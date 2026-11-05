#!/usr/bin/env bash
# prune-branches.sh — delete local branches already merged into origin/main.
# Dry run by default; run it from main for the most accurate merged check.
#
# Usage: scripts/prune-branches.sh            # report only
#        APPLY=1 scripts/prune-branches.sh    # delete merged local branches
# Used by `make prune-branches`.
#
# Safe by construction: uses `git branch -d` (refuses unmerged work), never
# touches the base branch, the current branch, or a branch checked out in any
# worktree, and never deletes remote branches (enable GitHub's "Automatically
# delete head branches" for those). Branches merged by squash/rebase are not
# detected as merged; they are listed under "not merged" for manual review.
# Both modes run `git fetch --prune`; only APPLY=1 also prunes worktree records.
set -euo pipefail

BASE="${BASE:-origin/main}"
BASE_LOCAL="${BASE#origin/}"

if [ -n "${APPLY:-}" ] && [ "$APPLY" != "1" ]; then
  echo "ERROR: APPLY must be exactly 1 (got '$APPLY'). Run: APPLY=1 make prune-branches" >&2
  exit 1
fi

git fetch --prune --quiet origin
[ "${APPLY:-}" = "1" ] && git worktree prune

current="$(git rev-parse --abbrev-ref HEAD)"
# Branches checked out in any worktree cannot be deleted.
in_use="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"

merged=()
while IFS= read -r b; do
  b="${b#"${b%%[![:space:]]*}"}"   # trim leading whitespace
  case "$b" in ''|main|master|"$BASE_LOCAL"|"$current") continue ;; esac
  grep -qxF "$b" <<<"$in_use" && continue
  merged+=("$b")
done < <(git branch --format='%(refname:lstrip=2)' --merged "$BASE")

failed=()
if [ "${#merged[@]}" -eq 0 ]; then
  echo "No local branches merged into $BASE (excluding $BASE_LOCAL, current, and worktree branches)."
else
  echo "Local branches merged into $BASE:"
  printf '  %s\n' "${merged[@]}"
  if [ "${APPLY:-}" = "1" ]; then
    for b in "${merged[@]}"; do
      git branch -d "$b" || failed+=("$b")
    done
  else
    echo "Dry run. Delete them with: APPLY=1 make prune-branches"
  fi
fi

echo
echo "Branches NOT merged into $BASE (review by hand; squash-merged work shows up here):"
git branch --format='  %(refname:lstrip=2)' --no-merged "$BASE" || true

if [ "${#failed[@]}" -gt 0 ]; then
  echo >&2
  echo "Could not delete (not merged into HEAD; retry from $BASE_LOCAL): ${failed[*]}" >&2
  exit 1
fi
