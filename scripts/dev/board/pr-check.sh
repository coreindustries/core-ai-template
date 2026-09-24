#!/usr/bin/env bash
# pr-check.sh — run the gates that turn agent PRs red, locally, before a push.
#
# Usage (from the PR's worktree — the gate reads the branch and the diff from
# the working directory, so running it from the main checkout checks main):
#   make -C <pr-worktree> pr-check BODY=<body.md> [BASE=main]
#   scripts/dev/board/pr-check.sh <body.md> [base-branch]
#
# Gates, in order (every failure is reported; exit 1 if any failed):
#   1. branch name is namespaced            scripts/assert-branch-name.sh
#   2. there IS a diff against the base     an empty file list false-passes gate 3
#   3. delivery contract                    scripts/pr-delivery-contract-check.sh
#   4. proof lines use full https:// URLs   bare github.com/... links are ambiguous
#                                           and some awk parsers split on them
#   5. new PRD/ADR files use date+slug IDs  scripts/assert-doc-ids.sh
#   6. configured ratchets                  prCheck.ratchets in .claude/agent-lanes.json
# Plus a NOTE (not a failure) when local commits are not pushed yet: a PR whose
# commits exist only locally looks empty to reviewers — push before claiming ready.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

BODY_FILE="${1:-}"
BASE="${2:-$(lanes_cfg '.defaultBranch' main)}"
[ -n "$BODY_FILE" ] || { echo "usage: pr-check.sh <body.md> [base-branch]" >&2; exit 2; }
[ -f "$BODY_FILE" ] || { echo "pr-check: body file not found: $BODY_FILE" >&2; exit 2; }

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "pr-check: not inside a git worktree" >&2; exit 2; }
cd "$TOP" || exit 2

failed=0
step() { printf '\n== %s\n' "$1"; }
bad() { echo "FAIL: $1"; failed=$((failed + 1)); }

step "branch name"
"$LANES_REPO_ROOT/scripts/assert-branch-name.sh" || bad "branch name is not namespaced"

step "diff against origin/${BASE}"
git fetch -q origin "$BASE" 2>/dev/null || echo "WARN: git fetch origin ${BASE} failed — diffing against the local ref"
CHANGED="$(git diff --name-only "origin/${BASE}...HEAD" 2>/dev/null)"
if [ -z "$CHANGED" ]; then
  bad "no changed files vs origin/${BASE} — wrong worktree, or nothing committed? (the contract check would false-pass)"
else
  echo "$(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ') changed file(s)"
fi

step "delivery contract"
if [ -n "$CHANGED" ]; then
  CHANGED_FILES="$CHANGED" "$LANES_REPO_ROOT/scripts/pr-delivery-contract-check.sh" < "$BODY_FILE" \
    || bad "delivery contract (see output above)"
fi

step "proof URLs"
bare_links="$(awk '
  /^## / { inproof = ($0 ~ /^## (Real Proof|Delivery Contract)/) }
  inproof && /(^|[^\/])(github\.com|www\.)[^ ]*/ && !/https:\/\/(github\.com|www\.)/ { print "  " $0 }
' "$BODY_FILE")"
if [ -n "$bare_links" ]; then
  bad "proof lines with links that are not full https:// URLs:"
  printf '%s\n' "$bare_links"
else
  echo "OK"
fi

step "doc IDs"
if [ -n "$CHANGED" ]; then
  "$LANES_REPO_ROOT/scripts/assert-doc-ids.sh" "origin/${BASE}" HEAD || bad "new PRD/ADR uses a sequential ID"
fi

step "ratchets"
n_ratchets="$(lanes_cfg '(.prCheck.ratchets // []) | length' 0)"
if [ "$n_ratchets" = "0" ]; then
  echo "none configured (prCheck.ratchets)"
else
  i=0
  while [ "$i" -lt "$n_ratchets" ]; do
    cmd="$(lanes_cfg ".prCheck.ratchets[$i]" '')"
    echo "-> $cmd"
    bash -c "$cmd" || bad "ratchet failed: $cmd"
    i=$((i + 1))
  done
fi

upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  printf '\nNOTE: branch has no upstream — push it (git push -u origin HEAD) before opening or readying the PR.\n'
else
  ahead="$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
  [ "$ahead" = "0" ] || printf '\nNOTE: %s commit(s) not pushed to %s — reviewers cannot see them yet.\n' "$ahead" "$upstream"
fi

if [ "$failed" -gt 0 ]; then
  printf '\npr-check: %s gate(s) failed\n' "$failed"
  exit 1
fi
printf '\npr-check: all gates passed\n'
