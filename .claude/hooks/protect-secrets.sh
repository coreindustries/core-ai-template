#!/bin/bash
# Block access to secret and credential files.
# Patterns are anchored to filename boundaries to avoid false positives on
# unrelated files that happen to contain these substrings
# (e.g. envoy-config.yaml, service.keys.yaml, monkey.tmp).
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

base=$(basename "$FILE_PATH")

# Reference/template files are always safe — they contain SSM paths and
# placeholder values only, never real secrets. Allow before pattern check.
case "$base" in
  .env.tpl|.env.example|.env.sample|.env.template) exit 0 ;;
esac

_blocked() {
  local reason="$1"
  echo "BLOCKED: $reason: $FILE_PATH" >&2
  exit 2
}

# .env and .env.* (but not the template files allowed above)
case "$base" in
  .env|.env.*) _blocked "plaintext .env file" ;;
esac

# Private keys and certificates (anchored to filename extension)
case "$base" in
  *.key|*.pem|*.p12|*.pfx|*.jks|*.keystore) _blocked "private key / certificate" ;;
esac

# Known credential files (exact basenames)
case "$base" in
  credentials.json|secrets.json|service-account.json|gha-creds.json)
    _blocked "known credential file" ;;
  auth-config|auth-config.*|database-passwords|database-passwords.*)
    _blocked "auth / password config" ;;
esac

# Credential directories anywhere in the path
case "$FILE_PATH" in
  */config/secrets/*|*/.aws/credentials|*/.aws/sso/cache/*|*/.ssh/*)
    _blocked "credential directory" ;;
  */.netrc|*/.npmrc|*/.pypirc|*/.docker/config.json|*/.kube/config)
    _blocked "package-manager / cluster credentials" ;;
esac

exit 0
