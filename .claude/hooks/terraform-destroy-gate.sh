#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# Only check Bash tool calls with a command
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block terraform destroy - require explicit user confirmation first
if echo "$COMMAND" | grep -qE 'terraform\s+destroy'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "terraform destroy는 매우 위험한 작업입니다. 사용자에게 먼저 영향 범위를 설명하고 확인을 받으세요."
    }
  }'
  exit 0
fi

exit 0
