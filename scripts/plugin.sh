#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <codex|claude> <install|remove|reload>" >&2
  exit 1
}

TOOL="${1:-}"
ACTION="${2:-}"
[ -n "$TOOL" ] && [ -n "$ACTION" ] || usage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/plugin.json")"
MARKETPLACE_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/marketplace.json")"
PLUGIN_ID="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

# "<plugin>@<marketplace> <marketplace source>". Claude also needs each in .claude-plugin/plugin.json "dependencies".
CODEX_DEPS=("ponytail@ponytail DietrichGebert/ponytail")
# impeccable ships no Codex plugin, so install_codex_deps puts its skill in ~/.agents/skills via its own CLI.
CLAUDE_DEPS=("${CODEX_DEPS[@]}" "impeccable@impeccable pbakaus/impeccable")

# Codex skips plugin hooks until trusted; write the trust hashes it would write after TUI review.
trust_codex_hooks() {
  local root="$1" id="$2" hooks_rel
  hooks_rel="$(jq -r '.hooks // empty' "$root/.codex-plugin/plugin.json")"
  [ -n "$hooks_rel" ] || return 0
  hooks_rel="${hooks_rel#./}"
  python3 "$ROOT_DIR/scripts/codex-trust-hooks.py" \
    "$root/$hooks_rel" "$id:$hooks_rel" "${CODEX_HOME:-$HOME/.codex}/config.toml"
}

install_codex_deps() {
  local dep id src out
  for dep in "${CODEX_DEPS[@]}"; do
    read -r id src <<<"$dep"
    codex plugin marketplace add "$src" --json
    out="$(codex plugin add "$id" --json)"
    echo "$out"
    trust_codex_hooks "$(jq -r '.installedPath' <<<"$out")" "$id"
  done
  # --no-hooks: its Codex hook is project-local (.codex/hooks.json), not something a user-scope install can set up.
  npx -y impeccable install --providers=codex --scope=user --yes --no-hooks
}

remove_codex_deps() {
  local dep id src
  for dep in "${CODEX_DEPS[@]}"; do
    read -r id src <<<"$dep"
    codex plugin remove "$id" --json
  done
  # impeccable's CLI has no uninstall; this is the folder install_codex_deps created.
  rm -rf "$HOME/.agents/skills/impeccable"
}

# Not --prune: it skips deps the user had installed by hand before (no "auto" flag).
remove_claude_deps() {
  local dep id src
  for dep in "${CLAUDE_DEPS[@]}"; do
    read -r id src <<<"$dep"
    claude plugin uninstall "$id"
  done
}

# claude.ai's Notion connector is tied to the claude.ai login's Notion account; block it so
# mcp/servers.json's notion (own OAuth, any account) is the only one. User settings honor deniedMcpServers.
DENIED_CONNECTOR="claude.ai Notion"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

edit_claude_settings() {
  local tmp
  [ -f "$CLAUDE_SETTINGS" ] || echo '{}' > "$CLAUDE_SETTINGS"
  tmp="$(mktemp)"
  jq --arg n "$DENIED_CONNECTOR" "$1" "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
}
deny_claude_connector() { edit_claude_settings '.deniedMcpServers = ((.deniedMcpServers // []) - [{serverName: $n}] + [{serverName: $n}])'; }
allow_claude_connector() { edit_claude_settings '.deniedMcpServers = ((.deniedMcpServers // []) - [{serverName: $n}]) | if .deniedMcpServers == [] then del(.deniedMcpServers) else . end'; }

# Claude installs dependencies itself, but only from marketplaces it already knows.
add_claude_dep_marketplaces() {
  local dep id src
  for dep in "${CLAUDE_DEPS[@]}"; do
    read -r id src <<<"$dep"
    claude plugin marketplace add "$src"
  done
}

case "$TOOL" in
  codex)
    case "$ACTION" in
      install)
        codex plugin marketplace add "$ROOT_DIR" --json
        codex plugin add "$PLUGIN_ID" --json
        trust_codex_hooks "$ROOT_DIR" "$PLUGIN_ID"
        install_codex_deps
        codex plugin list | grep "$PLUGIN_NAME"
        ;;
      remove)
        codex plugin remove "$PLUGIN_ID" --json
        remove_codex_deps
        "$ROOT_DIR/scripts/mcp.sh" codex disable
        "$ROOT_DIR/scripts/glitchtip-forward.sh" stop
        ;;
      reload)
        codex plugin remove "$PLUGIN_ID" --json || true
        rm -rf "$HOME/.codex/plugins/cache/${MARKETPLACE_NAME}/${PLUGIN_NAME}"
        codex plugin marketplace add "$ROOT_DIR" --json
        codex plugin add "$PLUGIN_ID" --json
        trust_codex_hooks "$ROOT_DIR" "$PLUGIN_ID"
        install_codex_deps
        ;;
      *) usage ;;
    esac
    ;;
  claude)
    case "$ACTION" in
      install)
        add_claude_dep_marketplaces
        claude plugin marketplace add "$ROOT_DIR"
        claude plugin install "$PLUGIN_ID"
        claude plugin enable "$PLUGIN_ID"
        deny_claude_connector
        claude plugin details "$PLUGIN_ID"
        ;;
      remove)
        claude plugin uninstall "$PLUGIN_ID"
        remove_claude_deps
        "$ROOT_DIR/scripts/mcp.sh" claude disable
        allow_claude_connector
        "$ROOT_DIR/scripts/glitchtip-forward.sh" stop
        ;;
      reload)
        add_claude_dep_marketplaces
        claude plugin marketplace update "$MARKETPLACE_NAME" || true
        # `plugin update` is a no-op while the version stays 0.1.0, so reinstall to refresh the cache.
        claude plugin uninstall "$PLUGIN_ID" || true
        claude plugin install "$PLUGIN_ID"
        deny_claude_connector
        claude plugin details "$PLUGIN_ID"
        ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
