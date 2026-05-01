#!/bin/bash
# scripts/precommit-secret-patterns.sh — blocks commits containing secrets
#
# Regex backstop that always runs (no gitleaks dependency). Complements
# `gitleaks protect --staged` in .husky/pre-commit so a missing or broken
# gitleaks install can't silently let secrets through.

PATTERNS=(
  'sk-ant-'                            # Anthropic API keys
  'sk-live-'                           # Stripe live keys (new format)
  'sk_live_'                           # Stripe live keys (legacy format)
  'ghp_'                               # GitHub personal tokens
  'gho_'                               # GitHub OAuth tokens
  'AKIA[0-9A-Z]{16}'                   # AWS access keys (full format)
  'xox[bpors]-'                        # Slack tokens
  'SG\.[A-Za-z0-9_-]{22}\.'            # SendGrid keys (full format)
  '-----BEGIN [A-Z ]*PRIVATE KEY-----' # PEM private key header
)
# Note: JWTs (eyJ...) are intentionally omitted — too noisy for regex matching.
# Use gitleaks (scripts/scan-secrets.sh) for entropy/context-aware detection.

BLOCKED_NAMES=('.env' 'credentials.json' 'id_rsa' 'id_ed25519' 'id_dsa' 'id_ecdsa')
BLOCKED_EXTS=('pem' 'key' 'p12' 'pfx')

# Exclude the secret-pattern scripts themselves so their pattern
# definitions don't match against the staged diff.
EXCLUDES=(
  ':!scripts/precommit-secret-patterns.sh'
  ':!scripts/prepush-secret-check.sh'
)

for pattern in "${PATTERNS[@]}"; do
  if git diff --cached --diff-filter=ACM -- "${EXCLUDES[@]}" | grep -qE -- "$pattern"; then
    echo "BLOCKED: Found potential secret matching '$pattern'"
    echo "Remove the secret and try again."
    exit 1
  fi
done

while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")
  for name in "${BLOCKED_NAMES[@]}"; do
    if [ "$base" = "$name" ]; then
      echo "BLOCKED: Attempted to commit sensitive file: $f"
      exit 1
    fi
  done
  ext="${base##*.}"
  if [ "$ext" != "$base" ]; then
    for blocked_ext in "${BLOCKED_EXTS[@]}"; do
      if [ "$ext" = "$blocked_ext" ]; then
        echo "BLOCKED: Attempted to commit sensitive file: $f"
        exit 1
      fi
    done
  fi
done < <(git diff --cached --name-only --diff-filter=ACM)

echo "Pre-commit security check passed."
exit 0
