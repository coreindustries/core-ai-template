#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# assert-no-secrets.sh
# -----------------------------------------------------------------------------
# Used by `make test-hermetic` to confirm a test run has no production
# credentials present in the environment. Prevents a unit test from
# accidentally hitting production if a developer runs it under the wrapper
# by mistake.
# -----------------------------------------------------------------------------
set -euo pipefail

RED=$'\033[0;31m'
RESET=$'\033[0m'

LEAKED=()

# Explicit allowlist of clearly-non-production value shapes. Anything matching
# one of these skips the leak check. Kept narrow on purpose — loose substring
# matches (e.g. bare "test") let real secrets through if they happen to
# contain the substring.
_is_placeholder() {
  local v="$1"
  [[ -z "$v" ]] && return 0
  # Empty / known placeholders
  [[ "$v" == *placeholder* ]] && return 0
  [[ "$v" == *CHANGEME* || "$v" == *changeme* ]] && return 0
  [[ "$v" == *your-api-key* || "$v" == *your_api_key* ]] && return 0
  [[ "$v" == *fake-* || "$v" == *-fake || "$v" == *-mock-* ]] && return 0
  [[ "$v" == *example.com* || "$v" == *example.org* ]] && return 0
  # Local DB shapes only
  [[ "$v" == postgres://test:test@localhost* ]] && return 0
  [[ "$v" == postgresql://test:test@localhost* ]] && return 0
  [[ "$v" == postgres://postgres:postgres@localhost* ]] && return 0
  [[ "$v" == postgresql://postgres:postgres@localhost* ]] && return 0
  [[ "$v" == redis://localhost* || "$v" == redis://127.0.0.1* ]] && return 0
  # Explicit test prefix/suffix markers
  [[ "$v" == sk-*-placeholder-* ]] && return 0
  [[ "$v" == test_* || "$v" == *_test_* || "$v" == *_test ]] && return 0
  return 1
}

while IFS='=' read -r key _; do
  case "$key" in
    *_SECRET|*_KEY|*_TOKEN|*_PASSWORD|*_CREDENTIAL*|DATABASE_URL|REDIS_URL)
      val="${!key:-}"
      if _is_placeholder "$val"; then
        continue
      fi
      LEAKED+=("$key")
      ;;
  esac
done < <(env)

if [[ ${#LEAKED[@]} -gt 0 ]]; then
  echo "${RED}ERROR:${RESET} production-looking secrets detected in test environment:"
  for k in "${LEAKED[@]}"; do
    echo "  - $k"
  done
  echo ""
  echo "Hermetic tests must not run with real credentials loaded."
  echo "Run without the wrapper: 'make test-hermetic' instead of 'make test'."
  exit 1
fi

exit 0
