#!/usr/bin/env bash
# assert-branch-name.sh — branch names must be namespaced (<type>/<slug>) so
# parallel agents picking the same task don't collide on a bare name.
#
# Usage: scripts/assert-branch-name.sh [branch]   (default: current branch)
# Used by .github/workflows/branch-name-lint.yml and `make pr-check`.
set -euo pipefail

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

# Accepted shapes:
#   <type>/<slug>        feat/oauth-login, fix/null-session,
#                        dependabot/npm_and_yarn/left-pad-1.3.0
#   worktree-<slug>      created by `make wt` / Claude Code worktrees
#   revert-<n>-<slug>    GitHub's auto-generated revert branches
PATTERN='^(worktree-[A-Za-z0-9._+-]+|revert-[0-9]+-[A-Za-z0-9._/+-]+|[a-z][a-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._/+-]*)$'

if printf '%s' "$BRANCH" | grep -qE "$PATTERN"; then
  echo "OK: '$BRANCH' is namespaced."
  exit 0
fi

cat >&2 <<ERR
Bare branch name: '$BRANCH' is not namespaced.

Branch names must be namespaced so parallel agents don't collide.

  Expected: <type>/<slug>
  Types:    feat | fix | docs | style | refactor | perf | test |
            chore | ci | build | revert

  Good:  feat/oauth-login
         fix/null-session-on-logout
  Bad:   fix-login          (no namespace)
         Feat/OAuth         (type must be lowercase)

Rename with:
  git branch -m <new-name>
  git push origin -u <new-name>
  git push origin --delete <old-name>

See .claude/rules/git-workflow.md
ERR
exit 1
