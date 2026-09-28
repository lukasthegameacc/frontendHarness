#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/codex-trust-hooks.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
HOOKS="$SANDBOX/hooks.json"
CONFIG="$SANDBOX/codex/config.toml"

# Expected hashes were written by codex-cli 0.157.1's TUI trust review for oh-my-codex.
cat > "$HOOKS" <<'JSON'
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "node \"${PLUGIN_ROOT}/hooks/codex-native-hook.mjs\""}], "matcher": "startup|resume|clear"}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "node \"${PLUGIN_ROOT}/hooks/codex-native-hook.mjs\""}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "node \"${PLUGIN_ROOT}/hooks/codex-native-hook.mjs\"", "timeout": 30}]}]
  }
}
JSON

mkdir -p "$(dirname "$CONFIG")"
cat > "$CONFIG" <<'TOML'
model = "x"

[hooks.state."omx@local:hooks/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:stale"
enabled = false
TOML

python3 "$SCRIPT" "$HOOKS" "omx@local:hooks/hooks.json" "$CONFIG" >/dev/null
python3 "$SCRIPT" "$HOOKS" "omx@local:hooks/hooks.json" "$CONFIG" >/dev/null

expect_hash() {
  local key="$1" hash="$2"
  grep -A1 -Fx "[hooks.state.\"omx@local:hooks/hooks.json:$key\"]" "$CONFIG" | grep -qFx "trusted_hash = \"$hash\""
}

expect_hash session_start:0:0 sha256:c70df1f988a6965eb9d0fbdbfeaf84a609c98a9e24567dd1eb140cd6bf8e49f9
expect_hash pre_tool_use:0:0 sha256:0beadaffc3fbe7daf525b5f470271fd9652bbb6a681827f62ae519aa585114fa
expect_hash stop:0:0 sha256:216a53a71d5c9819f0fdbbbbf869c4f8d9455e742dad9e0f1d91f3d67dbba2ff
grep -qFx 'enabled = false' "$CONFIG"
grep -qFx 'model = "x"' "$CONFIG"
[[ "$(grep -c '^\[hooks.state' "$CONFIG")" == 3 ]]

echo "ok"
