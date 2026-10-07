#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mcp.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
STUB_BIN="$SANDBOX/bin"
CALL_LOG="$SANDBOX/calls.log"
mkdir -p "$STUB_BIN" "$SANDBOX/home"

for name in codex claude; do
  printf '#!/usr/bin/env bash\nprintf "%%s|" %s "$@" >> "%s"; echo >> "%s"\n' "$name" "$CALL_LOG" "$CALL_LOG" > "$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
done

run() { HOME="$SANDBOX/home" XDG_STATE_HOME="$SANDBOX/state" PATH="$STUB_BIN:$PATH" "$SCRIPT" "$@"; }

expect_calls() {
  [[ "$(cat "$CALL_LOG")" == "$(printf '%s\n' "$@")" ]] || {
    echo "unexpected calls:" >&2; cat "$CALL_LOG" >&2; exit 1
  }
}

# HTTP server with a bearer token: Claude gets headers only, Codex gets the env var flag.
: > "$CALL_LOG"
run claude enable glitchtip
expect_calls 'claude|mcp|add-json|-s|user|glitchtip|{"type":"http","url":"http://localhost:38088/mcp","headers":{"Authorization":"Bearer ${GLITCHTIP_MCP_TOKEN}"}}|'
: > "$CALL_LOG"
run codex enable glitchtip
expect_calls 'codex|mcp|add|glitchtip|--url|http://localhost:38088/mcp|--bearer-token-env-var|GLITCHTIP_MCP_TOKEN|'

# stdio server: literal env kept, "${VAR}" pass-through dropped for Codex.
: > "$CALL_LOG"
run codex enable aws-eks
expect_calls 'codex|mcp|add|aws-eks|--env|FASTMCP_LOG_LEVEL=ERROR|--|uvx|awslabs.eks-mcp-server@latest|--allow-write|--allow-sensitive-data-access|'

# disable with no names removes every catalog server.
: > "$CALL_LOG"
run claude disable
[[ "$(wc -l < "$CALL_LOG")" -eq "$(jq '.mcpServers | length' "$(dirname "$SCRIPT")/../mcp/servers.json")" ]]

! run claude enable nope 2>/dev/null
echo "ok"
