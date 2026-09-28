#!/usr/bin/env bash
set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/block-env-edits.sh"

expect_deny() {
  local input="$1"
  printf '%s' "$input" | "$HOOK" \
    | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

expect_allow() {
  local input="$1"
  local output
  output="$(printf '%s' "$input" | "$HOOK")"
  [[ -z "$output" ]]
}

expect_deny '{"tool_input":{"file_path":".env.local"}}'
expect_deny '{"tool_input":{"command":"*** Begin Patch\n*** Update File: .env.example\n*** Update File: .env.local\n*** End Patch"}}'
expect_allow '{"tool_input":{"file_path":".env.example"}}'
