#!/usr/bin/env bash
# pr-watch.test.sh — unit tests for scripts/dev/board/pr-watch.sh against a
# FAKE gh/sleep on PATH (no network, no real GitHub calls).
#
# Fixture shapes follow `gh pr view/list --json
# number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,statusCheckRollup`,
# per gh's own documented JSON shape:
#   -> {"headRefOid":"9b51942c...","isDraft":true,"mergeStateStatus":"UNKNOWN",
#         "mergeable":"UNKNOWN","number":<n>,"reviewDecision":"","state":"OPEN",
#         "statusCheckRollup":[{"__typename":"CheckRun","completedAt":"...",
#         "conclusion":"SUCCESS","detailsUrl":"https://github.com/.../actions/runs/<runid>/job/<jobid>",
#         "name":"Branch name lint","startedAt":"...","status":"COMPLETED","workflowName":"..."}, ...]}
# `gh pr list --state open --json <same fields>` returns the same shape as an
# ARRAY of the above objects — confirms `gh pr list` accepts and returns the
# identical field set used for --agent discovery (mergeStateStatus can read
# "UNKNOWN" for a few seconds while GitHub computes mergeability, before
# settling to "CLEAN"/"DIRTY"/"BEHIND" — both UNKNOWN and CLEAN are treated
# as "not conflicting" by pr-watch.sh's classifier). Every PR number/title
# below is invented for this test (no real content, no PII).
#
# Run: ./scripts/dev/board/tests/pr-watch.test.sh (direct exec; `bash <file>`
# may trip a worktree guard — chmod +x is already set).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
PRWATCH="$BOARD_DIR/pr-watch.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
export FAKE_GH_LOG="$WORK/gh.log"
: > "$FAKE_GH_LOG"

# Every mutant below is a `sed`-patched COPY of pr-watch.sh dropped directly
# into $WORK (never back into scripts/dev/board/) — it sources gh-checks.sh
# and lib.sh via SCRIPT_DIR="$(dirname "$0")", so copies of both (plus
# lib.sh's own lanes-config.sh) must sit next to it in $WORK too, or the
# mutant fails at source-time before any of the logic under test ever runs.
# A disposable config fixture keeps every case here independent of this
# repo's real .claude/agent-lanes.json.
cp "$BOARD_DIR/gh-checks.sh" "$WORK/gh-checks.sh"
cp "$BOARD_DIR/lib.sh" "$WORK/lib.sh"
cp "$BOARD_DIR/lanes-config.sh" "$WORK/lanes-config.sh"
LANES_FIXTURE="$WORK/agent-lanes.json"
cat > "$LANES_FIXTURE" <<'JSON'
{ "checks": { "cancelledOk": [] } }
JSON
export LANES_CONFIG="$LANES_FIXTURE"
export LANES_REPO_ROOT="$REPO_ROOT"

# A second fixture with one cancelledOk entry, for the "configured exemption"
# case below — passed inline (LANES_CONFIG=... $PRWATCH ...) so it never
# leaks into other cases.
LANES_FIXTURE_CANCELLED_OK="$WORK/agent-lanes-cancelled-ok.json"
cat > "$LANES_FIXTURE_CANCELLED_OK" <<'JSON'
{ "checks": { "cancelledOk": ["Classify and auto-merge"] } }
JSON

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fake gh — `pr view <n>` returns $FAKE_PR_VIEW_<n> (or fails with
# $FAKE_PR_VIEW_FAIL_<n> as the stderr line, if set). `pr list` returns
# $FAKE_PR_LIST_JSON. Every invocation is logged to $FAKE_GH_LOG.
# ---------------------------------------------------------------------------
install_fake_gh() {
  cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  n="${3:-}"
  failvar="FAKE_PR_VIEW_FAIL_${n}"
  failval="$(eval "printf '%s' \"\${${failvar}:-}\"")"
  if [ -n "$failval" ]; then
    echo "$failval" >&2
    exit 1
  fi
  varname="FAKE_PR_VIEW_${n}"
  val="$(eval "printf '%s' \"\${${varname}:-}\"")"
  if [ -z "$val" ]; then
    echo "fake gh: no FAKE_PR_VIEW_${n} set" >&2
    exit 1
  fi
  printf '%s' "$val"
  exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  printf '%s' "${FAKE_PR_LIST_JSON:-[]}"
  exit 0
fi

echo "fake gh (pr-watch mode): unhandled $*" >&2
exit 1
FAKE_GH
  chmod +x "$FAKE_BIN/gh"
}
install_fake_gh

cat > "$FAKE_BIN/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
exit 0
FAKE_SLEEP
chmod +x "$FAKE_BIN/sleep"

export PATH="$FAKE_BIN:$PATH"

reset_env() {
  unset FAKE_PR_LIST_JSON
  for v in $(env | grep -o '^FAKE_PR_VIEW[A-Z0-9_]*' || true); do unset "$v"; done
  : > "$FAKE_GH_LOG"
  # Fresh state dir per test case so dedup state from one scenario never
  # leaks into another.
  export TMPDIR="$WORK/tmp-$$-$RANDOM"
  mkdir -p "$TMPDIR"
}

pr_json() {
  # pr_json <number> <state> <isDraft> <mergeable> <mergeStateStatus> <headRefOid> <checksJson>
  printf '{"number":%s,"state":"%s","isDraft":%s,"mergeable":"%s","mergeStateStatus":"%s","reviewDecision":"","headRefOid":"%s","statusCheckRollup":%s}' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

echo ""
echo "=== pr-watch.sh unit tests ==="

# ===========================================================================
# 1. Event classification — one case per event type
# ===========================================================================

reset_env
export FAKE_PR_VIEW_101="$(pr_json 101 MERGED false MERGEABLE CLEAN aaa1111 '[]')"
out="$($PRWATCH --once 101 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q '^ACTION pr=101 event=merged head=aaa1111'; then
  pass "classify: MERGED state -> event=merged"
else
  fail "classify: merged (rc=$rc out=[$out])"
fi

reset_env
export FAKE_PR_VIEW_102="$(pr_json 102 CLOSED false MERGEABLE CLEAN bbb2222 '[]')"
out="$($PRWATCH --once 102 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=closed'; then
  pass "classify: CLOSED (not merged) -> event=closed"
else
  fail "classify: closed (rc=$rc out=[$out])"
fi

reset_env
export FAKE_PR_VIEW_103="$(pr_json 103 OPEN false CONFLICTING DIRTY ccc3333 '[]')"
out="$($PRWATCH --once 103 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=conflict'; then
  pass "classify: mergeable=CONFLICTING + mergeStateStatus=DIRTY -> event=conflict"
else
  fail "classify: conflict (rc=$rc out=[$out])"
fi

reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE","name":"CI / foundation-tests"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"TIMED_OUT","name":"Delivery contract evidence"}]'
export FAKE_PR_VIEW_104="$(pr_json 104 OPEN false MERGEABLE CLEAN ddd4444 "$checks")"
out="$($PRWATCH --once 104 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=check-failed' \
   && printf '%s' "$out" | grep -q 'checks="CI / foundation-tests,Delivery contract evidence"'; then
  pass "classify: FAILURE + TIMED_OUT checks -> event=check-failed, names joined"
else
  fail "classify: check-failed (rc=$rc out=[$out])"
fi

reset_env
export FAKE_PR_VIEW_105="$(pr_json 105 OPEN false MERGEABLE BEHIND eee5555 '[]')"
out="$($PRWATCH --once 105 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=behind'; then
  pass "classify: mergeStateStatus=BEHIND -> event=behind"
else
  fail "classify: behind (rc=$rc out=[$out])"
fi

reset_env
checks='[{"__typename":"CheckRun","status":"IN_PROGRESS","name":"unit-tests"}]'
export FAKE_PR_VIEW_106="$(pr_json 106 OPEN false MERGEABLE CLEAN fff6666 "$checks")"
out="$($PRWATCH --once 106 2>/dev/null)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '^OK 1 PRs, none need action (pending=1)$'; then
  pass "classify: a still-running check -> event=pending, NOT reported as an action"
else
  fail "classify: pending (rc=$rc out=[$out])"
fi

reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]'
export FAKE_PR_VIEW_107="$(pr_json 107 OPEN false MERGEABLE CLEAN a7a7a7a7 "$checks")"
out="$($PRWATCH --once 107 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=ready'; then
  pass "classify: not draft, all checks green, clean -> event=ready"
else
  fail "classify: ready (rc=$rc out=[$out])"
fi

# A CANCELLED conclusion is not a plain "check-failed" — but it is not a pass
# either. A check name (grouped by workflowName+name) whose only run on this
# head is CANCELLED, with no SUCCESS/NEUTRAL/SKIPPED run for that same name,
# is its own event: check-cancelled.
reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"CI","workflowName":"CI"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"CANCELLED","name":"Classify and auto-merge","workflowName":"Merge Automation"}]'
export FAKE_PR_VIEW_108="$(pr_json 108 OPEN false MERGEABLE CLEAN b8b8b8b8 "$checks")"
out="$($PRWATCH --once 108 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=check-cancelled' \
   && printf '%s' "$out" | grep -q 'checks="Classify and auto-merge"' \
   && ! printf '%s' "$out" | grep -q 'event=check-failed' \
   && ! printf '%s' "$out" | grep -q 'event=ready'; then
  pass "classify: a CANCELLED check with no later success on the same name -> event=check-cancelled (not check-failed, not ready)"
else
  fail "classify: check-cancelled alone (rc=$rc out=[$out])"
fi

# A body edit that re-triggers the same check and this time it SUCCEEDS —
# same workflowName+name, one CANCELLED run and one SUCCESS run — is a pass:
# the gate did eventually run green on this head.
reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"CI","workflowName":"CI"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"CANCELLED","name":"Classify and auto-merge","workflowName":"Merge Automation"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"Classify and auto-merge","workflowName":"Merge Automation"}]'
export FAKE_PR_VIEW_109="$(pr_json 109 OPEN false MERGEABLE CLEAN c9c9c9c9 "$checks")"
out="$($PRWATCH --once 109 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=ready' \
   && ! printf '%s' "$out" | grep -q 'check-cancelled'; then
  pass "classify: a CANCELLED run followed by a SUCCESS run of the same name -> event=ready (the gate eventually passed)"
else
  fail "classify: cancelled-then-success (rc=$rc out=[$out])"
fi

# A check name listed in config .checks.cancelledOk is exempt from
# check-cancelled even with no later success — a job that cancels itself by
# design.
reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"CI","workflowName":"CI"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"CANCELLED","name":"Classify and auto-merge","workflowName":"Merge Automation"}]'
export FAKE_PR_VIEW_108="$(pr_json 108 OPEN false MERGEABLE CLEAN b8b8b8b8 "$checks")"
out="$(LANES_CONFIG="$LANES_FIXTURE_CANCELLED_OK" $PRWATCH --once 108 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=ready' \
   && ! printf '%s' "$out" | grep -q 'check-cancelled'; then
  pass "classify: a check name in config checks.cancelledOk is exempt from check-cancelled -> event=ready"
else
  fail "classify: cancelledOk exemption (rc=$rc out=[$out])"
fi

# A StatusContext entry (has no CheckRun name/workflowName/conclusion shape)
# sitting alongside a genuinely cancelled CheckRun must not interfere with —
# or be swept into — the check-cancelled classification either way.
reset_env
checks='[{"__typename":"StatusContext","context":"ci/legacy-status","state":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"CANCELLED","name":"Classify and auto-merge","workflowName":"Merge Automation"}]'
export FAKE_PR_VIEW_114="$(pr_json 114 OPEN false MERGEABLE CLEAN d1d1d1d1 "$checks")"
out="$($PRWATCH --once 114 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=check-cancelled' \
   && printf '%s' "$out" | grep -q 'checks="Classify and auto-merge"'; then
  pass "classify: a StatusContext entry alongside a cancelled CheckRun does not block or distort check-cancelled classification"
else
  fail "classify: StatusContext unaffected by check-cancelled (rc=$rc out=[$out])"
fi

# Mutation check: neutralize the check-cancelled classification entirely; the
# cancelled-alone fixture above must then misclassify as ready (proves the
# feature itself is load-bearing, not merely present).
mutant="$WORK/pr-watch.cancelled-mutant.sh"
sed 's/if \[ -n "\$cancelled" \]; then/if false; then/' "$PRWATCH" > "$mutant"
chmod +x "$mutant"
reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"CI","workflowName":"CI"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"CANCELLED","name":"Classify and auto-merge","workflowName":"Merge Automation"}]'
export FAKE_PR_VIEW_108="$(pr_json 108 OPEN false MERGEABLE CLEAN b8b8b8b8 "$checks")"
mut_out="$("$mutant" --once 108 2>/dev/null)"
if printf '%s' "$mut_out" | grep -q 'event=ready'; then
  pass "classify: MUTATION CHECK — disabling check-cancelled classification misreports the cancelled-alone fixture as ready (feature is load-bearing)"
else
  fail "classify: MUTATION CHECK — disabling check-cancelled classification should have misreported ready, but it didn't (got [$mut_out])"
fi

reset_env
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]'
export FAKE_PR_VIEW_108="$(pr_json 108 OPEN true MERGEABLE CLEAN b8b8b8b8 "$checks")"
out="$($PRWATCH --once 108 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=draft-green'; then
  pass "classify: draft + all checks green -> event=draft-green"
else
  fail "classify: draft-green (rc=$rc out=[$out])"
fi

# Mutation check: neutralize the conflict-classifier condition; the
# conflict-shaped fixture above must then classify as something else
# (proves test #3 is actually exercising that branch, not passing by luck).
mutant="$WORK/pr-watch.conflict-mutant.sh"
sed 's/if \[ "\$mergeable" = "CONFLICTING" \] || \[ "\$merge_state" = "DIRTY" \]; then/if false; then/' "$PRWATCH" > "$mutant"
chmod +x "$mutant"
reset_env
export FAKE_PR_VIEW_103="$(pr_json 103 OPEN false CONFLICTING DIRTY ccc3333 '[]')"
mut_out="$("$mutant" --once 103 2>/dev/null)"
if printf '%s' "$mut_out" | grep -q 'event=conflict'; then
  fail "classify: MUTATION CHECK — disabling the conflict condition should change the classification, but 'conflict' was still reported"
else
  pass "classify: MUTATION CHECK — disabling the conflict condition changes the outcome away from 'conflict' (got [$mut_out])"
fi

# ===========================================================================
# 1b. StatusContext handling (P1) — GitHub's other check-rollup shape.
# {__typename:"StatusContext", context, state} instead of CheckRun's
# {__typename:"CheckRun", name, status, conclusion}. A repo that runs GitHub
# Actions exclusively (no external commit-status integrations) never emits
# this shape, so these fixtures follow GitHub's public GraphQL schema for
# StatusContext instead of an observed sample.
# ===========================================================================

reset_env
checks='[{"__typename":"StatusContext","context":"ci/legacy-status","state":"FAILURE"}]'
export FAKE_PR_VIEW_110="$(pr_json 110 OPEN false MERGEABLE CLEAN aa10aa10 "$checks")"
out="$($PRWATCH --once 110 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=check-failed' \
   && printf '%s' "$out" | grep -q 'checks="ci/legacy-status"'; then
  pass "classify: StatusContext state=FAILURE -> event=check-failed, .context used as name (not .name, which StatusContext lacks)"
else
  fail "classify: StatusContext FAILURE (rc=$rc out=[$out])"
fi

reset_env
checks='[{"__typename":"StatusContext","context":"ci/legacy-status","state":"ERROR"}]'
export FAKE_PR_VIEW_111="$(pr_json 111 OPEN false MERGEABLE CLEAN bb11bb11 "$checks")"
out="$($PRWATCH --once 111 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=check-failed' \
   && printf '%s' "$out" | grep -q 'checks="ci/legacy-status"'; then
  pass "classify: StatusContext state=ERROR -> event=check-failed (ERROR is a StatusContext-only failure state)"
else
  fail "classify: StatusContext ERROR (rc=$rc out=[$out])"
fi

reset_env
checks='[{"__typename":"StatusContext","context":"ci/legacy-status","state":"PENDING"}]'
export FAKE_PR_VIEW_112="$(pr_json 112 OPEN false MERGEABLE CLEAN cc12cc12 "$checks")"
out="$($PRWATCH --once 112 2>/dev/null)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'pending=1'; then
  pass "classify: StatusContext state=PENDING -> event=pending, not actionable"
else
  fail "classify: StatusContext PENDING (rc=$rc out=[$out])"
fi

reset_env
checks='[{"__typename":"StatusContext","context":"ci/legacy-status","state":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]'
export FAKE_PR_VIEW_113="$(pr_json 113 OPEN false MERGEABLE CLEAN dd13dd13 "$checks")"
out="$($PRWATCH --once 113 2>/dev/null)"; rc=$?
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'event=ready'; then
  pass "classify: StatusContext SUCCESS mixed with a green CheckRun -> event=ready"
else
  fail "classify: StatusContext SUCCESS mixed (rc=$rc out=[$out])"
fi

# Mutation check: revert to reading .name only (the pre-fix bug) — the
# StatusContext FAILURE fixture above must then classify as something other
# than check-failed (proves the .context fallback is load-bearing).
mutant="$WORK/pr-watch.statuscontext-mutant.sh"
sed "s/(\$e.name \/\/ \$e.context \/\/ \"unknown\") as \$nm/(\$e.name) as \$nm/" "$PRWATCH" > "$mutant"
chmod +x "$mutant"
reset_env
checks='[{"__typename":"StatusContext","context":"ci/legacy-status","state":"FAILURE"}]'
export FAKE_PR_VIEW_110="$(pr_json 110 OPEN false MERGEABLE CLEAN aa10aa10 "$checks")"
mut_out="$("$mutant" --once 110 2>/dev/null)"
if printf '%s' "$mut_out" | grep -q 'event=check-failed'; then
  fail "classify: MUTATION CHECK — reading .name only should stop classifying a StatusContext failure as check-failed, but it still did ([$mut_out])"
else
  pass "classify: MUTATION CHECK — reading .name only (pre-fix) changes the outcome away from check-failed (got [$mut_out])"
fi

# ===========================================================================
# 1c. Empty/null statusCheckRollup (P2) — treated as pending, not ready.
# ===========================================================================

reset_env
export FAKE_PR_VIEW_120="$(pr_json 120 OPEN false MERGEABLE CLEAN ee14ee14 '[]')"
out="$($PRWATCH --once 120 2>/dev/null)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'pending=1'; then
  pass "classify: empty statusCheckRollup ([]) -> event=pending, not ready"
else
  fail "classify: empty rollup (rc=$rc out=[$out])"
fi

reset_env
export FAKE_PR_VIEW_121="$(printf '{"number":121,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"","headRefOid":"ff15ff15","statusCheckRollup":null}')"
out="$($PRWATCH --once 121 2>/dev/null)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'pending=1'; then
  pass "classify: null statusCheckRollup -> event=pending, not ready"
else
  fail "classify: null rollup (rc=$rc out=[$out])"
fi

# Mutation check: neutralize the zero-checks guard; the empty-rollup fixture
# above must then misclassify as ready (proves the guard is load-bearing).
mutant="$WORK/pr-watch.zerochecks-mutant.sh"
sed 's/\[ "\$pending_count" -gt 0 \] || \[ "\$total_checks" -eq 0 \]/[ "$pending_count" -gt 0 ]/' "$PRWATCH" > "$mutant"
chmod +x "$mutant"
reset_env
export FAKE_PR_VIEW_120="$(pr_json 120 OPEN false MERGEABLE CLEAN ee14ee14 '[]')"
mut_out="$("$mutant" --once 120 2>/dev/null)"; mut_rc=$?
if [ "$mut_rc" = "10" ] && printf '%s' "$mut_out" | grep -q 'event=ready'; then
  pass "classify: MUTATION CHECK — disabling the zero-checks guard makes an empty rollup misclassify as ready (got [$mut_out])"
else
  fail "classify: MUTATION CHECK — disabling the zero-checks guard should have made the empty-rollup PR classify as ready (rc=$mut_rc out=[$mut_out])"
fi

# ===========================================================================
# 2. Dedup — same (head, event) not re-reported; a new head re-reported
# ===========================================================================
reset_env
export FAKE_PR_VIEW_200="$(pr_json 200 OPEN false MERGEABLE CLEAN head0001 '[{"status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]')"
out1="$($PRWATCH --once 200 2>/dev/null)"; rc1=$?
out2="$($PRWATCH --once 200 2>/dev/null)"; rc2=$?
if [ "$rc1" = "10" ] && printf '%s' "$out1" | grep -q 'event=ready' \
   && [ "$rc2" = "0" ]; then
  pass "dedup: identical (head, event) on the next poll is NOT re-reported (rc 10 then 0)"
else
  fail "dedup: same-head suppression (rc1=$rc1 out1=[$out1] rc2=$rc2 out2=[$out2])"
fi

# New head, same event type -> must report again (new information: still
# ready after a new push).
export FAKE_PR_VIEW_200="$(pr_json 200 OPEN false MERGEABLE CLEAN head0002 '[{"status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]')"
out3="$($PRWATCH --once 200 2>/dev/null)"; rc3=$?
if [ "$rc3" = "10" ] && printf '%s' "$out3" | grep -q 'head=head0002'; then
  pass "dedup: a new headRefOid with the same event re-reports"
else
  fail "dedup: new-head re-report (rc3=$rc3 out3=[$out3])"
fi

# Mutation check: neutralize the dedup guard; the second identical-head poll
# must then report AGAIN (proves the dedup assertion above is load-bearing).
mutant="$WORK/pr-watch.dedup-mutant.sh"
sed 's/if \[ "\$new_state" = "\$last" \]; then/if false; then/' "$PRWATCH" > "$mutant"
chmod +x "$mutant"
reset_env
export FAKE_PR_VIEW_200="$(pr_json 200 OPEN false MERGEABLE CLEAN head0001 '[{"status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]')"
"$mutant" --once 200 >/dev/null 2>/dev/null
mut_out2="$("$mutant" --once 200 2>/dev/null)"; mut_rc2=$?
if [ "$mut_rc2" = "10" ]; then
  pass "dedup: MUTATION CHECK — disabling the dedup guard makes the identical poll report again (rc=$mut_rc2)"
else
  fail "dedup: MUTATION CHECK — disabling the dedup guard should have made the 2nd poll report again, but rc=$mut_rc2"
fi

# ===========================================================================
# 3. --agent discovery, including a PR that merged between polls
# ===========================================================================
reset_env
green_check='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]'
export FAKE_PR_LIST_JSON="[$(pr_json 700 OPEN false MERGEABLE CLEAN aaaa1111 "$green_check")]"
out1="$($PRWATCH --once --agent C-TEST-AGENT 2>/dev/null)"; rc1=$?

# Second poll: the PR is gone from the open list (merged) — pr-watch must
# individually re-check it and report merged, without the caller passing
# the number explicitly.
export FAKE_PR_LIST_JSON='[]'
export FAKE_PR_VIEW_700="$(pr_json 700 MERGED false UNKNOWN UNKNOWN aaaa1111 '[]')"
out2="$($PRWATCH --once --agent C-TEST-AGENT 2>/dev/null)"; rc2=$?

if [ "$rc1" = "10" ] && printf '%s' "$out1" | grep -q 'pr=700 event=ready' \
   && [ "$rc2" = "10" ] && printf '%s' "$out2" | grep -q 'pr=700 event=merged'; then
  pass "--agent: discovers an open PR by label, then reports merged once it disappears from the open list"
else
  fail "--agent: discovery + disappearance (rc1=$rc1 out1=[$out1] rc2=$rc2 out2=[$out2])"
fi

# --agent and explicit PR numbers together must be refused.
reset_env
"$PRWATCH" --agent C-TEST-AGENT 5 >/dev/null 2>/dev/null
if [ "$?" != "0" ]; then
  pass "--agent + explicit PR numbers together is refused"
else
  fail "--agent + explicit PR numbers together should be refused"
fi

# --agent: a PR that vanishes from the open list AND whose individual
# `gh pr view` fails (transient — rate limit, GitHub-side lag) must stay in
# known-prs and be retried, not dropped, so its eventual merged/closed event
# is still reported (P3).
reset_env
green_check='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]'
export FAKE_PR_LIST_JSON="[$(pr_json 800 OPEN false MERGEABLE CLEAN 80080080 "$green_check")]"
out1="$($PRWATCH --once --agent C-RETRY-AGENT 2>/dev/null)"; rc1=$?

# Poll 2: vanished from the open list, and the individual view call fails
# transiently — must NOT be dropped from known-prs.
export FAKE_PR_LIST_JSON='[]'
export FAKE_PR_VIEW_FAIL_800="gh: rate limited"
out2="$($PRWATCH --once --agent C-RETRY-AGENT 2>/dev/null)"; rc2=$?

# Poll 3: still vanished, view call now succeeds and reports merged.
unset FAKE_PR_VIEW_FAIL_800
export FAKE_PR_VIEW_800="$(pr_json 800 MERGED false UNKNOWN UNKNOWN 80080080 '[]')"
out3="$($PRWATCH --once --agent C-RETRY-AGENT 2>/dev/null)"; rc3=$?

if [ "$rc1" = "10" ] && printf '%s' "$out1" | grep -q 'pr=800 event=ready' \
   && [ "$rc2" = "0" ] && printf '%s' "$out2" | grep -q '^OK 0 PRs' \
   && [ "$rc3" = "10" ] && printf '%s' "$out3" | grep -q 'pr=800 event=merged'; then
  pass "--agent: a vanished PR whose gh pr view fails transiently is retried next poll, not dropped, and its merged event is eventually reported"
else
  fail "--agent: vanished-PR retry (rc1=$rc1 out1=[$out1] rc2=$rc2 out2=[$out2] rc3=$rc3 out3=[$out3])"
fi

# Mutation check: revert to the pre-fix behavior (write only current_numbers
# to KNOWN_FILE, dropping a failed-view PR) — the same scenario must then
# lose the merged event permanently.
mutant="$WORK/pr-watch.knownfile-mutant.sh"
sed "s/{ printf '%s\\\\n' \"\$current_numbers\"; printf '%s' \"\$still_missing\"; } \\\\/{ printf '%s\\\\n' \"\$current_numbers\"; } \\\\/" "$PRWATCH" > "$mutant"
chmod +x "$mutant"
reset_env
export FAKE_PR_LIST_JSON="[$(pr_json 801 OPEN false MERGEABLE CLEAN 81081081 "$green_check")]"
"$mutant" --once --agent C-RETRY-MUTANT-AGENT >/dev/null 2>/dev/null
export FAKE_PR_LIST_JSON='[]'
export FAKE_PR_VIEW_FAIL_801="gh: rate limited"
"$mutant" --once --agent C-RETRY-MUTANT-AGENT >/dev/null 2>/dev/null
unset FAKE_PR_VIEW_FAIL_801
export FAKE_PR_VIEW_801="$(pr_json 801 MERGED false UNKNOWN UNKNOWN 81081081 '[]')"
mut_out="$("$mutant" --once --agent C-RETRY-MUTANT-AGENT 2>/dev/null)"; mut_rc=$?
if printf '%s' "$mut_out" | grep -q 'pr=801 event=merged'; then
  fail "classify: MUTATION CHECK — dropping failed-view PRs from known-prs should have lost the merged event, but it was still reported ([$mut_out])"
else
  pass "classify: MUTATION CHECK — reverting to current_numbers-only known-prs loses the merged event after a transient view failure (got rc=$mut_rc out=[$mut_out])"
fi

# ===========================================================================
# 3b. GraphQL call-count budget — --agent mode must classify ALL currently-open
# PRs from the ONE `gh pr list` call's JSON; it must NOT issue a `gh pr view`
# per PR. Every lane's pr-watch.sh and the board-project-sync workflow share
# one GitHub user's 5000-point/hour GraphQL budget — a per-PR view call here
# multiplies straight into that shared budget.
# ===========================================================================
reset_env
green_check='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS","name":"lint"}]'
conflict_check='[]'
failing_check='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE","name":"CI / foundation-tests"}]'
export FAKE_PR_LIST_JSON="[$(pr_json 901 OPEN false MERGEABLE CLEAN 90190190 "$failing_check"),$(pr_json 902 OPEN false CONFLICTING DIRTY 90290290 "$conflict_check"),$(pr_json 903 OPEN true MERGEABLE CLEAN 90390390 "$green_check"),$(pr_json 904 OPEN false MERGEABLE CLEAN 90490490 "$green_check")]"
out="$($PRWATCH --once --agent C-BUDGET-AGENT 2>"$WORK/budget.err")"; rc=$?
list_calls="$(grep -c '^pr list ' "$FAKE_GH_LOG" || true)"
view_calls="$(grep -c '^pr view ' "$FAKE_GH_LOG" || true)"

if [ "$rc" = "10" ] \
   && [ "${list_calls:-0}" = "1" ] && [ "${view_calls:-0}" = "0" ] \
   && printf '%s' "$out" | grep -q 'pr=901 event=check-failed' \
   && printf '%s' "$out" | grep -q 'pr=902 event=conflict' \
   && printf '%s' "$out" | grep -q 'pr=903 event=draft-green' \
   && printf '%s' "$out" | grep -q 'pr=904 event=ready'; then
  pass "call-count budget: one poll over 4 open PRs makes exactly ONE 'gh pr list' call and ZERO 'gh pr view' calls, all four events (check-failed/conflict/draft-green/ready) classified correctly from the batched list JSON"
else
  fail "call-count budget (rc=$rc list_calls=$list_calls view_calls=$view_calls out=[$out] err=[$(cat "$WORK/budget.err")])"
fi

# Mutation check: revert run_poll's --agent loop to the pre-fix shape — one
# `fetch_pr_json` (gh pr view) call per PR in the list, instead of reading
# each PR's JSON straight out of the already-fetched list — and confirm the
# call-count assertion above then fails (proves it is not vacuous).
mutant="$WORK/pr-watch.perpr-view-mutant.sh"
awk '
  index($0, "select(.number == $n)") {
    print "        pr_json=\"$(fetch_pr_json \"$n\")\""
    next
  }
  { print }
' "$PRWATCH" > "$mutant"
chmod +x "$mutant"
if ! grep -q 'fetch_pr_json "\$n"' "$mutant"; then
  fail "call-count budget: MUTATION CHECK — the awk patch did not introduce a per-PR fetch_pr_json call (mutant is unchanged, proves nothing)"
else
  reset_env
  export FAKE_PR_LIST_JSON="[$(pr_json 901 OPEN false MERGEABLE CLEAN 90190190 "$failing_check"),$(pr_json 902 OPEN false CONFLICTING DIRTY 90290290 "$conflict_check"),$(pr_json 903 OPEN true MERGEABLE CLEAN 90390390 "$green_check"),$(pr_json 904 OPEN false MERGEABLE CLEAN 90490490 "$green_check")]"
  export FAKE_PR_VIEW_901="$(pr_json 901 OPEN false MERGEABLE CLEAN 90190190 "$failing_check")"
  export FAKE_PR_VIEW_902="$(pr_json 902 OPEN false CONFLICTING DIRTY 90290290 "$conflict_check")"
  export FAKE_PR_VIEW_903="$(pr_json 903 OPEN true MERGEABLE CLEAN 90390390 "$green_check")"
  export FAKE_PR_VIEW_904="$(pr_json 904 OPEN false MERGEABLE CLEAN 90490490 "$green_check")"
  "$mutant" --once --agent C-BUDGET-MUTANT-AGENT >/dev/null 2>/dev/null
  mut_view_calls="$(grep -c '^pr view ' "$FAKE_GH_LOG" || true)"
  if [ "${mut_view_calls:-0}" -gt 0 ]; then
    pass "call-count budget: MUTATION CHECK — reverting to a per-PR 'gh pr view' loop makes the zero-view-calls assertion fail ($mut_view_calls view call(s)), proving the batching invariant above is load-bearing"
  else
    fail "call-count budget: MUTATION CHECK — the per-PR-view mutant should have issued 'gh pr view' calls, but made none"
  fi
fi

# ===========================================================================
# 4. gh failure on one PR -> WARN + continue; the other PR still reports
# ===========================================================================
reset_env
export FAKE_PR_VIEW_FAIL_301="gh: pull request not found"
export FAKE_PR_VIEW_302="$(pr_json 302 OPEN false CONFLICTING DIRTY dead0001 '[]')"
out="$($PRWATCH --once 301 302 2>"$WORK/warn.err")"; rc=$?
warn="$(cat "$WORK/warn.err")"
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'pr=302 event=conflict' \
   && printf '%s' "$warn" | grep -q 'WARN pr-watch: gh failed for pr=301'; then
  pass "gh failure on one PR: WARN to stderr, poll continues, surviving PR still reports"
else
  fail "gh failure partial (rc=$rc out=[$out] warn=[$warn])"
fi

# ===========================================================================
# 5. Every gh call fails this poll -> exit 2, no false OK/IDLE
# ===========================================================================
reset_env
export FAKE_PR_VIEW_FAIL_401="gh: connection reset"
export FAKE_PR_VIEW_FAIL_402="gh: connection reset"
out="$($PRWATCH --once 401 402 2>"$WORK/allfail.err")"; rc=$?
if [ "$rc" = "2" ] && grep -q '^ERROR pr-watch: all 2 gh call(s) failed' "$WORK/allfail.err"; then
  pass "all gh calls failing this poll -> exit 2, ERROR line, no OK/IDLE printed"
else
  fail "all-fail (rc=$rc out=[$out] err=[$(cat "$WORK/allfail.err")])"
fi

# ===========================================================================
# 6. gh_checks (gh-checks.sh) — routing around a fine-grained PAT GH_TOKEN
# that cannot read check runs.
#
# Real shape, per gh's documented GraphQL error for this case:
#   gh pr view <n> --json statusCheckRollup    (GH_TOKEN = fine-grained PAT)
#     -> exit 1, stderr: "GraphQL: Resource not accessible by personal
#        access token (repository.pullRequest.statusCheckRollup.nodes.0.
#        commit.statusCheckRollup.contexts.nodes.0), ..."
#   GH_TOKEN= gh pr view <n> --json statusCheckRollup   (keyring login)
#     -> exit 0, stdout: {"statusCheckRollup":[{"__typename":"CheckRun",...}]}
# The fakes below reproduce exactly this shape: fail with the real PAT error
# whenever GH_TOKEN is non-empty, succeed with a real-shaped JSON sample
# whenever it is unset/empty — the same branch a real fine-grained-PAT vs.
# keyring-login `gh` takes.
# ===========================================================================

GH_CHECKS_SH="$BOARD_DIR/gh-checks.sh"
PAT_ERROR_LINE='GraphQL: Resource not accessible by personal access token (repository.pullRequest.statusCheckRollup.nodes.0.commit.statusCheckRollup.contexts.nodes.0)'

# ---------------------------------------------------------------------------
# 6a. GH_TOKEN set (PAT) -> gh_checks succeeds via the keyring fallback,
# output is the real JSON, NOTE printed exactly once across two calls
# (memoized after the first probe).
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_A'
#!/usr/bin/env bash
set -uo pipefail
: "${GH_CHECKS_CALL_LOG:=/dev/null}"
echo "call GH_TOKEN=[${GH_TOKEN:-}]" >> "$GH_CHECKS_CALL_LOG"
if [ -n "${GH_TOKEN:-}" ]; then
  echo "$PAT_ERROR_LINE" >&2
  exit 1
fi
printf '%s' '{"statusCheckRollup":[{"__typename":"CheckRun","completedAt":"2026-01-01T00:00:00Z","conclusion":"SUCCESS","detailsUrl":"https://github.com/x/y/actions/runs/1/job/1","name":"Branch name lint","startedAt":"2026-01-01T00:00:00Z","status":"COMPLETED","workflowName":"Branch name lint"}]}'
exit 0
GHCHECKS_FAKE_A
chmod +x "$FAKE_BIN/gh"

export GH_CHECKS_CALL_LOG="$WORK/gh-checks-a.calls"
: > "$GH_CHECKS_CALL_LOG"
(
  export GH_TOKEN="github_pat_11FAKEFAKEFAKEFAKEFAKEFAKE"
  export PAT_ERROR_LINE
  unset BOARD_CHECKS_TOKEN
  # shellcheck disable=SC1091
  source "$GH_CHECKS_SH"
  out1="$(gh_checks pr view 1 --json statusCheckRollup)"; rc1=$?
  out2="$(gh_checks pr view 2 --json statusCheckRollup)"; rc2=$?
  printf 'RC1\t%s\n' "$rc1"
  printf 'OUT1\t%s\n' "$out1"
  printf 'RC2\t%s\n' "$rc2"
  printf 'OUT2\t%s\n' "$out2"
) > "$WORK/gh-checks-a.out" 2> "$WORK/gh-checks-a.err"

rc1="$(awk -F'\t' '$1=="RC1"{print $2}' "$WORK/gh-checks-a.out")"
rc2="$(awk -F'\t' '$1=="RC2"{print $2}' "$WORK/gh-checks-a.out")"
out1="$(awk -F'\t' '$1=="OUT1"{print $2}' "$WORK/gh-checks-a.out")"
out2="$(awk -F'\t' '$1=="OUT2"{print $2}' "$WORK/gh-checks-a.out")"
note_count="$(grep -c '^NOTE gh-checks:' "$WORK/gh-checks-a.err" || true)"
call_count="$(wc -l < "$GH_CHECKS_CALL_LOG" | tr -d ' ')"

if [ "$rc1" = "0" ] && [ "$rc2" = "0" ] \
   && printf '%s' "$out1" | grep -q '"statusCheckRollup"' \
   && [ "$out1" = "$out2" ] \
   && [ "$note_count" = "1" ] \
   && [ "$call_count" = "3" ]; then
  pass "gh_checks: GH_TOKEN set (fine-grained PAT) -> falls back to keyring login, real JSON returned, NOTE printed exactly once across two calls (memoized: 1 failed probe + 2 keyring calls = 3 gh invocations)"
else
  fail "gh_checks: GH_TOKEN fallback (rc1=$rc1 rc2=$rc2 note_count=$note_count call_count=$call_count out1=[$out1] out2=[$out2] err=[$(cat "$WORK/gh-checks-a.err")])"
fi

# ---------------------------------------------------------------------------
# 6b. BOARD_CHECKS_TOKEN set -> used directly, no probing, no NOTE — even
# though the ambient GH_TOKEN is a broken PAT that would otherwise fail.
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_B'
#!/usr/bin/env bash
set -uo pipefail
: "${GH_CHECKS_CALL_LOG:=/dev/null}"
echo "call GH_TOKEN=[${GH_TOKEN:-}]" >> "$GH_CHECKS_CALL_LOG"
if [ "${GH_TOKEN:-}" = "board-checks-token-value" ]; then
  printf '%s' '{"statusCheckRollup":[]}'
  exit 0
fi
echo "$PAT_ERROR_LINE" >&2
exit 1
GHCHECKS_FAKE_B
chmod +x "$FAKE_BIN/gh"

export GH_CHECKS_CALL_LOG="$WORK/gh-checks-b.calls"
: > "$GH_CHECKS_CALL_LOG"
(
  export GH_TOKEN="github_pat_11AMBIENT_BROKEN"
  export BOARD_CHECKS_TOKEN="board-checks-token-value"
  export PAT_ERROR_LINE
  # shellcheck disable=SC1091
  source "$GH_CHECKS_SH"
  out="$(gh_checks pr view 1 --json statusCheckRollup)"; rc=$?
  printf 'RC\t%s\n' "$rc"
  printf 'OUT\t%s\n' "$out"
) > "$WORK/gh-checks-b.out" 2> "$WORK/gh-checks-b.err"

rc="$(awk -F'\t' '$1=="RC"{print $2}' "$WORK/gh-checks-b.out")"
out="$(awk -F'\t' '$1=="OUT"{print $2}' "$WORK/gh-checks-b.out")"
note_count="$(grep -c '^NOTE gh-checks:' "$WORK/gh-checks-b.err" || true)"
call_count="$(wc -l < "$GH_CHECKS_CALL_LOG" | tr -d ' ')"

if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '"statusCheckRollup"' \
   && [ "${note_count:-0}" = "0" ] && [ "$call_count" = "1" ]; then
  pass "gh_checks: BOARD_CHECKS_TOKEN set -> used directly (overrides a broken ambient GH_TOKEN), single call, no NOTE"
else
  fail "gh_checks: BOARD_CHECKS_TOKEN direct-use (rc=$rc note_count=$note_count call_count=$call_count out=[$out])"
fi

# ---------------------------------------------------------------------------
# 6c. Both the active GH_TOKEN and the keyring login fail -> non-zero exit,
# ERROR line names both credentials, stdout empty (never a silent empty
# success-shaped result).
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_C'
#!/usr/bin/env bash
set -uo pipefail
: "${GH_CHECKS_CALL_LOG:=/dev/null}"
echo "call GH_TOKEN=[${GH_TOKEN:-}]" >> "$GH_CHECKS_CALL_LOG"
echo "$PAT_ERROR_LINE" >&2
exit 1
GHCHECKS_FAKE_C
chmod +x "$FAKE_BIN/gh"

export GH_CHECKS_CALL_LOG="$WORK/gh-checks-c.calls"
: > "$GH_CHECKS_CALL_LOG"
(
  export GH_TOKEN="github_pat_11ALWAYS_BROKEN"
  export PAT_ERROR_LINE
  unset BOARD_CHECKS_TOKEN
  # shellcheck disable=SC1091
  source "$GH_CHECKS_SH"
  out="$(gh_checks pr view 1 --json statusCheckRollup)"; rc=$?
  printf 'RC\t%s\n' "$rc"
  printf 'OUT\t%s\n' "$out"
) > "$WORK/gh-checks-c.out" 2> "$WORK/gh-checks-c.err"

rc="$(awk -F'\t' '$1=="RC"{print $2}' "$WORK/gh-checks-c.out")"
out="$(awk -F'\t' '$1=="OUT"{print $2}' "$WORK/gh-checks-c.out")"

if [ -n "$rc" ] && [ "$rc" != "0" ] && [ -z "$out" ] \
   && grep -q '^ERROR gh-checks:' "$WORK/gh-checks-c.err" \
   && grep -qi 'GH_TOKEN' "$WORK/gh-checks-c.err" \
   && grep -qi 'keyring' "$WORK/gh-checks-c.err"; then
  pass "gh_checks: both GH_TOKEN and the keyring login fail -> non-zero exit, ERROR names both credentials, stdout empty"
else
  fail "gh_checks: both-fail (rc=$rc out=[$out] err=[$(cat "$WORK/gh-checks-c.err")])"
fi

# ---------------------------------------------------------------------------
# 6d. An unrelated gh failure (not the PAT-checks error) -> no retry,
# original stderr and exit code pass through unchanged.
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_D'
#!/usr/bin/env bash
set -uo pipefail
: "${GH_CHECKS_CALL_LOG:=/dev/null}"
echo "call GH_TOKEN=[${GH_TOKEN:-}]" >> "$GH_CHECKS_CALL_LOG"
echo 'gh: pull request not found' >&2
exit 7
GHCHECKS_FAKE_D
chmod +x "$FAKE_BIN/gh"

export GH_CHECKS_CALL_LOG="$WORK/gh-checks-d.calls"
: > "$GH_CHECKS_CALL_LOG"
(
  export GH_TOKEN="github_pat_11WHATEVER"
  unset BOARD_CHECKS_TOKEN
  # shellcheck disable=SC1091
  source "$GH_CHECKS_SH"
  out="$(gh_checks pr view 999 --json statusCheckRollup)"; rc=$?
  printf 'RC\t%s\n' "$rc"
  printf 'OUT\t%s\n' "$out"
) > "$WORK/gh-checks-d.out" 2> "$WORK/gh-checks-d.err"

rc="$(awk -F'\t' '$1=="RC"{print $2}' "$WORK/gh-checks-d.out")"
call_count="$(wc -l < "$GH_CHECKS_CALL_LOG" | tr -d ' ')"

if [ "$rc" = "7" ] && grep -q 'gh: pull request not found' "$WORK/gh-checks-d.err" \
   && ! grep -q '^NOTE gh-checks:' "$WORK/gh-checks-d.err" \
   && ! grep -q '^ERROR gh-checks:' "$WORK/gh-checks-d.err" \
   && [ "$call_count" = "1" ]; then
  pass "gh_checks: an unrelated gh failure is not retried — original stderr + exit code pass through, gh called exactly once"
else
  fail "gh_checks: unrelated-failure passthrough (rc=$rc call_count=$call_count err=[$(cat "$WORK/gh-checks-d.err")])"
fi

# ---------------------------------------------------------------------------
# 6e. End-to-end: pr-watch.sh --once against a stubbed PR with a FAILURE
# check, run under a PAT-only GH_TOKEN, reports event=check-failed — not an
# error — AND the gh_checks NOTE (active credential can't read checks,
# fell back to the keyring login) reaches stderr exactly once. fetch_pr_json
# captures gh_checks's whole stderr into its own per-call tmpfile; it used to
# discard that tmpfile unread on success, silently swallowing the NOTE —
# fixed by forwarding any `NOTE gh-checks:` line before discarding the rest.
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_E'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  n="${3:-}"
  if [ -n "${GH_TOKEN:-}" ]; then
    echo "$PAT_ERROR_LINE" >&2
    exit 1
  fi
  varname="FAKE_PR_VIEW_${n}"
  val="$(eval "printf '%s' \"\${${varname}:-}\"")"
  if [ -z "$val" ]; then
    echo "fake gh: no FAKE_PR_VIEW_${n} set" >&2
    exit 1
  fi
  printf '%s' "$val"
  exit 0
fi

echo "fake gh (gh-checks e2e mode): unhandled $*" >&2
exit 1
GHCHECKS_FAKE_E
chmod +x "$FAKE_BIN/gh"

checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE","name":"CI / foundation-tests"}]'
export FAKE_PR_VIEW_900="$(pr_json 900 OPEN false MERGEABLE CLEAN e2e0001 "$checks")"
export PAT_ERROR_LINE
out="$(GH_TOKEN="github_pat_11TESTONLY" $PRWATCH --once 900 2>"$WORK/gh-checks-e.err")"; rc=$?
note_count="$(grep -c '^NOTE gh-checks:' "$WORK/gh-checks-e.err" || true)"
if [ "$rc" = "10" ] && printf '%s' "$out" | grep -q 'pr=900 event=check-failed' \
   && printf '%s' "$out" | grep -q 'checks="CI / foundation-tests"' \
   && [ "${note_count:-0}" = "1" ]; then
  pass "gh_checks e2e: pr-watch.sh under a PAT-only GH_TOKEN falls back, reports event=check-failed (not an error), and forwards the NOTE to stderr exactly once"
else
  fail "gh_checks e2e: PAT fallback through pr-watch.sh (rc=$rc note_count=$note_count out=[$out] err=[$(cat "$WORK/gh-checks-e.err")])"
fi

# Restore the general pr-watch fake gh for anything that might run after
# this section.
install_fake_gh

# ---------------------------------------------------------------------------
# 6f. MUTATION CHECK: with the keyring-fallback retry removed from
# gh-checks.sh entirely, case 6a (GH_TOKEN set, PAT fails, should fall back)
# must fail instead of succeed — proves the retry is load-bearing, not
# vacuously passing.
# ---------------------------------------------------------------------------
mutant_gh_checks="$WORK/gh-checks.no-fallback-mutant.sh"
awk '
  /if grep -q .Resource not accessible by personal access token/ { skip = 1 }
  skip && /^  fi$/ { skip = 0; next }
  !skip { print }
' "$GH_CHECKS_SH" > "$mutant_gh_checks"
# Check for the CODE line specifically, not the header-comment prose above
# it (which also contains this phrase and would otherwise always match).
if grep -q "if grep -q 'Resource not accessible by personal access token'" "$mutant_gh_checks"; then
  fail "gh_checks: MUTATION CHECK — the awk strip did not remove the fallback block (mutant is unchanged, proves nothing)"
else
  reset_env
  cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_MUT'
#!/usr/bin/env bash
set -uo pipefail
if [ -n "${GH_TOKEN:-}" ]; then
  echo "$PAT_ERROR_LINE" >&2
  exit 1
fi
printf '%s' '{"statusCheckRollup":[]}'
exit 0
GHCHECKS_FAKE_MUT
  chmod +x "$FAKE_BIN/gh"
  (
    export GH_TOKEN="github_pat_11MUTANT"
    export PAT_ERROR_LINE
    unset BOARD_CHECKS_TOKEN
    # shellcheck disable=SC1091
    source "$mutant_gh_checks"
    out="$(gh_checks pr view 1 --json statusCheckRollup)"
    rc=$?
    printf 'RC\t%s\n' "$rc"
    printf 'OUT\t%s\n' "$out"
  ) > "$WORK/gh-checks-mut.out" 2>/dev/null
  mut_rc="$(awk -F'\t' '$1=="RC"{print $2}' "$WORK/gh-checks-mut.out")"
  if [ "$mut_rc" = "0" ]; then
    fail "gh_checks: MUTATION CHECK — removing the keyring fallback should have made the PAT-only case fail, but rc=0"
  else
    pass "gh_checks: MUTATION CHECK — removing the keyring fallback makes the PAT-only case fail (rc=$mut_rc), proving the fallback in 6a is load-bearing"
  fi
fi

# End-to-end mutation check: the same fallback removed, run through
# pr-watch.sh (case 6e's scenario) — a PAT-only env must now surface an
# ERROR/all-calls-failed poll instead of silently reporting check-failed.
mutant_prwatch="$WORK/pr-watch.no-fallback-mutant.sh"
cp "$PRWATCH" "$mutant_prwatch"
chmod +x "$mutant_prwatch"
cp "$mutant_gh_checks" "$WORK/gh-checks.sh"
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_MUT_E'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  if [ -n "${GH_TOKEN:-}" ]; then
    echo "$PAT_ERROR_LINE" >&2
    exit 1
  fi
  printf '%s' "${FAKE_PR_VIEW_900:-}"
  exit 0
fi
echo "unhandled $*" >&2
exit 1
GHCHECKS_FAKE_MUT_E
chmod +x "$FAKE_BIN/gh"
checks='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE","name":"CI / foundation-tests"}]'
export FAKE_PR_VIEW_900="$(pr_json 900 OPEN false MERGEABLE CLEAN e2e0001 "$checks")"
export PAT_ERROR_LINE
mut_out="$(GH_TOKEN="github_pat_11TESTONLY" "$mutant_prwatch" --once 900 2>"$WORK/gh-checks-mut-e.err")"; mut_rc=$?
if [ "$mut_rc" = "2" ]; then
  pass "gh_checks e2e: MUTATION CHECK — removing the keyring fallback makes pr-watch.sh's PAT-only poll fail loud (rc=2) instead of silently succeeding"
else
  fail "gh_checks e2e: MUTATION CHECK — removing the fallback should have made the PAT-only poll fail (rc=2), but rc=$mut_rc out=[$mut_out]"
fi
# Restore the real gh-checks.sh — line 771 above overwrote $WORK/gh-checks.sh
# with the no-fallback mutant, and leaving that in place would silently
# affect any test added below this point in the future.
cp "$BOARD_DIR/gh-checks.sh" "$WORK/gh-checks.sh"
install_fake_gh

# ---------------------------------------------------------------------------
# 6g. SCOPE GUARD (P2 review): gh_checks exists only to read PR
# check rollups. It must refuse anything that isn't `pr view`/`pr list` with
# a --json value containing statusCheckRollup — never blindly retry an
# arbitrary (possibly mutating) gh command under the keyring login just
# because it happened to fail once. `gh_checks pr merge 1` is refused with
# rc=2 and the stub gh is never invoked at all.
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_SCOPE'
#!/usr/bin/env bash
set -uo pipefail
: "${GH_CHECKS_CALL_LOG:=/dev/null}"
echo "call $*" >> "$GH_CHECKS_CALL_LOG"
echo "fake gh: should never be invoked for a disallowed gh_checks call" >&2
exit 1
GHCHECKS_FAKE_SCOPE
chmod +x "$FAKE_BIN/gh"

export GH_CHECKS_CALL_LOG="$WORK/gh-checks-scope.calls"
: > "$GH_CHECKS_CALL_LOG"
(
  unset GH_TOKEN GITHUB_TOKEN BOARD_CHECKS_TOKEN
  # shellcheck disable=SC1091
  source "$GH_CHECKS_SH"
  gh_checks pr merge 1
  echo "RC $?"
) > "$WORK/gh-checks-scope.out" 2> "$WORK/gh-checks-scope.err"

scope_rc="$(awk '$1=="RC"{print $2}' "$WORK/gh-checks-scope.out")"
scope_calls="$(wc -l < "$GH_CHECKS_CALL_LOG" | tr -d ' ')"
if [ "$scope_rc" = "2" ] && [ "$scope_calls" = "0" ] \
   && grep -q '^ERROR gh-checks: refusing' "$WORK/gh-checks-scope.err" \
   && grep -q 'pr merge 1' "$WORK/gh-checks-scope.err"; then
  pass "gh_checks: SCOPE GUARD — 'pr merge 1' is refused with rc=2 (ERROR to stderr), the stub gh is never invoked"
else
  fail "gh_checks: SCOPE GUARD (rc=$scope_rc calls=$scope_calls err=[$(cat "$WORK/gh-checks-scope.err")])"
fi

# MUTATION CHECK: with the guard's call site stripped from gh-checks.sh, the
# same disallowed call now reaches the stub gh — proving the guard above is
# load-bearing, not vacuous. Check for the CODE line specifically, not the
# header-comment prose (which also mentions the guard by name).
mutant_no_guard="$WORK/gh-checks.no-guard-mutant.sh"
awk '
  /^  if ! _gh_checks_allowed / { skip = 1 }
  skip && /^  fi$/ { skip = 0; next }
  !skip { print }
' "$GH_CHECKS_SH" > "$mutant_no_guard"
if grep -q '^  if ! _gh_checks_allowed ' "$mutant_no_guard"; then
  fail "gh_checks: SCOPE GUARD MUTATION CHECK — the awk strip did not remove the guard call site (mutant is unchanged, proves nothing)"
else
  : > "$GH_CHECKS_CALL_LOG"
  (
    unset GH_TOKEN GITHUB_TOKEN BOARD_CHECKS_TOKEN
    # shellcheck disable=SC1091
    source "$mutant_no_guard"
    gh_checks pr merge 1 >/dev/null 2>&1
    echo "RC $?"
  ) > "$WORK/gh-checks-scope-mut.out" 2>/dev/null
  mut_calls="$(wc -l < "$GH_CHECKS_CALL_LOG" | tr -d ' ')"
  if [ "$mut_calls" -gt 0 ]; then
    pass "gh_checks: SCOPE GUARD MUTATION CHECK — removing the guard's call site lets 'pr merge 1' reach the stub gh ($mut_calls call(s)), proving the guard in 6g is load-bearing"
  else
    fail "gh_checks: SCOPE GUARD MUTATION CHECK — removing the guard's call site should have let the disallowed call reach gh, but it still made zero calls"
  fi
fi
install_fake_gh

# ---------------------------------------------------------------------------
# 6h. GITHUB_TOKEN (not just GH_TOKEN) counts as an active PAT-ish
# credential: gh also honors GITHUB_TOKEN, so a caller with only GITHUB_TOKEN
# set (no GH_TOKEN) must trigger the exact same probe-and-fall-back dance —
# and the keyring retry must unset BOTH env vars, not just GH_TOKEN.
# ---------------------------------------------------------------------------
reset_env
cat > "$FAKE_BIN/gh" <<'GHCHECKS_FAKE_GITHUB_TOKEN'
#!/usr/bin/env bash
set -uo pipefail
: "${GH_CHECKS_CALL_LOG:=/dev/null}"
echo "call GH_TOKEN=[${GH_TOKEN:-}] GITHUB_TOKEN=[${GITHUB_TOKEN:-}]" >> "$GH_CHECKS_CALL_LOG"
if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "$PAT_ERROR_LINE" >&2
  exit 1
fi
printf '%s' '{"statusCheckRollup":[]}'
exit 0
GHCHECKS_FAKE_GITHUB_TOKEN
chmod +x "$FAKE_BIN/gh"

export GH_CHECKS_CALL_LOG="$WORK/gh-checks-h.calls"
: > "$GH_CHECKS_CALL_LOG"
(
  unset GH_TOKEN
  export GITHUB_TOKEN="[REDACTED:SECRET]"
  export PAT_ERROR_LINE
  unset BOARD_CHECKS_TOKEN
  # shellcheck disable=SC1091
  source "$GH_CHECKS_SH"
  out="$(gh_checks pr view 1 --json statusCheckRollup)"; rc=$?
  printf 'RC\t%s\n' "$rc"
  printf 'OUT\t%s\n' "$out"
) > "$WORK/gh-checks-h.out" 2> "$WORK/gh-checks-h.err"

rc="$(awk -F'\t' '$1=="RC"{print $2}' "$WORK/gh-checks-h.out")"
out="$(awk -F'\t' '$1=="OUT"{print $2}' "$WORK/gh-checks-h.out")"
note_count="$(grep -c '^NOTE gh-checks:' "$WORK/gh-checks-h.err" || true)"
call_count="$(wc -l < "$GH_CHECKS_CALL_LOG" | tr -d ' ')"

if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '"statusCheckRollup"' \
   && [ "${note_count:-0}" = "1" ] && [ "$call_count" = "2" ]; then
  pass "gh_checks: GITHUB_TOKEN set (GH_TOKEN unset) -> treated as an active PAT-ish credential, falls back to the keyring login with BOTH vars unset for the retry, NOTE printed once"
else
  fail "gh_checks: GITHUB_TOKEN-only fallback (rc=$rc note_count=$note_count call_count=$call_count out=[$out] err=[$(cat "$WORK/gh-checks-h.err")])"
fi
install_fake_gh

print_summary "pr-watch.sh"
