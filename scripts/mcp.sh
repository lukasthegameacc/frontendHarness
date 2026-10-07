#!/usr/bin/env bash
# MCP servers in mcp/servers.json are off by default; this adds/removes them in the user-scope config.
# (Claude plugin .mcp.json servers can't default to disabled globally, so the plugin doesn't ship one.)
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <codex|claude> <list|enable|disable> [server...]" >&2
  echo "       enable needs server names; disable with none removes every catalog server" >&2
  exit 1
}

TOOL="${1:-}"
ACTION="${2:-}"
[ -n "$TOOL" ] && [ -n "$ACTION" ] || usage
shift 2

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/mcp/servers.json"
FORWARD="$ROOT_DIR/scripts/glitchtip-forward.sh"

def() {
  jq -e --arg n "$1" '.mcpServers[$n]' "$CATALOG" || { echo "unknown server: $1 (see: $(basename "$0") $TOOL list)" >&2; exit 1; }
}

enable_claude() {
  # bearer_token_env_var is the Codex spelling of the same token; Claude uses headers.
  claude mcp add-json -s user "$1" "$(def "$1" | jq -c 'del(.bearer_token_env_var)')"
}

enable_codex() {
  local d args=()
  d="$(def "$1")"
  if jq -e '.url' <<<"$d" >/dev/null; then
    args+=(--url "$(jq -r '.url' <<<"$d")")
    jq -e '.bearer_token_env_var' <<<"$d" >/dev/null && args+=(--bearer-token-env-var "$(jq -r '.bearer_token_env_var' <<<"$d")")
  else
    # Codex doesn't expand "${VAR}" in env, so pass-through entries are dropped and inherit instead.
    while IFS= read -r kv; do args+=(--env "$kv"); done < <(jq -r '.env // {} | to_entries[] | select(.value | test("^\\$\\{\\w+\\}$") | not) | "\(.key)=\(.value)"' <<<"$d")
    args+=(-- "$(jq -r '.command' <<<"$d")")
    while IFS= read -r a; do args+=("$a"); done < <(jq -r '.args // [] | .[]' <<<"$d")
  fi
  codex mcp add "$1" "${args[@]}"
}

disable() {
  case "$TOOL" in
    claude) claude mcp remove -s user "$1" ;;
    codex) codex mcp remove "$1" ;;
  esac
}

case "$TOOL" in claude|codex) ;; *) usage ;; esac

case "$ACTION" in
  list)
    jq -r '.mcpServers | keys[]' "$CATALOG"
    ;;
  enable)
    [ $# -gt 0 ] || usage
    for n in "$@"; do
      "enable_$TOOL" "$n"
      if [ "$n" = glitchtip ]; then "$FORWARD" start; fi
    done
    ;;
  disable)
    [ $# -gt 0 ] || set -- $(jq -r '.mcpServers | keys[]' "$CATALOG")
    for n in "$@"; do
      disable "$n" >/dev/null 2>&1 || true
      # Keep the tunnel while the other tool still uses it.
      if [ "$n" = glitchtip ] && ! "$FORWARD" enabled; then "$FORWARD" stop; fi
    done
    ;;
  *) usage ;;
esac
