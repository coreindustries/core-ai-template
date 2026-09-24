#!/usr/bin/env bash
# wt-clean.test.sh — unit tests for scripts/dev/board/wt-clean.sh against a
# REAL temp git repo (main checkout + bare "origin" + linked worktrees) and a
# FAKE `gh` on PATH (no network, no real GitHub calls).
#
# This test script is allowed to invoke real `git` (it creates and drives its
# own disposable temp repo) even though the agent that wrote wt-clean.sh
# itself was not allowed to run bash text containing "git" — running this
# test FILE directly (`bash .../wt-clean.test.sh`) is the sanctioned path,
# per the same convention board.test.sh uses for git-heavy fixtures.
#
# Fixture shapes below follow `gh pr view/list --json
# number,state,headRefOid,headRefName`, per gh's own documented JSON shape.
# Every branch/PR name below is invented for this test (no real content).
#
# Run: bash scripts/dev/board/tests/wt-clean.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
WTCLEAN="$BOARD_DIR/wt-clean.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

# Resolved via `cd ... && pwd -P`, not just mktemp's raw output: on macOS
# mktemp -d returns an unresolved /var/... path while git itself records the
# symlink-resolved /private/var/... form in `worktree list`/error messages —
# without this, every path-based string assertion below silently mismatches.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
export FAKE_GH_LOG="$WORK/gh.log"
: > "$FAKE_GH_LOG"

# wt-clean.sh sources lib.sh (and, transitively, lanes-config.sh) by its OWN
# path — a mutant copied into $WORK needs both sitting next to it too, or it
# fails at source-time before any of the logic under test ever runs. A
# disposable config fixture keeps every case here independent of this repo's
# real .claude/agent-lanes.json.
cp "$BOARD_DIR/lib.sh" "$WORK/lib.sh"
cp "$BOARD_DIR/lanes-config.sh" "$WORK/lanes-config.sh"
LANES_FIXTURE="$WORK/agent-lanes.json"
cat > "$LANES_FIXTURE" <<'JSON'
{ "deploy": { "journalDir": "docs/deployments" } }
JSON
export LANES_CONFIG="$LANES_FIXTURE"
export LANES_REPO_ROOT="$REPO_ROOT"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== wt-clean.sh unit tests ==="

# ---------------------------------------------------------------------------
# Fake gh — dispatches `pr view <n>` (FAKE_PRVIEW_<n>), `pr list --head <b>`
# (FAKE_PRHEAD_<sanitized b>, default "[]"), and `pr list --label agent:<X>`
# (FAKE_AGENTLIST_<sanitized X>, default "[]"). Every invocation is logged.
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

sanitize() { printf '%s' "$1" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]'; }

sub1="${1:-}"; sub2="${2:-}"

case "$sub1" in
  pr)
    case "$sub2" in
      view)
        num="${3:-}"
        varname="FAKE_PRVIEW_${num}"
        val="$(eval "printf '%s' \"\${$varname:-}\"")"
        if [ -z "$val" ]; then
          echo "fake gh: no fixture for pr view $num" >&2
          exit 1
        fi
        printf '%s\n' "$val"
        ;;
      list)
        head_val=""
        label_val=""
        prev=""
        for a in "$@"; do
          if [ "$prev" = "--head" ]; then head_val="$a"; fi
          if [ "$prev" = "--label" ]; then label_val="$a"; fi
          prev="$a"
        done
        if [ -n "$label_val" ]; then
          agent="${label_val#agent:}"
          varname="FAKE_AGENTLIST_$(sanitize "$agent")"
          val="$(eval "printf '%s' \"\${$varname:-[]}\"")"
          printf '%s\n' "$val"
        elif [ -n "$head_val" ]; then
          varname="FAKE_PRHEAD_$(sanitize "$head_val")"
          val="$(eval "printf '%s' \"\${$varname:-[]}\"")"
          printf '%s\n' "$val"
        else
          echo "fake gh: pr list without --head or --label" >&2
          exit 1
        fi
        ;;
      *) echo "fake gh: unhandled pr $sub2" >&2; exit 1 ;;
    esac
    ;;
  *) echo "fake gh: unhandled subcommand $sub1" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$FAKE_BIN/gh"

export PATH="$FAKE_BIN:$PATH"

# ---------------------------------------------------------------------------
# Real disposable git repo: seed -> bare origin -> main checkout + worktrees.
# ---------------------------------------------------------------------------
export GIT_AUTHOR_NAME="wt-clean-test"
export GIT_AUTHOR_EMAIL="wt-clean-test@example.invalid"
export GIT_COMMITTER_NAME="wt-clean-test"
export GIT_COMMITTER_EMAIL="wt-clean-test@example.invalid"

SEED="$WORK/seed"
ORIGIN="$WORK/origin.git"
MAIN="$WORK/main"
WT_DIR="$WORK/worktrees"
mkdir -p "$WT_DIR"

git init -q "$SEED"
git -C "$SEED" symbolic-ref HEAD refs/heads/main
echo "seed" > "$SEED/README.md"
git -C "$SEED" add README.md
git -C "$SEED" commit -q -m "seed"

git clone -q --bare "$SEED" "$ORIGIN"
git clone -q "$ORIGIN" "$MAIN"

new_worktree() {
  # new_worktree <name> <branch> [<start-point>]
  local name="$1" branch="$2" start="${3:-main}"
  git -C "$MAIN" worktree add -q -b "$branch" "$WT_DIR/$name" "$start"
}

commit_in() {
  # commit_in <path> <content>
  local path="$1" content="$2"
  printf '%s\n' "$content" > "$path/marker.txt"
  git -C "$path" add marker.txt
  git -C "$path" commit -q -m "content: $content"
}

MAIN_HEAD_BEFORE="$(git -C "$MAIN" rev-parse HEAD)"
ALL_OUTPUT="$WORK/all-output.log"
: > "$ALL_OUTPUT"

run_wtclean() {
  # run_wtclean <errfile> <args...> — runs from inside MAIN, captures stdout
  # to $out (caller reads it back), tees combined stdout into ALL_OUTPUT for
  # the "main checkout never touched" cross-case grep at the end.
  local errfile="$1"; shift
  ( cd "$MAIN" && "$WTCLEAN" "$@" ) 2>"$errfile"
}

# ===========================================================================
# 1. merged + clean + HEAD == PR head -> REMOVED, branch deleted
# ===========================================================================
new_worktree wt1 wt1-clean
commit_in "$WT_DIR/wt1" "wt1"
WT1_SHA="$(git -C "$WT_DIR/wt1" rev-parse HEAD)"
export FAKE_PRVIEW_301="{\"number\":301,\"state\":\"MERGED\",\"headRefOid\":\"$WT1_SHA\",\"headRefName\":\"wt1-clean\"}"

out="$(run_wtclean "$WORK/case1.err" --pr 301)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "REMOVED $WT_DIR/wt1 (#301, branch wt1-clean)" \
   && [ ! -d "$WT_DIR/wt1" ] \
   && ! git -C "$MAIN" rev-parse --verify -q refs/heads/wt1-clean >/dev/null 2>&1; then
  pass "merged+clean+HEAD==head: REMOVED, dir gone, branch deleted"
else
  fail "merged+clean+HEAD==head (rc=$rc out=[$out] err=[$(cat "$WORK/case1.err")])"
fi

# ===========================================================================
# 2. merged but dirty -> SKIP dirty, worktree still exists
# ===========================================================================
new_worktree wt2 wt2-dirty
commit_in "$WT_DIR/wt2" "wt2"
WT2_SHA="$(git -C "$WT_DIR/wt2" rev-parse HEAD)"
echo "uncommitted" > "$WT_DIR/wt2/untracked.txt"
export FAKE_PRVIEW_302="{\"number\":302,\"state\":\"MERGED\",\"headRefOid\":\"$WT2_SHA\",\"headRefName\":\"wt2-dirty\"}"

out="$(run_wtclean "$WORK/case2.err" --pr 302)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qE '^SKIP dirty \(1 files\) '"$WT_DIR"'/wt2$' \
   && [ -d "$WT_DIR/wt2" ]; then
  pass "merged but dirty: SKIP dirty, worktree still exists"
else
  fail "merged but dirty (rc=$rc out=[$out] err=[$(cat "$WORK/case2.err")])"
fi

# ---------------------------------------------------------------------------
# Mutation checks (using case 2's still-dirty wt2, still fixtured as #302):
#   (a) disable the dirty check -> output must stop being "SKIP dirty"
#   (b) (a) + add --force to `git worktree remove` -> the dirty worktree is
#       ACTUALLY removed (the real failure mode both guards jointly prevent)
# Mutants are separate temp files; wt-clean.sh itself is never touched, so
# there is nothing to "restore" afterward.
# ---------------------------------------------------------------------------
MUTANT_A="$WORK/wt-clean.mutantA.sh"
sed 's/if \[ -n "\$dirty_lines" \]; then/if false; then/' "$WTCLEAN" > "$MUTANT_A"
chmod +x "$MUTANT_A"

out="$(cd "$MAIN" && "$MUTANT_A" --pr 302 2>"$WORK/mutantA.err")"
if ! printf '%s' "$out" | grep -q 'SKIP dirty' && [ -d "$WT_DIR/wt2" ]; then
  pass "MUTATION CHECK: disabling the dirty check changes the outcome away from SKIP dirty (git's own native refusal still saves the worktree — see mutant B below for the full failure mode)"
else
  fail "MUTATION CHECK: disabling the dirty check should stop producing 'SKIP dirty' (out=[$out])"
fi

MUTANT_B="$WORK/wt-clean.mutantB.sh"
sed 's/git -C "\$MAIN_CHECKOUT" worktree remove "\$wpath" 2>"\$ERRFILE"/git -C "$MAIN_CHECKOUT" worktree remove --force "$wpath" 2>"$ERRFILE"/' "$MUTANT_A" > "$MUTANT_B"
chmod +x "$MUTANT_B"

out="$(cd "$MAIN" && "$MUTANT_B" --pr 302 2>"$WORK/mutantB.err")"
if printf '%s' "$out" | grep -qF "REMOVED $WT_DIR/wt2" && [ ! -d "$WT_DIR/wt2" ]; then
  pass "MUTATION CHECK: dirty-check removed AND --force added actually destroys the dirty worktree (proves both guards are load-bearing together)"
else
  fail "MUTATION CHECK: mutant B (no dirty check + --force) should have actually removed the dirty worktree (out=[$out] dir-exists=$([ -d "$WT_DIR/wt2" ] && echo yes || echo no))"
fi

# ===========================================================================
# 3. dirty under docs/deployments/attempts/ -> journal warning
# ===========================================================================
new_worktree wt3 wt3-journal
commit_in "$WT_DIR/wt3" "wt3"
WT3_SHA="$(git -C "$WT_DIR/wt3" rev-parse HEAD)"
mkdir -p "$WT_DIR/wt3/docs/deployments/attempts"
echo "{}" > "$WT_DIR/wt3/docs/deployments/attempts/run.json"
export FAKE_PRVIEW_303="{\"number\":303,\"state\":\"MERGED\",\"headRefOid\":\"$WT3_SHA\",\"headRefName\":\"wt3-journal\"}"

out="$(run_wtclean "$WORK/case3.err" --pr 303)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -q 'SKIP dirty' \
   && printf '%s' "$out" | grep -qi 'journals' \
   && [ -d "$WT_DIR/wt3" ]; then
  pass "dirty under docs/deployments/attempts: journal warning shown, worktree kept"
else
  fail "dirty under docs/deployments/attempts (rc=$rc out=[$out] err=[$(cat "$WORK/case3.err")])"
fi

# ===========================================================================
# 4. ahead-of-pr -> SKIP ahead-of-pr, branch kept
# ===========================================================================
new_worktree wt4 wt4-ahead
commit_in "$WT_DIR/wt4" "wt4-prhead"
WT4_PRHEAD_SHA="$(git -C "$WT_DIR/wt4" rev-parse HEAD)"
git -C "$WT_DIR/wt4" push -q origin "HEAD:refs/pull/304/head"
commit_in "$WT_DIR/wt4" "wt4-extra-local-commit"
export FAKE_PRVIEW_304="{\"number\":304,\"state\":\"MERGED\",\"headRefOid\":\"$WT4_PRHEAD_SHA\",\"headRefName\":\"wt4-ahead\"}"

out="$(run_wtclean "$WORK/case4.err" --pr 304)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "SKIP ahead-of-pr $WT_DIR/wt4" \
   && [ -d "$WT_DIR/wt4" ] \
   && git -C "$MAIN" rev-parse --verify -q refs/heads/wt4-ahead >/dev/null 2>&1; then
  pass "ahead-of-pr: SKIP ahead-of-pr, worktree and branch both kept"
else
  fail "ahead-of-pr (rc=$rc out=[$out] err=[$(cat "$WORK/case4.err")])"
fi

# ===========================================================================
# 5. open PR -> KEEP open-pr
# ===========================================================================
new_worktree wt5 wt5-open
commit_in "$WT_DIR/wt5" "wt5"
WT5_SHA="$(git -C "$WT_DIR/wt5" rev-parse HEAD)"
export FAKE_PRVIEW_305="{\"number\":305,\"state\":\"OPEN\",\"headRefOid\":\"$WT5_SHA\",\"headRefName\":\"wt5-open\"}"

out="$(run_wtclean "$WORK/case5.err" --pr 305)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "KEEP open-pr #305 $WT_DIR/wt5" \
   && [ -d "$WT_DIR/wt5" ]; then
  pass "open PR: KEEP open-pr, worktree untouched"
else
  fail "open PR (rc=$rc out=[$out] err=[$(cat "$WORK/case5.err")])"
fi

# ===========================================================================
# 6. locked -> SKIP locked
# ===========================================================================
new_worktree wt6 wt6-locked
commit_in "$WT_DIR/wt6" "wt6"
WT6_SHA="$(git -C "$WT_DIR/wt6" rev-parse HEAD)"
git -C "$MAIN" worktree lock "$WT_DIR/wt6"
export FAKE_PRVIEW_306="{\"number\":306,\"state\":\"MERGED\",\"headRefOid\":\"$WT6_SHA\",\"headRefName\":\"wt6-locked\"}"

out="$(run_wtclean "$WORK/case6.err" --pr 306)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "SKIP locked $WT_DIR/wt6" \
   && [ -d "$WT_DIR/wt6" ]; then
  pass "locked: SKIP locked, worktree untouched"
else
  fail "locked (rc=$rc out=[$out] err=[$(cat "$WORK/case6.err")])"
fi

# ===========================================================================
# 7. local branch name differs from upstream -> still matched, removed
# ===========================================================================
new_worktree wt7-seed wt7-seed-tmp
commit_in "$WT_DIR/wt7-seed" "wt7"
WT7_SHA="$(git -C "$WT_DIR/wt7-seed" rev-parse HEAD)"
git -C "$WT_DIR/wt7-seed" push -q origin HEAD:refs/heads/feat/wt7-mismatch
git -C "$MAIN" worktree remove "$WT_DIR/wt7-seed"
git -C "$MAIN" branch -q -D wt7-seed-tmp
git -C "$MAIN" fetch -q origin
git -C "$MAIN" worktree add -q -b c-features/wt7-mismatch "$WT_DIR/wt7" origin/feat/wt7-mismatch
export FAKE_PRVIEW_307="{\"number\":307,\"state\":\"MERGED\",\"headRefOid\":\"$WT7_SHA\",\"headRefName\":\"feat/wt7-mismatch\"}"

out="$(run_wtclean "$WORK/case7.err" --pr 307)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "REMOVED $WT_DIR/wt7 (#307, branch c-features/wt7-mismatch)" \
   && [ ! -d "$WT_DIR/wt7" ] \
   && ! git -C "$MAIN" rev-parse --verify -q refs/heads/c-features/wt7-mismatch >/dev/null 2>&1; then
  pass "local branch name differs from upstream: still matched via upstream, removed"
else
  fail "local branch differs from upstream (rc=$rc out=[$out] err=[$(cat "$WORK/case7.err")])"
fi

# ===========================================================================
# 8. --dry-run removes nothing
# ===========================================================================
new_worktree wt8 wt8-dryrun
commit_in "$WT_DIR/wt8" "wt8"
WT8_SHA="$(git -C "$WT_DIR/wt8" rev-parse HEAD)"
export FAKE_PRVIEW_308="{\"number\":308,\"state\":\"MERGED\",\"headRefOid\":\"$WT8_SHA\",\"headRefName\":\"wt8-dryrun\"}"

out="$(run_wtclean "$WORK/case8.err" --pr 308 --dry-run)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "WOULD-REMOVE $WT_DIR/wt8 (#308, branch wt8-dryrun)" \
   && [ -d "$WT_DIR/wt8" ] \
   && git -C "$MAIN" rev-parse --verify -q refs/heads/wt8-dryrun >/dev/null 2>&1; then
  pass "--dry-run: prints WOULD-REMOVE, removes nothing"
else
  fail "--dry-run (rc=$rc out=[$out] err=[$(cat "$WORK/case8.err")])"
fi

# ===========================================================================
# 9. bonus: pr-head-unavailable -> SKIP pr-head-unavailable (missing PR-head
# ref must not be silently treated as "not an ancestor")
# ===========================================================================
new_worktree wt9 wt9-nohead
commit_in "$WT_DIR/wt9" "wt9"
FAKE_MISSING_SHA="deadbeef00000000000000000000000000000cafe"
export FAKE_PRVIEW_309="{\"number\":309,\"state\":\"MERGED\",\"headRefOid\":\"$FAKE_MISSING_SHA\",\"headRefName\":\"wt9-nohead\"}"

out="$(run_wtclean "$WORK/case9.err" --pr 309)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "SKIP pr-head-unavailable $WT_DIR/wt9" \
   && [ -d "$WT_DIR/wt9" ]; then
  pass "pr-head-unavailable: missing PR-head ref reported, not treated as not-ancestor"
else
  fail "pr-head-unavailable (rc=$rc out=[$out] err=[$(cat "$WORK/case9.err")])"
fi

# ===========================================================================
# 10. bonus: --agent mode (merged PRs labeled agent:<NAME>)
# ===========================================================================
new_worktree wt10 wt10-agent
commit_in "$WT_DIR/wt10" "wt10"
WT10_SHA="$(git -C "$WT_DIR/wt10" rev-parse HEAD)"
export FAKE_AGENTLIST_TESTAGENT="[{\"number\":310,\"headRefName\":\"wt10-agent\",\"headRefOid\":\"$WT10_SHA\",\"state\":\"MERGED\"}]"

out="$(run_wtclean "$WORK/case10.err" --agent TESTAGENT)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "REMOVED $WT_DIR/wt10 (#310, branch wt10-agent)" \
   && [ ! -d "$WT_DIR/wt10" ]; then
  pass "--agent mode: matches merged+labeled PR by branch, removes"
else
  fail "--agent mode (rc=$rc out=[$out] err=[$(cat "$WORK/case10.err")])"
fi

# ===========================================================================
# 11. stacked PRs: feat/wt11-base is its own, separately open branch/PR;
# feat/wt11-top branches from it and adds one more commit, and IS merged. A
# clean worktree sitting on feat/wt11-base (whose tip is an ancestor of the
# merged top PR's head, but is not the top PR's own branch and is not an
# exact-HEAD match) must NOT be matched by `--pr <top>` — and its branch must
# NOT be deleted. Judge regression (2026-09-23): the removed ancestry rule
# (c) matched this shape and would have `branch -D`'d feat/wt11-base out
# from under its own still-open PR.
# ===========================================================================
SCRATCH11="$WORK/scratch11"
git clone -q "$ORIGIN" "$SCRATCH11"
commit_in "$SCRATCH11" "wt11-base"
WT11_BASE_SHA="$(git -C "$SCRATCH11" rev-parse HEAD)"
git -C "$SCRATCH11" push -q origin HEAD:refs/heads/feat/wt11-base
commit_in "$SCRATCH11" "wt11-top"
WT11_TOP_SHA="$(git -C "$SCRATCH11" rev-parse HEAD)"
git -C "$SCRATCH11" push -q origin HEAD:refs/heads/feat/wt11-top
git -C "$SCRATCH11" push -q origin HEAD:refs/pull/320/head
rm -rf "$SCRATCH11"

git -C "$MAIN" fetch -q origin
new_worktree wt11-base feat/wt11-base origin/feat/wt11-base
export FAKE_PRVIEW_320="{\"number\":320,\"state\":\"MERGED\",\"headRefOid\":\"$WT11_TOP_SHA\",\"headRefName\":\"feat/wt11-top\"}"

out="$(run_wtclean "$WORK/case11.err" --pr 320)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && ! printf '%s' "$out" | grep -qF "$WT_DIR/wt11-base" \
   && [ -d "$WT_DIR/wt11-base" ] \
   && git -C "$MAIN" rev-parse --verify -q refs/heads/feat/wt11-base >/dev/null 2>&1; then
  pass "stacked PRs: base-branch worktree (ancestor of the merged top PR's head, but not its branch or exact head) is NOT matched, worktree and branch both untouched"
else
  fail "stacked PRs (rc=$rc out=[$out] err=[$(cat "$WORK/case11.err")])"
fi

# ===========================================================================
# 12. general case: a worktree on some OTHER, unrelated branch whose HEAD
# merely happens to be an ancestor of a merged PR's head (not the PR's own
# branch, not an exact-HEAD match) -> NOT matched, NOT removed. Same class
# as case 11's stacked-PR incident shape, without the "PR" framing on the
# ancestor branch itself.
# ===========================================================================
SCRATCH12="$WORK/scratch12"
git clone -q "$ORIGIN" "$SCRATCH12"
commit_in "$SCRATCH12" "wt12-a"
WT12_A_SHA="$(git -C "$SCRATCH12" rev-parse HEAD)"
commit_in "$SCRATCH12" "wt12-b"
WT12_B_SHA="$(git -C "$SCRATCH12" rev-parse HEAD)"
git -C "$SCRATCH12" push -q origin HEAD:refs/heads/pr312-branch
rm -rf "$SCRATCH12"

git -C "$MAIN" fetch -q origin
git -C "$MAIN" worktree add -q -b worktree-agent-312 "$WT_DIR/wt12-agent" "$WT12_A_SHA"
export FAKE_PRVIEW_312="{\"number\":312,\"state\":\"MERGED\",\"headRefOid\":\"$WT12_B_SHA\",\"headRefName\":\"pr312-branch\"}"

out="$(run_wtclean "$WORK/case12.err" --pr 312)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && ! printf '%s' "$out" | grep -qF "$WT_DIR/wt12-agent" \
   && [ -d "$WT_DIR/wt12-agent" ] \
   && git -C "$MAIN" rev-parse --verify -q refs/heads/worktree-agent-312 >/dev/null 2>&1; then
  pass "unrelated branch, HEAD merely an ancestor of the PR head: NOT matched, worktree and branch both untouched"
else
  fail "unrelated branch ancestor-only (rc=$rc out=[$out] err=[$(cat "$WORK/case12.err")])"
fi

# Mutation check: re-add an ancestry-matching rule to find_all_worktrees_for_pr
# (inserted via awk, not sed, since it's a multi-line insertion) and confirm
# the stacked-PR base worktree from case 11 now matches and would be removed
# (--dry-run, so nothing is actually destroyed) — proving the fix is the
# absence of ancestry matching, not incidental to some other guard.
MUTANT_C="$WORK/wt-clean.mutantC.sh"
awk '
  /\[ "\$matched" = "1" \] && printf/ && !done {
    print "    if [ \"$matched\" != \"1\" ] && [ \"$wbranch\" != \"DETACHED\" ]; then"
    print "      if git -C \"$wpath\" merge-base --is-ancestor \"$whead\" \"$target_sha\" 2>/dev/null; then"
    print "        matched=1"
    print "      fi"
    print "    fi"
    done = 1
  }
  { print }
' "$WTCLEAN" > "$MUTANT_C"
chmod +x "$MUTANT_C"
if ! diff -q "$WTCLEAN" "$MUTANT_C" >/dev/null 2>&1; then
  out="$(cd "$MAIN" && "$MUTANT_C" --pr 320 --dry-run 2>"$WORK/mutantC.err")"
  if printf '%s' "$out" | grep -qF "WOULD-REMOVE $WT_DIR/wt11-base"; then
    pass "MUTATION CHECK: re-adding an ancestry match makes the stacked-PR test fail (base worktree matches again, guard-removal is load-bearing)"
  else
    fail "MUTATION CHECK: re-adding an ancestry match should have made wt11-base match again (out=[$out] err=[$(cat "$WORK/mutantC.err")])"
  fi
else
  fail "MUTATION CHECK: the awk mutation did not change wt-clean.sh at all (mutant is identical to the original, proves nothing)"
fi

# ===========================================================================
# 13. two worktrees for the same PR (one by branch name, one by exact HEAD
# equality on its own branch name) -> BOTH removed.
# ===========================================================================
SCRATCH13="$WORK/scratch13"
git clone -q "$ORIGIN" "$SCRATCH13"
commit_in "$SCRATCH13" "wt13"
WT13_SHA="$(git -C "$SCRATCH13" rev-parse HEAD)"
git -C "$SCRATCH13" push -q origin HEAD:refs/heads/pr313-branch
rm -rf "$SCRATCH13"

git -C "$MAIN" fetch -q origin
git -C "$MAIN" worktree add -q -b pr313-branch "$WT_DIR/wt13a" origin/pr313-branch
git -C "$MAIN" worktree add -q -b worktree-agent-313 "$WT_DIR/wt13b" "$WT13_SHA"
export FAKE_PRVIEW_313="{\"number\":313,\"state\":\"MERGED\",\"headRefOid\":\"$WT13_SHA\",\"headRefName\":\"pr313-branch\"}"

out="$(run_wtclean "$WORK/case13.err" --pr 313)"
rc=$?
printf '%s\n' "$out" >> "$ALL_OUTPUT"
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF "REMOVED $WT_DIR/wt13a (#313, branch pr313-branch)" \
   && printf '%s' "$out" | grep -qF "REMOVED $WT_DIR/wt13b (#313, branch worktree-agent-313)" \
   && [ ! -d "$WT_DIR/wt13a" ] && [ ! -d "$WT_DIR/wt13b" ]; then
  pass "two worktrees for the same PR: both matched (branch name + exact HEAD), both REMOVED"
else
  fail "two worktrees for the same PR (rc=$rc out=[$out] err=[$(cat "$WORK/case13.err")])"
fi

# ===========================================================================
# 14. main checkout is never touched, across every case above
# ===========================================================================
MAIN_HEAD_AFTER="$(git -C "$MAIN" rev-parse HEAD)"
main_dirty="$(git -C "$MAIN" status --porcelain)"

if [ "$MAIN_HEAD_BEFORE" = "$MAIN_HEAD_AFTER" ] && [ -z "$main_dirty" ] \
   && ! grep -qF "$MAIN" "$ALL_OUTPUT"; then
  pass "main checkout never touched: HEAD unchanged, clean, never named in output"
else
  fail "main checkout touched (before=$MAIN_HEAD_BEFORE after=$MAIN_HEAD_AFTER dirty=[$main_dirty])"
fi

print_summary "wt-clean.sh"
