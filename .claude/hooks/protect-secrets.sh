#!/bin/bash
# Block access to secret and credential files
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Blocked patterns
BLOCKED_PATTERNS=(
  ".env"
  ".key"
  ".pem"
  "credentials.json"
  "secrets.json"
  "config/secrets/"
  "auth-config."
  "database-passwords."
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "BLOCKED: Cannot access secret/credential file: $FILE_PATH" >&2
    exit 2
  fi
done

exit 0
