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
DEPS=("ponytail@ponytail DietrichGebert/ponytail")

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
  for dep in "${DEPS[@]}"; do
    read -r id src <<<"$dep"
    codex plugin marketplace add "$src" --json
    out="$(codex plugin add "$id" --json)"
    echo "$out"
    trust_codex_hooks "$(jq -r '.installedPath' <<<"$out")" "$id"
  done
}

# Claude installs dependencies itself, but only from marketplaces it already knows.
add_claude_dep_marketplaces() {
  local dep id src
  for dep in "${DEPS[@]}"; do
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
        claude plugin details "$PLUGIN_ID"
        ;;
      remove)
        claude plugin disable "$PLUGIN_ID"
        ;;
      reload)
        add_claude_dep_marketplaces
        claude plugin marketplace update "$MARKETPLACE_NAME" || true
        claude plugin update "$PLUGIN_ID" || true
        claude plugin details "$PLUGIN_ID"
        ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
