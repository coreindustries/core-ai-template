#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# assert-no-plaintext-env.sh
# -----------------------------------------------------------------------------
# Blocks any commit that adds or modifies a plaintext .env file.
# Only .env.tpl, .env.example, .env.sample, .env.template are allowed.
#
# Enforces .claude/rules/secrets-hygiene.md.
# -----------------------------------------------------------------------------
set -euo pipefail

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
RESET=$'\033[0m'

# If called from husky/lint-staged with staged files: use git diff.
# If called standalone: scan the working tree.
if git rev-parse --git-dir > /dev/null 2>&1; then
  STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
else
  STAGED=""
fi

if [[ -n "$STAGED" ]]; then
  TARGETS=$(echo "$STAGED" | grep -E '(^|/)\.env(\.|$)' || true)
else
  TARGETS=$(find . -type f -name '.env*' \
    -not -path './node_modules/*' \
    -not -path './.git/*' \
    -not -path './venv/*' \
    -not -path './.venv/*' \
    2>/dev/null || true)
fi

if [[ -z "$TARGETS" ]]; then
  exit 0
fi

OFFENDERS=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  base=$(basename "$file")
  case "$base" in
    .env.tpl|.env.example|.env.sample|.env.template)
      # Template files are allowed — but verify they don't contain real values
      # (heuristic: lines with = followed by something that looks like a live
      # secret and isn't a reference / placeholder).
      if [[ -f "$file" ]] && grep -Eq '^[A-Z_][A-Z0-9_]*=[^#]*[A-Za-z0-9_/+=-]{32,}' "$file" 2>/dev/null; then
        # Allow-list: reference patterns and obvious placeholders
        if ! grep -Eq '^[A-Z_][A-Z0-9_]*=(op://|arn:aws:|sops://|vault:|\$\{|\{\{|.*placeholder|.*example|.*changeme|.*your[-_])' "$file"; then
          OFFENDERS+=("$file (template contains what looks like a real value)")
        fi
      fi
      ;;
    *)
      # Any other .env* file is forbidden
      OFFENDERS+=("$file")
      ;;
  esac
done <<< "$TARGETS"

if [[ ${#OFFENDERS[@]} -gt 0 ]]; then
  echo "${RED}ERROR:${RESET} plaintext .env files detected."
  echo ""
  for f in "${OFFENDERS[@]}"; do
    echo "  ${YELLOW}✗${RESET} $f"
  done
  echo ""
  echo "This repo forbids plaintext secrets on disk in any environment."
  echo "See ${YELLOW}.claude/rules/secrets-hygiene.md${RESET} for the full directive."
  echo ""
  echo "To fix:"
  echo "  1. Move the values to AWS SSM / Secrets Manager:"
  echo "       chamber write <service-name> <key> '<value>'"
  echo "  2. Add a reference line to .env.tpl."
  echo "  3. Delete the plaintext file:"
  echo "       rm ${OFFENDERS[0]%% *}"
  echo "  4. Run via the wrapper:"
  echo "       make dev"
  echo ""
  echo "If the file was committed in history, rotate the credentials immediately."
  echo "See docs/runbooks/secret-leak.md"
  exit 1
fi

exit 0
