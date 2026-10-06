#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/plugin.sh"
PLUGIN_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/plugin.json")"
MARKETPLACE_NAME="$(jq -r '.name' "$ROOT_DIR/.claude-plugin/marketplace.json")"
PLUGIN_ID="${PLUGIN_NAME}@${MARKETPLACE_NAME}"
DEP_ID="ponytail@ponytail"
DEP_SRC="DietrichGebert/ponytail"
CLAUDE_DEP_ID="impeccable@impeccable"
CLAUDE_DEP_SRC="pbakaus/impeccable"
IMPECCABLE_CODEX="npx -y impeccable install --providers=codex --scope=user --yes --no-hooks"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
STUB_BIN="$SANDBOX/bin"
FAKE_HOME="$SANDBOX/home"
INSTALLED="$SANDBOX/installed"
CALL_LOG="$SANDBOX/calls.log"
mkdir -p "$STUB_BIN" "$FAKE_HOME"

# Fake installed copy of the dependency so its hooks can be trusted.
mkdir -p "$INSTALLED/ponytail/.codex-plugin" "$INSTALLED/ponytail/hooks"
echo '{"name":"ponytail","hooks":"./hooks/codex-hooks.json"}' > "$INSTALLED/ponytail/.codex-plugin/plugin.json"
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"true"}]}]}}' > "$INSTALLED/ponytail/hooks/codex-hooks.json"

# codex/claude are stubbed so this test never touches the real CLIs or ~/.codex.
for name in codex claude npx; do
  cat > "$STUB_BIN/$name" <<STUB
#!/usr/bin/env bash
echo "$name \$*" >> "$CALL_LOG"
[[ "\$*" == *"plugin list"* ]] && echo "$PLUGIN_NAME"
[[ "\$1 \$2" == "plugin add" ]] && echo "{\"installedPath\":\"$INSTALLED/\${3%@*}\"}"
exit 0
STUB
  chmod +x "$STUB_BIN/$name"
done

run() {
  HOME="$FAKE_HOME" CODEX_HOME="$FAKE_HOME/.codex" PATH="$STUB_BIN:$PATH" "$SCRIPT" "$@"
}

expect_usage_error() {
  local out
  if out="$("$SCRIPT" "$@" 2>&1)"; then
    echo "expected usage error for args: $*" >&2
    exit 1
  fi
  [[ "$out" == usage:* ]]
}

expect_calls() {
  [[ "$(cat "$CALL_LOG")" == "$(printf '%s\n' "$@")" ]] || {
    echo "unexpected calls:" >&2; cat "$CALL_LOG" >&2; exit 1
  }
}

trust_count() {
  grep -c "^\[hooks.state.\"$1:" "$FAKE_HOME/.codex/config.toml"
}

expect_usage_error
expect_usage_error codex
expect_usage_error codex bogus
expect_usage_error bogus install

: > "$CALL_LOG"
run codex install >/dev/null
expect_calls \
  "codex plugin marketplace add $ROOT_DIR --json" \
  "codex plugin add $PLUGIN_ID --json" \
  "codex plugin marketplace add $DEP_SRC --json" \
  "codex plugin add $DEP_ID --json" \
  "$IMPECCABLE_CODEX" \
  "codex plugin list"
[[ "$(trust_count "$PLUGIN_ID:hooks/hooks.json:pre_tool_use")" == 1 ]]
[[ "$(trust_count "$DEP_ID:hooks/codex-hooks.json:session_start")" == 1 ]]
grep -qE '^trusted_hash = "sha256:[0-9a-f]{64}"$' "$FAKE_HOME/.codex/config.toml"

: > "$CALL_LOG"
mkdir -p "$FAKE_HOME/.agents/skills/impeccable"
run codex remove >/dev/null
expect_calls \
  "codex plugin remove $PLUGIN_ID --json" \
  "codex plugin remove $DEP_ID --json"
[[ ! -e "$FAKE_HOME/.agents/skills/impeccable" ]]

: > "$CALL_LOG"
CACHE_DIR="$FAKE_HOME/.codex/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME"
mkdir -p "$CACHE_DIR" && touch "$CACHE_DIR/marker"
run codex reload >/dev/null
expect_calls \
  "codex plugin remove $PLUGIN_ID --json" \
  "codex plugin marketplace add $ROOT_DIR --json" \
  "codex plugin add $PLUGIN_ID --json" \
  "codex plugin marketplace add $DEP_SRC --json" \
  "codex plugin add $DEP_ID --json" \
  "$IMPECCABLE_CODEX"
[[ ! -e "$CACHE_DIR" ]]
[[ "$(trust_count "$PLUGIN_ID")" == 1 ]]
[[ "$(trust_count "$DEP_ID")" == 1 ]]

: > "$CALL_LOG"
run claude install >/dev/null
expect_calls \
  "claude plugin marketplace add $DEP_SRC" \
  "claude plugin marketplace add $CLAUDE_DEP_SRC" \
  "claude plugin marketplace add $ROOT_DIR" \
  "claude plugin install $PLUGIN_ID" \
  "claude plugin enable $PLUGIN_ID" \
  "claude plugin details $PLUGIN_ID"

: > "$CALL_LOG"
run claude remove >/dev/null
expect_calls \
  "claude plugin uninstall $PLUGIN_ID" \
  "claude plugin uninstall $DEP_ID" \
  "claude plugin uninstall $CLAUDE_DEP_ID"

: > "$CALL_LOG"
run claude reload >/dev/null
expect_calls \
  "claude plugin marketplace add $DEP_SRC" \
  "claude plugin marketplace add $CLAUDE_DEP_SRC" \
  "claude plugin marketplace update $MARKETPLACE_NAME" \
  "claude plugin update $PLUGIN_ID" \
  "claude plugin details $PLUGIN_ID"

for id in "$DEP_ID" "$CLAUDE_DEP_ID"; do
  jq -e --arg n "${id%@*}" --arg m "${id#*@}" \
    '.dependencies[] | select(.name == $n and .marketplace == $m)' \
    "$ROOT_DIR/.claude-plugin/plugin.json" >/dev/null
  jq -e --arg m "${id#*@}" '.allowCrossMarketplaceDependenciesOn | index($m)' \
    "$ROOT_DIR/.claude-plugin/marketplace.json" >/dev/null
done

echo "ok"
