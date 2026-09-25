#!/usr/bin/env bash
# auto-merge-sensitive-paths.test.sh — guards the Tier-3 "prd/ is sensitive"
# classifier in .github/workflows/auto-merge.yml. A PR touching prd/ must be
# forced to needs-review and never auto-merge, regardless of its commit
# prefix — see the prd-manager skill (.claude/skills/prd-manager/SKILL.md §6):
# a grooming-only PRD PR can still change scope under the hood (flipping
# `status` to Superseded/Deprecated hides FRs from `board.sh prd-scan`;
# adding FR ids to a previously-unnumbered PRD creates real FEATURES-lane
# work).
#
# This reads the PRD_SENSITIVE_PATTERN value OUT of the workflow file (never
# a copy pasted in here) so it cannot silently drift from what actually ships
# in CI, and runs the real `grep -qE` the workflow itself runs, against the
# real newline-joined path list shape `gh pr view --json files --jq
# '.files[].path'` produces.
#
# Run: bash scripts/dev/board/tests/auto-merge-sensitive-paths.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/auto-merge.yml"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== auto-merge.yml Tier-3 sensitive-path classifier (prd/ gate) ==="

# extract_pattern <file> — the single-quoted value of the
# PRD_SENSITIVE_PATTERN='...' assignment line in the given workflow file.
extract_pattern() {
  local file="$1" line
  line="$(grep -c "^ *PRD_SENSITIVE_PATTERN='" "$file")"
  if [ "$line" != "1" ]; then
    echo "" # signal failure to the caller; count mismatch is asserted separately
    return
  fi
  grep "^ *PRD_SENSITIVE_PATTERN='" "$file" | sed -E "s/^ *PRD_SENSITIVE_PATTERN='([^']*)'.*/\1/"
}

# is_sensitive <pattern> <file...> — mirrors the workflow exactly: a
# newline-joined changed-file list (the shape `gh pr view --json files --jq
# '.files[].path'` produces) piped into `grep -qE "$pattern"`.
is_sensitive() {
  local pattern="$1"; shift
  printf '%s\n' "$@" | grep -qE "$pattern"
}

n_lines="$(grep -c "^ *PRD_SENSITIVE_PATTERN='" "$WORKFLOW")"
if [ "$n_lines" != "1" ]; then
  fail "expected exactly one PRD_SENSITIVE_PATTERN assignment in auto-merge.yml, found ${n_lines} (classifier moved, renamed or duplicated — update this test, don't delete it)"
else
  pass "found exactly one PRD_SENSITIVE_PATTERN assignment in auto-merge.yml"
fi

PATTERN="$(extract_pattern "$WORKFLOW")"
[ -n "$PATTERN" ] && pass "extracted a non-empty pattern: ${PATTERN}" \
  || fail "could not extract PRD_SENSITIVE_PATTERN's value from auto-merge.yml"

# want, why, files...
check_case() {
  local want="$1" why="$2"; shift 2
  local got=1
  is_sensitive "$PATTERN" "$@" && got=0
  if [ "$got" = "$want" ]; then
    pass "$why"
  else
    fail "$why (pattern=[$PATTERN] files=[$*] want_sensitive=$([ "$want" = 0 ] && echo true || echo false))"
  fi
}

check_case 0 "a new PRD must never auto-merge" "prd/2026-09-25-example.md"
check_case 0 "the shared index prd/00_index.md is sensitive too" "prd/00_index.md"
check_case 0 "nested prd/ paths are still caught" "prd/tasks/some_feature_tasks.md"
check_case 0 "one sensitive file among several is enough" "src/app.ts" "prd/2026-09-25-example.md"

check_case 1 "docs/decisions is not prd/ and not otherwise sensitive" "docs/decisions/0099-example.md"
check_case 1 "ordinary app code stays non-sensitive" "src/app.ts"
check_case 1 "a plain root doc is not sensitive" "README.md"
check_case 1 "a file merely containing 'prd' mid-path is not prd/ itself" "src/prd/helper.ts"

# ---------------------------------------------------------------------------
# MUTATION CHECK: patch a disposable copy of auto-merge.yml so the pattern
# can never match anything real, and confirm the previously-sensitive case
# above flips to non-sensitive — proving the checks above are actually
# exercising the real workflow's pattern, not passing vacuously.
# ---------------------------------------------------------------------------
MUTANT="$WORK/auto-merge.mutant.yml"
python3 -c '
import sys
src = open(sys.argv[1]).read()
old = "PRD_SENSITIVE_PATTERN=%s^prd/%s" % ("\x27", "\x27")
new = "PRD_SENSITIVE_PATTERN=%s^THIS-PATTERN-CAN-NEVER-MATCH-ANYTHING/%s" % ("\x27", "\x27")
if old not in src:
    sys.exit(2)
open(sys.argv[2], "w").write(src.replace(old, new))
' "$WORKFLOW" "$MUTANT"
mutant_rc=$?

if [ "$mutant_rc" -ne 0 ]; then
  fail "MUTATION CHECK: could not locate PRD_SENSITIVE_PATTERN='^prd/' in auto-merge.yml to mutate (source drifted from the expected text)"
else
  MUT_PATTERN="$(extract_pattern "$MUTANT")"
  if is_sensitive "$MUT_PATTERN" "prd/2026-09-25-example.md"; then
    fail "MUTATION CHECK: breaking the pattern should have made prd/2026-09-25-example.md non-sensitive, but it still matched"
  else
    pass "MUTATION CHECK: breaking the pattern makes a real PRD path stop matching (the prd/ gate is load-bearing)"
  fi
fi

print_summary "auto-merge.yml sensitive-path classifier (prd/ gate)"
