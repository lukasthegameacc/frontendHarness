#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"

# Codex passes file paths directly for some tools and a patch command for apply_patch.
FILE_PATHS="$(printf '%s' "$INPUT" | jq -r '
  .tool_input as $input
  | [
      $input.file_path?,
      $input.path?,
      $input.target_file?,
      (($input.command? // "") | [scan("(?m)^\\*\\*\\* (?:Update|Add|Delete) File: (.+)$")]),
      (($input.command? // "") | [scan("(?m)^\\*\\*\\* Move to: (.+)$")])
    ]
  | flatten
  | map(select(type == "string" and length > 0))
  | .[]
')"

# ponytail: guards Codex file-edit tools only; add command-aware checks if shell/MCP writes need blocking.
while IFS= read -r FILE_PATH; do
  [ -n "$FILE_PATH" ] || continue
  BASENAME="$(basename "$FILE_PATH")"

  # .env.example 는 허용
  [[ "$BASENAME" == ".env.example" ]] && continue

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
done <<< "$FILE_PATHS"

exit 0
