#!/usr/bin/env bash
# assert-doc-ids.test.sh — unit tests for scripts/assert-doc-ids.sh against a
# REAL disposable temp git repo. No network calls.
#
# The gate: a PRD or ADR *added* on a branch must use a date+slug ID, never a
# sequential number. Existing numbered docs on the base are grandfathered.
#
# Run: bash scripts/dev/board/tests/assert-doc-ids.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../../.." && pwd)"
GATE="$REPO_ROOT/scripts/assert-doc-ids.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== assert-doc-ids.sh unit tests ==="

export GIT_AUTHOR_NAME="doc-ids-test" GIT_AUTHOR_EMAIL="doc-ids-test@example.invalid"
export GIT_COMMITTER_NAME="doc-ids-test" GIT_COMMITTER_EMAIL="doc-ids-test@example.invalid"

REPO="$WORK/repo"
git init -q "$REPO"
git -C "$REPO" symbolic-ref HEAD refs/heads/main
mkdir -p "$REPO/prd/tasks" "$REPO/docs/decisions"
# Grandfathered numbered docs + the non-ID files that live beside them.
for f in prd/05-legacy.md prd/00_index.md prd/_PRD_TEMPLATE.md \
         docs/decisions/0001-legacy.md docs/decisions/index.md docs/decisions/adr-template.md; do
  echo "x" > "$REPO/$f"
done
git -C "$REPO" add -A
git -C "$REPO" commit -q -m seed
BASE="$(git -C "$REPO" rev-parse HEAD)"

# case <name> <expect-exit> <file-to-add>...
# Each case branches fresh from BASE, adds the files, and runs the gate.
case_() {
  local name="$1" want="$2"; shift 2
  git -C "$REPO" checkout -q -B "case" "$BASE"
  for f in "$@"; do
    mkdir -p "$REPO/$(dirname "$f")"
    echo "new" > "$REPO/$f"
  done
  git -C "$REPO" add -A
  git -C "$REPO" commit -q --allow-empty -m "$name"
  local out rc
  out="$( cd "$REPO" && "$GATE" "$BASE" HEAD 2>&1 )"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    pass "$name (exit $rc)"
  else
    fail "$name: expected exit $want, got $rc — $out"
  fi
}

case_ "no doc changes passes"                    0
case_ "date+slug PRD passes"                     0 prd/2026-09-24-oauth-login.md
case_ "date+slug ADR passes"                     0 docs/decisions/2026-09-24-queue-backend.md
case_ "task files are not IDs"                   0 prd/tasks/oauth_tasks.md
case_ "template/index files are not IDs"         0 prd/00_roadmap.md prd/_task_template.md docs/decisions/README.md
case_ "new numbered PRD fails"                   1 prd/06-next-thing.md
case_ "new numbered ADR fails"                   1 docs/decisions/0002-next-thing.md
case_ "PRD- prefixed numbered fails"             1 prd/PRD-07-thing.md
case_ "uppercase slug fails"                     1 prd/2026-09-24-OAuth.md
case_ "one bad among good still fails"           1 prd/2026-09-24-good.md docs/decisions/0002-bad.md

# Grandfathering: editing an existing numbered doc is not an addition.
git -C "$REPO" checkout -q -B "case" "$BASE"
echo "edit" >> "$REPO/prd/05-legacy.md"
git -C "$REPO" commit -q -am "edit legacy"
if ( cd "$REPO" && "$GATE" "$BASE" HEAD >/dev/null 2>&1 ); then
  pass "editing a grandfathered numbered PRD passes"
else
  fail "editing a grandfathered numbered PRD should pass"
fi

# The error names the offending file and the fix.
git -C "$REPO" checkout -q -B "case" "$BASE"
echo "n" > "$REPO/prd/06-next.md"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m bad
msg="$( cd "$REPO" && "$GATE" "$BASE" HEAD 2>&1 )"
case "$msg" in
  *prd/06-next.md*YYYY-MM-DD*) pass "error names the file and the date+slug form" ;;
  *) fail "error message missing file or fix: $msg" ;;
esac

print_summary "assert-doc-ids.sh"
