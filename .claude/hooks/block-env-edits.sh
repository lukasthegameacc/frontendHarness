#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '
  .tool_input.file_path //
  .tool_input.path //
  .tool_input.target_file //
  empty
')"

# 파일 경로를 못 찾으면 통과
if [ -z "${FILE_PATH:-}" ]; then
  exit 0
fi

BASENAME="$(basename "$FILE_PATH")"

# .env.example 는 허용
if [[ "$BASENAME" == ".env.example" ]]; then
  exit 0
fi

# 실제 비밀 파일 차단
if [[ "$BASENAME" == ".env" || "$BASENAME" == .env.* ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Editing .env secret files is blocked. Use Secret Manager or Parameter Store. .env.example is allowed."
    }
  }'
  exit 0
fi

exit 0