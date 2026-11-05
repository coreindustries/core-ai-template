#!/usr/bin/env bash
# prune-branches.sh — delete local branches already merged into origin/main and
# prune stale worktree records. Dry run by default.
#
# Usage: scripts/prune-branches.sh            # report only
#        APPLY=1 scripts/prune-branches.sh    # delete merged local branches
# Used by `make prune-branches`.
#
# Safe by construction: uses `git branch -d` (refuses unmerged work), never
# touches the default branch, the current branch, or a branch checked out in
# any worktree, and never deletes remote branches (enable GitHub's "Automatically
# delete head branches" for those). Branches merged by squash/rebase are not
# detected as merged; they are listed under "not merged" for manual review.
set -euo pipefail

BASE="${BASE:-origin/main}"

if [ -n "${APPLY:-}" ] && [ "$APPLY" != "1" ]; then
  echo "ERROR: APPLY must be exactly 1 (got '$APPLY'). Run: APPLY=1 make prune-branches" >&2
  exit 1
fi

git fetch --prune --quiet origin
git worktree prune

current="$(git rev-parse --abbrev-ref HEAD)"
# Branches checked out in any worktree cannot be deleted.
in_use="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"

merged=()
while IFS= read -r b; do
  b="${b#"${b%%[![:space:]]*}"}"   # trim leading whitespace
  case "$b" in ''|main|master|"$current") continue ;; esac
  printf '%s\n' "$in_use" | grep -qxF "$b" && continue
  merged+=("$b")
done < <(git branch --format='%(refname:short)' --merged "$BASE")

if [ "${#merged[@]}" -eq 0 ]; then
  echo "No local branches merged into $BASE (excluding main, current, and worktree branches)."
else
  echo "Local branches merged into $BASE:"
  printf '  %s\n' "${merged[@]}"
  if [ "${APPLY:-}" = "1" ]; then
    git branch -d "${merged[@]}"
  else
    echo "Dry run. Delete them with: APPLY=1 make prune-branches"
  fi
fi

echo
echo "Branches NOT merged into $BASE (review by hand; squash-merged work shows up here):"
git branch --format='  %(refname:short)' --no-merged "$BASE" || true
