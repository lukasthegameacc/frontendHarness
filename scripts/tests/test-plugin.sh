#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/plugin.sh"
PLUGIN_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/plugin.json")"
MARKETPLACE_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/marketplace.json")"
PLUGIN_ID="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
STUB_BIN="$SANDBOX/bin"
FAKE_HOME="$SANDBOX/home"
CALL_LOG="$SANDBOX/calls.log"
mkdir -p "$STUB_BIN" "$FAKE_HOME"

# codex/claude are stubbed so this test never touches the real CLIs or ~/.codex.
for name in codex claude; do
  cat > "$STUB_BIN/$name" <<STUB
#!/usr/bin/env bash
echo "$name \$*" >> "$CALL_LOG"
[[ "\$*" == *"plugin list"* ]] && echo "$PLUGIN_NAME"
exit 0
STUB
  chmod +x "$STUB_BIN/$name"
done

run() {
  HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" "$SCRIPT" "$@"
}

expect_usage_error() {
  local out
  if out="$("$SCRIPT" "$@" 2>&1)"; then
    echo "expected usage error for args: $*" >&2
    exit 1
  fi
  [[ "$out" == usage:* ]]
}

expect_usage_error
expect_usage_error codex
expect_usage_error codex bogus
expect_usage_error bogus install

: > "$CALL_LOG"
run codex install >/dev/null
[[ "$(sed -n 1p "$CALL_LOG")" == "codex plugin marketplace add $ROOT_DIR --json" ]]
[[ "$(sed -n 2p "$CALL_LOG")" == "codex plugin add $PLUGIN_ID --json" ]]
[[ "$(sed -n 3p "$CALL_LOG")" == "codex plugin list" ]]

: > "$CALL_LOG"
run codex remove >/dev/null
[[ "$(cat "$CALL_LOG")" == "codex plugin remove $PLUGIN_ID --json" ]]

: > "$CALL_LOG"
CACHE_DIR="$FAKE_HOME/.codex/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME"
mkdir -p "$CACHE_DIR" && touch "$CACHE_DIR/marker"
run codex reload >/dev/null
[[ "$(sed -n 1p "$CALL_LOG")" == "codex plugin remove $PLUGIN_ID --json" ]]
[[ "$(sed -n 2p "$CALL_LOG")" == "codex plugin marketplace add $ROOT_DIR --json" ]]
[[ "$(sed -n 3p "$CALL_LOG")" == "codex plugin add $PLUGIN_ID --json" ]]
[[ ! -e "$CACHE_DIR" ]]

: > "$CALL_LOG"
run claude install >/dev/null
[[ "$(sed -n 1p "$CALL_LOG")" == "claude plugin marketplace add $ROOT_DIR" ]]
[[ "$(sed -n 2p "$CALL_LOG")" == "claude plugin install $PLUGIN_ID" ]]
[[ "$(sed -n 3p "$CALL_LOG")" == "claude plugin enable $PLUGIN_ID" ]]
[[ "$(sed -n 4p "$CALL_LOG")" == "claude plugin details $PLUGIN_ID" ]]

: > "$CALL_LOG"
run claude remove >/dev/null
[[ "$(cat "$CALL_LOG")" == "claude plugin disable $PLUGIN_ID" ]]

: > "$CALL_LOG"
run claude reload >/dev/null
[[ "$(sed -n 1p "$CALL_LOG")" == "claude plugin marketplace update $MARKETPLACE_NAME" ]]
[[ "$(sed -n 2p "$CALL_LOG")" == "claude plugin update $PLUGIN_ID" ]]
[[ "$(sed -n 3p "$CALL_LOG")" == "claude plugin details $PLUGIN_ID" ]]

echo "ok"
