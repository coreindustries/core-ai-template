#!/usr/bin/env bash
# pr-check.test.sh — unit tests for scripts/dev/board/pr-check.sh against a
# REAL disposable temp git repo (main + a bare "origin", the same pattern
# wt-clean.test.sh/board.test.sh use). No network calls.
#
# pr-check.sh shells out to $LANES_REPO_ROOT/scripts/assert-branch-name.sh
# and $LANES_REPO_ROOT/scripts/pr-delivery-contract-check.sh — LANES_REPO_ROOT
# is pinned to this template's REAL repo root so those resolve; LANES_CONFIG
# points at a disposable per-case fixture so nothing here depends on this
# repo's real .claude/agent-lanes.json.
#
# Run: bash scripts/dev/board/tests/pr-check.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
PR_CHECK="$BOARD_DIR/pr-check.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== pr-check.sh unit tests ==="

export GIT_AUTHOR_NAME="pr-check-test" GIT_AUTHOR_EMAIL="pr-check-test@example.invalid"
export GIT_COMMITTER_NAME="pr-check-test" GIT_COMMITTER_EMAIL="pr-check-test@example.invalid"

# ---------------------------------------------------------------------------
# Disposable repo + bare "origin" standing in for the real remote's main.
# ---------------------------------------------------------------------------
SEED="$WORK/seed"
ORIGIN="$WORK/origin.git"
REPO="$WORK/repo"

git init -q "$SEED"
git -C "$SEED" symbolic-ref HEAD refs/heads/main
echo "seed" > "$SEED/README.md"
git -C "$SEED" add README.md
git -C "$SEED" commit -q -m seed
git clone -q --bare "$SEED" "$ORIGIN"
git clone -q "$ORIGIN" "$REPO"

LANES_FIXTURE="$WORK/agent-lanes.json"
cat > "$LANES_FIXTURE" <<'JSON'
{ "defaultBranch": "main", "prCheck": { "ratchets": [] } }
JSON

run_pr_check() {
  # run_pr_check <config-file> <body-file>
  local cfg="$1" body="$2"
  ( cd "$REPO" && LANES_REPO_ROOT="$REPO_ROOT" LANES_CONFIG="$cfg" "$PR_CHECK" "$body" )
}

FULL_CONTRACT_BODY="$WORK/full-contract.md"
cat > "$FULL_CONTRACT_BODY" <<'MD'
## Risk Class
Infra — a broken CI workflow file could block every future PR.

## Delivery Contract
- Invariant: the workflow continues to run on every PR
- Runtime boundaries touched: GitHub Actions CI
- All writers/callers checked: only this workflow file touches the job matrix
- Silent fallback paths changed or ruled out: none introduced
- Rollback/killswitch: revert this commit

## Real Proof
Ran the workflow locally with `act` and confirmed the job passes:
https://github.com/example-org/example-repo/actions/runs/1
MD

MISSING_CONTRACT_BODY="$WORK/missing-contract.md"
cat > "$MISSING_CONTRACT_BODY" <<'MD'
## Summary
Updates the CI workflow file.
MD

BARE_LINK_BODY="$WORK/bare-link.md"
cat > "$BARE_LINK_BODY" <<'MD'
## Risk Class
Infra — a broken CI workflow file could block every future PR.

## Delivery Contract
- Invariant: the workflow continues to run on every PR
- Runtime boundaries touched: GitHub Actions CI
- All writers/callers checked: only this workflow file touches the job matrix
- Silent fallback paths changed or ruled out: none introduced
- Rollback/killswitch: revert this commit

## Real Proof
See the passing run at github.com/example-org/example-repo/actions/runs/1
MD

# ===========================================================================
# 1. Missing delivery contract on a high-risk change (.github/workflows/) ->
# fail.
# ===========================================================================
git -C "$REPO" checkout -q -b feat/missing-contract origin/main
mkdir -p "$REPO/.github/workflows"
echo "name: x" > "$REPO/.github/workflows/x.yml"
git -C "$REPO" add .github/workflows/x.yml
git -C "$REPO" commit -q -m "add workflow"

out="$(run_pr_check "$LANES_FIXTURE" "$MISSING_CONTRACT_BODY" 2>&1)"
rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q "delivery contract (see output above)" \
   && printf '%s' "$out" | grep -q "gate(s) failed"; then
  pass "missing delivery contract on a high-risk (.github/workflows/) change -> fail"
else
  fail "missing contract (rc=$rc out=[$out])"
fi

# ===========================================================================
# 2. Full contract, namespaced branch, real diff -> pass.
# ===========================================================================
git -C "$REPO" checkout -q -b feat/full-contract origin/main
mkdir -p "$REPO/.github/workflows"
echo "name: x" > "$REPO/.github/workflows/x.yml"
git -C "$REPO" add .github/workflows/x.yml
git -C "$REPO" commit -q -m "add workflow"

out="$(run_pr_check "$LANES_FIXTURE" "$FULL_CONTRACT_BODY" 2>&1)"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "all gates passed"; then
  pass "full delivery contract + namespaced branch + real diff -> pass"
else
  fail "full contract pass path (rc=$rc out=[$out])"
fi

# ===========================================================================
# 3. Bare github.com/... link inside ## Real Proof -> fail (ambiguous, not a
# full https:// URL), even though the contract sections are otherwise filled.
# ===========================================================================
git -C "$REPO" checkout -q -b feat/bare-link origin/main
mkdir -p "$REPO/.github/workflows"
echo "name: x" > "$REPO/.github/workflows/x.yml"
git -C "$REPO" add .github/workflows/x.yml
git -C "$REPO" commit -q -m "add workflow"

out="$(run_pr_check "$LANES_FIXTURE" "$BARE_LINK_BODY" 2>&1)"
rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q "proof lines with links that are not full https:// URLs"; then
  pass "bare github.com/... link in Real Proof -> fail"
else
  fail "bare link in proof (rc=$rc out=[$out])"
fi

# ===========================================================================
# 4. Empty diff vs origin/main (branch sitting exactly at origin/main) ->
# fail, and the delivery-contract step is skipped rather than false-passing
# on an empty file list.
# ===========================================================================
git -C "$REPO" checkout -q -b chore/no-changes origin/main

out="$(run_pr_check "$LANES_FIXTURE" "$FULL_CONTRACT_BODY" 2>&1)"
rc=$?
fail_count="$(printf '%s' "$out" | grep -c '^FAIL:')"
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q "no changed files vs origin/main" \
   && [ "$fail_count" = "1" ]; then
  pass "empty diff vs origin/main -> fail, delivery-contract step skipped (never false-passes on an empty file list)"
else
  fail "empty diff (rc=$rc fail_count=$fail_count out=[$out])"
fi

# ===========================================================================
# 5. Bare (unnamespaced) branch name -> fail, isolated from the other gates
# by touching only a low-risk file (no delivery contract required).
# ===========================================================================
git -C "$REPO" checkout -q -b nofeature origin/main
echo "docs change" >> "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "docs tweak"

out="$(run_pr_check "$LANES_FIXTURE" "$MISSING_CONTRACT_BODY" 2>&1)"
rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q "branch name is not namespaced" \
   && ! printf '%s' "$out" | grep -q "delivery contract (see output above)"; then
  pass "bare (unnamespaced) branch name -> fail, isolated from the low-risk diff's other gates"
else
  fail "bare branch name (rc=$rc out=[$out])"
fi

# ===========================================================================
# 6. Configured ratchet failing -> fail, even when the contract, branch name,
# and diff all pass.
# ===========================================================================
RATCHET_FIXTURE="$WORK/agent-lanes-ratchet.json"
cat > "$RATCHET_FIXTURE" <<'JSON'
{ "defaultBranch": "main", "prCheck": { "ratchets": ["false"] } }
JSON

git -C "$REPO" checkout -q -b feat/ratchet-fail origin/main
mkdir -p "$REPO/.github/workflows"
echo "name: x" > "$REPO/.github/workflows/x.yml"
git -C "$REPO" add .github/workflows/x.yml
git -C "$REPO" commit -q -m "add workflow"

out="$(run_pr_check "$RATCHET_FIXTURE" "$FULL_CONTRACT_BODY" 2>&1)"
rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q "ratchet failed: false" \
   && ! printf '%s' "$out" | grep -q "delivery contract (see output above)" \
   && ! printf '%s' "$out" | grep -q "branch name is not namespaced"; then
  pass "a configured ratchet that fails -> fail, even though contract/branch/diff all otherwise pass"
else
  fail "ratchet failure (rc=$rc out=[$out])"
fi

print_summary "pr-check.sh"
