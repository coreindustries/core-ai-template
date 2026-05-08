#!/bin/bash
# scripts/prepush-secret-check.sh — scan commits about to be pushed for secrets.
#
# Pre-push hooks read from stdin one line per ref being pushed:
#   <local-ref> <local-oid> <remote-ref> <remote-oid>
# For each ref, we derive the commit range that's new to the remote and run
# both gitleaks (if installed) and a regex backstop over that range.
#
# This catches what pre-commit misses: --no-verify commits, branches pushed
# from machines without husky installed, and old unscanned history.

set -uo pipefail

ZERO='0000000000000000000000000000000000000000'

PATTERNS=(
  'sk-ant-'
  'sk-live-'
  'sk_live_'
  'ghp_'
  'gho_'
  'AKIA[0-9A-Z]{16}'
  'xox[bpors]-'
  'SG\.[A-Za-z0-9_-]{22}\.'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

# Exclude the secret-pattern scripts and the doc that inlines them, so
# their pattern definitions don't match against scanned commits.
EXCLUDES=(
  ':!scripts/precommit-secret-patterns.sh'
  ':!scripts/prepush-secret-check.sh'
  ':!docs/adopt-best-practices.md'
)

scan_range() {
  # Args are passed to both `git log -p` and gitleaks --log-opts.
  local -a log_args=("$@")
  local range_str="${log_args[*]}"
  local found=0

  if command -v gitleaks &>/dev/null; then
    local -a cfg=()
    [ -f ".gitleaks.toml" ] && cfg=(--config=.gitleaks.toml)
    # gitleaks accepts pathspec exclusions appended to log-opts via -- separator.
    if ! gitleaks detect --no-banner \
        --log-opts="$range_str -- ${EXCLUDES[*]}" \
        ${cfg[@]+"${cfg[@]}"}; then
      found=1
    fi
  else
    echo "Warning: gitleaks not installed — running regex backstop only" >&2
    echo "  brew install gitleaks" >&2
  fi

  for pattern in "${PATTERNS[@]}"; do
    if git log -p "${log_args[@]}" -- "${EXCLUDES[@]}" 2>/dev/null | grep -qE -- "$pattern"; then
      echo "BLOCKED: pre-push found potential secret matching '$pattern' in range: $range_str"
      found=1
    fi
  done

  return $found
}

failed=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$local_sha" = "$ZERO" ] && continue   # branch deletion

  if [ "$remote_sha" = "$ZERO" ]; then
    # New branch on remote — scan commits not yet on any remote.
    scan_range "$local_sha" --not --remotes || failed=1
  else
    scan_range "$remote_sha..$local_sha" || failed=1
  fi
done

if [ $failed -ne 0 ]; then
  echo ""
  echo "Push blocked. Remove the secret(s) from the offending commits and try again."
  echo "Options:"
  echo "  - git rebase -i to edit/drop the commit"
  echo "  - rotate the leaked credential immediately if it was real"
  echo "  - false positive? add 'pragma: allowlist secret' or update .gitleaks.toml"
  exit 1
fi

echo "Pre-push security check passed."
exit 0
