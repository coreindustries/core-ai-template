#!/usr/bin/env bash
# issue-watch.test.sh — unit tests for scripts/dev/board/issue-watch.sh
# against a FAKE `gh` on PATH (no network, no real GitHub calls), driven with
# --once and a fresh temp state dir per test case.
#
# REST shapes below follow the documented GitHub Issues API
# (`gh api repos/<owner>/<repo>/issues`):
#   -> [{"number":<n>,"title":"...","state":"open","created_at":"...",
#        "comments":0,"labels":[{"name":"..."}], ...}]  (no pull_request key
#        on a real issue)
#   gh api repos/<owner>/<repo>/issues/<n> --jq '{number,title,state,
#     created_at,comments,labels:[.labels[].name],pull_request}'
#     -> {"number":<n>,"comments":1,"labels":["agent:C-FEATURE-1"],
#         "pull_request":{"diff_url":"...","html_url":"...","merged_at":null,
#                          "patch_url":"...","url":"..."},"state":"open", ...}
# Every fixture below invents its own numbers/titles/logins (no real content,
# no PII).
#
# Run: ./scripts/dev/board/tests/issue-watch.test.sh (direct exec — chmod +x
# is already set; `bash <file>` may trip a worktree guard in this repo).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
WATCH="$BOARD_DIR/issue-watch.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
export FAKE_GH_LOG="$WORK/gh.log"
: > "$FAKE_GH_LOG"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# issue-watch.sh sources lib.sh (and transitively lanes-config.sh) by its own
# dirname — a mutant copied into $WORK needs both sitting next to it too, or
# it fails at source-time before any of the logic under test ever runs. A
# disposable config fixture (excludeLabels empty — equivalent to "no
# exclusions", matching every pre-existing case's assumptions below) keeps
# every case here independent of this repo's real .claude/agent-lanes.json.
cp "$BOARD_DIR/lib.sh" "$WORK/lib.sh"
cp "$BOARD_DIR/lanes-config.sh" "$WORK/lanes-config.sh"
LANES_FIXTURE="$WORK/agent-lanes.json"
cat > "$LANES_FIXTURE" <<'JSON'
{ "intake": { "excludeLabels": [] } }
JSON
export LANES_CONFIG="$LANES_FIXTURE"
export LANES_REPO_ROOT="$REPO_ROOT"

# ---------------------------------------------------------------------------
# Fake gh — dispatches:
#   gh repo view --json nameWithOwner --jq ...   -> "$FAKE_REPO"
#   gh api ... repos/<r>/issues (state=open, no labels filter,
#     sort=created)                              -> "$FAKE_FRESH_TSV" (the
#     --jq already applied server-side by the real gh; here the fake just
#     returns the pre-filtered TSV the real --jq expression would have
#     produced, since re-implementing that jq filter in bash would test the
#     fixture instead of the script's own filtering logic — the FILTERING is
#     exercised by feeding rows that a correct filter would and would not
#     keep, see case 1)
#   gh api ... -f labels=lane:<L> (queue scan)   -> "$FAKE_QUEUE_TSV_<L>"
#   gh api ... -f labels=agent:<A> -f state=all  -> "$FAKE_CLAIMED_TSV_<A>"
#   gh api "repos/<r>/issues/<n>/comments?per_page=1&page=<count>" --jq ..
#     -> "$FAKE_LAST_COMMENTER_<n>"
# Every invocation is logged to $FAKE_GH_LOG.
#
# Because the real filtering (date window, label exclusion, PR exclusion) is
# expressed entirely inside the --jq argument passed to the REAL gh, and this
# fake gh does not run jq at all, tests that need to prove the *filter logic*
# itself (case 1: unlabeled-vs-lane-labeled-vs-operation-lock-vs-PR) instead
# invoke the --jq filter directly against a synthetic JSON array with `jq`,
# matching what issue-watch.sh's own fetch_fresh()/fetch_queue() functions
# literally pass to gh. This is NOT re-testing gh — it is testing the exact
# jq expression shipped in issue-watch.sh, extracted textually from the file
# so drift is impossible.
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  printf '%s' "${FAKE_REPO:-owner/repo}"
  exit 0
fi

if [ "${1:-}" = "api" ]; then
  # Find the path arg (first non-flag arg after "api") and any -f label filter.
  path=""
  label_val=""
  prev=""
  for a in "$@"; do
    if [ "$prev" = "-f" ] && printf '%s' "$a" | grep -q '^labels='; then
      label_val="${a#labels=}"
    fi
    prev="$a"
  done
  for a in "$@"; do
    case "$a" in
      repos/*/issues) path="issues" ;;
      repos/*/issues/*/comments*) path="comments" ;;
      repos/*/issues/*) path="issue" ;;
    esac
  done

  if [ "$path" = "comments" ]; then
    n=""
    for a in "$@"; do
      case "$a" in
        repos/*/issues/*/comments*)
          n="$(printf '%s' "$a" | sed -E 's#.*/issues/([0-9]+)/comments.*#\1#')"
          ;;
      esac
    done
    varname="FAKE_LAST_COMMENTER_${n}"
    val="$(eval "printf '%s' \"\${${varname}:-unknown}\"")"
    printf '%s' "$val"
    exit 0
  fi

  # Individual issue lookup (repos/<r>/issues/<n>) — used by the stale-claim
  # diff to disambiguate "closed" from "unclaimed" when an issue vanishes
  # from the (open-only) claimed scan. FAKE_ISSUE_LOOKUP_<n> is a
  # "state<TAB>labels-csv" pair; FAKE_ISSUE_LOOKUP_<n>_FAIL simulates a
  # failed lookup.
  if [ "$path" = "issue" ]; then
    n=""
    for a in "$@"; do
      case "$a" in
        repos/*/issues/*)
          n="$(printf '%s' "$a" | sed -E 's#.*/issues/([0-9]+)$#\1#')"
          ;;
      esac
    done
    failvar="FAKE_ISSUE_LOOKUP_${n}_FAIL"
    failval="$(eval "printf '%s' \"\${${failvar}:-}\"")"
    if [ -n "$failval" ]; then
      echo "$failval" >&2
      exit 1
    fi
    varname="FAKE_ISSUE_LOOKUP_${n}"
    val="$(eval "printf '%s' \"\${${varname}:-}\"")"
    printf '%s' "$val"
    exit 0
  fi

  if [ "$path" = "issues" ]; then
    if [ -n "$label_val" ]; then
      case "$label_val" in
        lane:*)
          varname="FAKE_QUEUE_TSV_$(printf '%s' "${label_val#lane:}" | tr -c 'A-Za-z0-9' '_')"
          ;;
        agent:*)
          varname="FAKE_CLAIMED_TSV_$(printf '%s' "${label_val#agent:}" | tr -c 'A-Za-z0-9' '_')"
          ;;
        *)
          echo "fake gh: unhandled labels= value: $label_val" >&2
          exit 1
          ;;
      esac
      failvar="${varname}_FAIL"
      failval="$(eval "printf '%s' \"\${${failvar}:-}\"")"
      if [ -n "$failval" ]; then
        echo "$failval" >&2
        exit 1
      fi
      val="$(eval "printf '%s' \"\${${varname}:-}\"")"
      printf '%s' "$val"
      exit 0
    fi
    if [ -n "${FAKE_FRESH_FAIL:-}" ]; then
      echo "$FAKE_FRESH_FAIL" >&2
      exit 1
    fi
    printf '%s' "${FAKE_FRESH_TSV:-}"
    exit 0
  fi

  echo "fake gh: unhandled api call: $*" >&2
  exit 1
fi

echo "fake gh: unhandled subcommand: $*" >&2
exit 1
FAKE_GH
chmod +x "$FAKE_BIN/gh"

export PATH="$FAKE_BIN:$PATH"
export FAKE_REPO="example-org/example-repo"

reset_env() {
  unset FAKE_FRESH_TSV FAKE_FRESH_FAIL
  for v in $(env | grep -o '^FAKE_QUEUE_TSV[A-Za-z0-9_]*' || true); do unset "$v"; done
  for v in $(env | grep -o '^FAKE_CLAIMED_TSV[A-Za-z0-9_]*' || true); do unset "$v"; done
  for v in $(env | grep -o '^FAKE_LAST_COMMENTER[A-Za-z0-9_]*' || true); do unset "$v"; done
  for v in $(env | grep -o '^FAKE_ISSUE_LOOKUP_[A-Za-z0-9_]*' || true); do unset "$v"; done
  : > "$FAKE_GH_LOG"
}

# Fresh temp state dir per case, matching --state-dir DIR (never the default
# path) so cases never see each other's dedup markers.
new_state_dir() {
  local d="$WORK/state-$$-$RANDOM"
  mkdir -p "$d"
  printf '%s' "$d"
}

run_watch() {
  # run_watch <state-dir> <args...> — always --once.
  local sd="$1"; shift
  "$WATCH" --once --state-dir "$sd" "$@"
}

echo ""
echo "=== issue-watch.sh unit tests ==="

# ===========================================================================
# 1. jq filter fidelity — extract the EXACT --jq expression fetch_fresh() and
# fetch_queue() ship, and run it (via the real `jq`, not the fake gh) against
# a synthetic issues array covering every exclusion: unlabeled+fresh (KEEP),
# lane-labeled (DROP, has lane:), operation-lock (DROP), a PR (DROP), and a
# stale issue older than 48h (DROP). Proves the filter logic itself, since
# the fake gh above does not execute jq at all.
# ===========================================================================
FRESH_JQ="$(sed -n "/^fetch_fresh() {/,/^}/p" "$WATCH" | sed -n "s/.*--jq '\\(.*\\)'$/\\1/p")"
# fetch_fresh()'s --jq argument is built in the SOURCE as three concatenated
# bash string literals — '...' "$INTAKE_EXCLUDE_JSON" '...' — so the sed
# extraction above captures the literal, UNEXPANDED text
# '"$INTAKE_EXCLUDE_JSON"' embedded in the middle of the jq program (bash
# does not re-expand a variable reference that appears as plain characters
# inside an already-expanded string). Substitute in an actual JSON array
# literal before handing this to the real `jq` — this test isn't exercising
# the exclude-label config wiring itself (see the dedicated end-to-end case
# near the bottom of this file for that) — it substitutes in ["operation-lock"]
# so the fixture below can still exercise all five filter dimensions
# together (fresh, unlabeled, non-lane, non-excluded, non-PR) the way the
# pre-config-driven version of this script always did. LITERAL_TOKEN is
# built with the dollar sign escaped so bash treats it as literal characters,
# not a variable reference, while constructing the search string.
LITERAL_TOKEN="'\"\$INTAKE_EXCLUDE_JSON\"'"
FRESH_JQ="${FRESH_JQ//$LITERAL_TOKEN/[\"operation-lock\"]}"
if [ -z "$FRESH_JQ" ]; then
  fail "jq filter fidelity: could not extract fetch_fresh()'s --jq expression from issue-watch.sh (test is stale vs. the script)"
else
  now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stale_iso="2020-01-01T00:00:00Z"
  fixture='[
    {"number":1,"pull_request":null,"created_at":"'"$now_iso"'","labels":[]},
    {"number":2,"pull_request":null,"created_at":"'"$now_iso"'","labels":[{"name":"lane:bug"}]},
    {"number":3,"pull_request":null,"created_at":"'"$now_iso"'","labels":[{"name":"operation-lock"}]},
    {"number":4,"pull_request":{"url":"x"},"created_at":"'"$now_iso"'","labels":[]},
    {"number":5,"pull_request":null,"created_at":"'"$stale_iso"'","labels":[]}
  ]'
  kept="$(printf '%s' "$fixture" | jq -r "$FRESH_JQ" 2>"$WORK/fresh-jq.err" | cut -f1)"
  if [ "$kept" = "1" ]; then
    pass "jq filter fidelity: fetch_fresh() keeps only the unlabeled, fresh, non-PR, non-operation-lock issue (#1)"
  else
    fail "jq filter fidelity: fetch_fresh() (kept=[$kept] err=[$(cat "$WORK/fresh-jq.err")])"
  fi
fi

QUEUE_JQ="$(sed -n "/^fetch_queue() {/,/^}/p" "$WATCH" | sed -n "s/.*--jq '\\(.*\\)'$/\\1/p")"
if [ -z "$QUEUE_JQ" ]; then
  fail "jq filter fidelity: could not extract fetch_queue()'s --jq expression from issue-watch.sh (test is stale vs. the script)"
else
  fixture='[
    {"number":10,"pull_request":null,"labels":[{"name":"lane:bug"},{"name":"P0"}]},
    {"number":11,"pull_request":null,"labels":[{"name":"lane:bug"},{"name":"agent:C-BUGFIX-1"}]},
    {"number":12,"pull_request":null,"labels":[{"name":"lane:bug"}]}
  ]'
  out="$(printf '%s' "$fixture" | jq -r "$QUEUE_JQ" 2>"$WORK/queue-jq.err")"
  if printf '%s' "$out" | grep -qF $'10\tP0' && printf '%s' "$out" | grep -qF $'12\t?' \
     && ! printf '%s' "$out" | grep -q '^11'; then
    pass "jq filter fidelity: fetch_queue() drops the agent-labeled issue, extracts P0, defaults missing priority to '?'"
  else
    fail "jq filter fidelity: fetch_queue() (out=[$out] err=[$(cat "$WORK/queue-jq.err")])"
  fi
fi

# ===========================================================================
# 2. Baseline: first pass emits ONLY WATCH-ARMED with correct counts; second
# pass (same state dir, same fixtures) is completely silent.
# ===========================================================================
reset_env
SD="$(new_state_dir)"
export FAKE_FRESH_TSV=$'101\tnone\tSomething operator-filed\n102\tbug,P1\tAlready has a lane label but no lane:*'
export FAKE_QUEUE_TSV_bug=$'201\tP1\tQueued bug'
export FAKE_CLAIMED_TSV_C_TEST=$'301\topen\t0\tagent:C-TEST\tMy claimed issue'

out1="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"; rc1=$?
out2="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"; rc2=$?

if [ "$rc1" = "0" ] && [ "$rc2" = "0" ] \
   && printf '%s' "$out1" | grep -qF "WATCH-ARMED agent=C-TEST lane=bug claimed=1 untriaged=2 queue=1" \
   && [ "$(printf '%s' "$out1" | grep -c .)" = "1" ] \
   && [ -z "$out2" ]; then
  pass "baseline: first pass emits only WATCH-ARMED with correct counts, second pass is silent"
else
  fail "baseline (rc1=$rc1 out1=[$out1] rc2=$rc2 out2=[$out2])"
fi

# ===========================================================================
# 3. NEW-ISSUE: after baseline, a genuinely new unlabeled issue appears ->
# reported once; a third poll with the same issue is silent.
# ===========================================================================
export FAKE_FRESH_TSV=$'101\tnone\tSomething operator-filed\n102\tbug,P1\tAlready has a lane label but no lane:*\n103\tnone\tBrand new phone screenshot bug'
out3="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"
out4="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"

if printf '%s' "$out3" | grep -qF "NEW-ISSUE #103 [no labels] Brand new phone screenshot bug" \
   && [ "$(printf '%s' "$out3" | grep -c '^NEW-ISSUE')" = "1" ] \
   && ! printf '%s' "$out4" | grep -q 'NEW-ISSUE #103'; then
  pass "NEW-ISSUE: a new unlabeled issue is reported once, silent on the next poll"
else
  fail "NEW-ISSUE (out3=[$out3] out4=[$out4])"
fi

# ===========================================================================
# 4. QUEUE-P0: a new unclaimed P0 issue in lane:bug is reported with the
# QUEUE-P0 prefix (not plain QUEUE).
# ===========================================================================
export FAKE_QUEUE_TSV_bug=$'201\tP1\tQueued bug\n202\tP0\tData loss from a phone screenshot'
out5="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"
if printf '%s' "$out5" | grep -qF "QUEUE-P0 #202 P0 Data loss from a phone screenshot" \
   && ! printf '%s' "$out5" | grep -q '^QUEUE #202'; then
  pass "QUEUE-P0: a new P0 unclaimed queue issue uses the QUEUE-P0 prefix"
else
  fail "QUEUE-P0 (out5=[$out5])"
fi

# ===========================================================================
# 5. ISSUE-EVENT: comment count up -> delta + last commenter login.
# ===========================================================================
export FAKE_CLAIMED_TSV_C_TEST=$'301\topen\t3\tagent:C-TEST\tMy claimed issue'
export FAKE_LAST_COMMENTER_301="alice"
out6="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"
if printf '%s' "$out6" | grep -qF "ISSUE-EVENT #301 +3 comment(s) from alice"; then
  pass "ISSUE-EVENT: comment count increase reports the delta and the last commenter's login"
else
  fail "ISSUE-EVENT comments (out6=[$out6])"
fi

# The last-commenter lookup must fetch the Nth comment directly (per_page=1,
# page=<current comment count>) rather than `.[-1]` of gh's default 30-item
# page — the latter is wrong past 30 comments (issue-watch.sh header + P2-3).
if grep -q 'repos/example-org/example-repo/issues/301/comments?per_page=1&page=3' "$FAKE_GH_LOG"; then
  pass "ISSUE-EVENT: last-commenter lookup fetches the Nth comment directly (per_page=1&page=<count>), not .[-1] of the default page"
else
  fail "ISSUE-EVENT last-commenter lookup shape (log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# ===========================================================================
# 6. ISSUE-EVENT: label add/remove.
# ===========================================================================
export FAKE_CLAIMED_TSV_C_TEST=$'301\topen\t3\tagent:C-TEST,needs-info\tMy claimed issue'
out7="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"
if printf '%s' "$out7" | grep -qF "ISSUE-EVENT #301 labels +needs-info"; then
  pass "ISSUE-EVENT: a newly added label is reported as labels +<name>"
else
  fail "ISSUE-EVENT label add (out7=[$out7])"
fi

export FAKE_CLAIMED_TSV_C_TEST=$'301\topen\t3\tagent:C-TEST\tMy claimed issue'
out8="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"
if printf '%s' "$out8" | grep -qF "ISSUE-EVENT #301 labels -needs-info"; then
  pass "ISSUE-EVENT: a removed label is reported as labels -<name>"
else
  fail "ISSUE-EVENT label remove (out8=[$out8])"
fi

# ===========================================================================
# 7. ISSUE-EVENT: close.
# ===========================================================================
export FAKE_CLAIMED_TSV_C_TEST=$'301\tclosed\t3\tagent:C-TEST\tMy claimed issue'
out9="$(run_watch "$SD" --agent C-TEST --lane bug 2>&1)"
if printf '%s' "$out9" | grep -qF "ISSUE-EVENT #301 closed"; then
  pass "ISSUE-EVENT: open -> closed reported as 'closed'"
else
  fail "ISSUE-EVENT close (out9=[$out9])"
fi

# ===========================================================================
# 8. operation-lock and PR items ignored (end-to-end via the fake gh's
# labels-based dispatch is not exercised here directly for the fresh scan
# since the fake doesn't run jq — see case 1's jq-fidelity test for that.
# This case instead proves a PR-labeled agent:<NAME> issue never enters the
# ISSUE-EVENT path at all by asserting fetch_claimed()'s own --jq excludes it
# the same way case 1 did for fetch_fresh()/fetch_queue().)
# ===========================================================================
CLAIMED_JQ="$(sed -n "/^fetch_claimed() {/,/^}/p" "$WATCH" | sed -n "s/.*--jq '\\(.*\\)'$/\\1/p")"
if [ -z "$CLAIMED_JQ" ]; then
  fail "jq filter fidelity: could not extract fetch_claimed()'s --jq expression from issue-watch.sh (test is stale vs. the script)"
else
  fixture='[
    {"number":20,"pull_request":null,"state":"open","comments":0,"labels":[{"name":"agent:C-TEST"}]},
    {"number":21,"pull_request":{"url":"x"},"state":"open","comments":0,"labels":[{"name":"agent:C-TEST"}]}
  ]'
  out="$(printf '%s' "$fixture" | jq -r "$CLAIMED_JQ" 2>"$WORK/claimed-jq.err")"
  if printf '%s' "$out" | grep -q '^20' && ! printf '%s' "$out" | grep -q '^21'; then
    pass "operation-lock/PR exclusion: fetch_claimed()'s jq drops a PR even when agent-labeled"
  else
    fail "operation-lock/PR exclusion (out=[$out] err=[$(cat "$WORK/claimed-jq.err")])"
  fi
fi

# ===========================================================================
# 9. gh failure -> WATCH-ERROR line on STDOUT, exit 0 under --once, and the
# claimed-issue scan (which still succeeds) is unaffected in the same poll.
# ===========================================================================
reset_env
SD2="$(new_state_dir)"
export FAKE_FRESH_FAIL="gh: rate limited"
export FAKE_CLAIMED_TSV_C_TEST2=$'401\topen\t0\tagent:C-TEST2\tSurvives the other scan failing'
out10="$(run_watch "$SD2" --agent C-TEST2 2>&1)"; rc10=$?
if [ "$rc10" = "0" ] && printf '%s' "$out10" | grep -qF "WATCH-ERROR fresh-issue scan failed: gh: rate limited"; then
  pass "gh failure: WATCH-ERROR on stdout, exit 0 under --once"
else
  fail "gh failure (rc10=$rc10 out10=[$out10])"
fi

# A failed scan withholds WATCH-ARMED (partial baseline would drop dedup
# markers for the failed scan and cause false positives later).
if ! printf '%s' "$out10" | grep -q 'WATCH-ARMED'; then
  pass "gh failure during baseline: WATCH-ARMED is withheld until every enabled scan succeeds together"
else
  fail "gh failure should have withheld WATCH-ARMED (out10=[$out10])"
fi

# Once the failing scan recovers, baseline completes on the next poll.
unset FAKE_FRESH_FAIL
export FAKE_FRESH_TSV=""
out11="$(run_watch "$SD2" --agent C-TEST2 2>&1)"; rc11=$?
if [ "$rc11" = "0" ] && printf '%s' "$out11" | grep -qF "WATCH-ARMED agent=C-TEST2 lane=none claimed=1 untriaged=0 queue=0"; then
  pass "gh recovery: baseline completes once the previously-failing scan succeeds"
else
  fail "gh recovery (rc11=$rc11 out11=[$out11])"
fi

# ===========================================================================
# 10. MUTATION CHECK: neutralize the dedup marker check for NEW-ISSUE; the
# same already-reported issue must then be reported AGAIN every poll (proves
# case 3's assertion is actually exercising the dedup guard, not passing by
# luck).
# ===========================================================================
MUTANT="$WORK/issue-watch.dedup-mutant.sh"
sed 's/\[ -e "\$marker" \] && continue/false \&\& continue/' "$WATCH" > "$MUTANT"
chmod +x "$MUTANT"

reset_env
SD3="$(new_state_dir)"
export FAKE_FRESH_TSV=$'501\tnone\tRepeat offender'
export FAKE_CLAIMED_TSV_C_MUT=""
"$MUTANT" --once --state-dir "$SD3" --agent C-MUT >/dev/null 2>&1
mut_out="$("$MUTANT" --once --state-dir "$SD3" --agent C-MUT 2>&1)"
if printf '%s' "$mut_out" | grep -q 'NEW-ISSUE #501'; then
  pass "MUTATION CHECK: disabling the dedup marker check makes NEW-ISSUE re-fire every poll (dedup in case 3 is load-bearing)"
else
  fail "MUTATION CHECK: disabling dedup should have made NEW-ISSUE re-fire, but it didn't (mut_out=[$mut_out])"
fi

# ===========================================================================
# 11. --interval validation: values below 15 seconds are rejected (exit 2);
#     the floor value itself is accepted.
# ===========================================================================
reset_env
SD4="$(new_state_dir)"
out12="$("$WATCH" --agent C-INTERVAL --interval 0 --once --state-dir "$SD4" 2>&1)"; rc12=$?
if [ "$rc12" = "2" ] && printf '%s' "$out12" | grep -q -- "--interval must be at least 15 seconds"; then
  pass "--interval 0: rejected with a clear error, exit 2"
else
  fail "--interval 0 (rc=$rc12 out=[$out12])"
fi

out13="$("$WATCH" --agent C-INTERVAL --interval 14 --once --state-dir "$SD4" 2>&1)"; rc13=$?
if [ "$rc13" = "2" ] && printf '%s' "$out13" | grep -q -- "--interval must be at least 15 seconds"; then
  pass "--interval 14: rejected (below the 15s floor), exit 2"
else
  fail "--interval 14 (rc=$rc13 out=[$out13])"
fi

out14="$("$WATCH" --agent C-INTERVAL --interval 15 --once --state-dir "$SD4" 2>&1)"; rc14=$?
if [ "$rc14" = "0" ]; then
  pass "--interval 15: accepted at the floor"
else
  fail "--interval 15 (rc=$rc14 out=[$out14])"
fi

# ===========================================================================
# 12. ISSUE-EVENT unclaimed: agent:<NAME> removed from a previously-claimed,
#     already-baselined issue -> the individual lookup (fetch_claimed is now
#     open-only, so a vanished issue always needs disambiguating) confirms
#     it's still OPEN, so it's reported as 'unclaimed' once, state file
#     removed so a later reclaim starts a fresh baseline (no spurious diff).
# ===========================================================================
reset_env
SD5="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_UNCLAIM=$'601\topen\t0\tagent:C-UNCLAIM\tGoing to be unclaimed'
out15="$(run_watch "$SD5" --agent C-UNCLAIM 2>&1)"
if printf '%s' "$out15" | grep -qF "WATCH-ARMED agent=C-UNCLAIM lane=none claimed=1 untriaged=0 queue=0" \
   && [ -f "$SD5/issue-601.state" ]; then
  pass "unclaimed setup: baseline armed with issue #601 claimed"
else
  fail "unclaimed setup (out=[$out15])"
fi

export FAKE_CLAIMED_TSV_C_UNCLAIM=""
export FAKE_ISSUE_LOOKUP_601=$'open\tsome-other-label'
out16="$(run_watch "$SD5" --agent C-UNCLAIM 2>&1)"
if printf '%s' "$out16" | grep -qF "ISSUE-EVENT #601 unclaimed (agent:C-UNCLAIM removed)" \
   && [ ! -f "$SD5/issue-601.state" ]; then
  pass "ISSUE-EVENT: agent:<NAME> removed from a claimed issue (still open on lookup) reports 'unclaimed' once and clears its state file"
else
  fail "unclaimed event (out=[$out16] state-exists=$([ -f "$SD5/issue-601.state" ] && echo yes || echo no))"
fi

out17="$(run_watch "$SD5" --agent C-UNCLAIM 2>&1)"
if ! printf '%s' "$out17" | grep -q 'unclaimed'; then
  pass "unclaimed: not re-reported once the state file is already gone"
else
  fail "unclaimed re-fire (out=[$out17])"
fi

# Reclaim starts a fresh baseline silently — no spurious diff against the
# pre-removal state, which is the whole point of deleting the state file.
export FAKE_CLAIMED_TSV_C_UNCLAIM=$'601\topen\t0\tagent:C-UNCLAIM\tReclaimed'
out18="$(run_watch "$SD5" --agent C-UNCLAIM 2>&1)"
if [ -z "$out18" ]; then
  pass "reclaim after unclaimed: silent (fresh baseline for #601, no spurious ISSUE-EVENT)"
else
  fail "reclaim after unclaimed (out=[$out18])"
fi

# ===========================================================================
# 13. ISSUE-EVENT closed via disappearance (P2-A regression coverage):
#     fetch_claimed only ever returns OPEN issues, so once #901 closes it
#     vanishes from claimed_raw exactly the same way an unclaimed issue
#     does (this is also the shape of the >100-lifetime-claims false
#     positive: before this fix, ANY vanish — whether from closing or from
#     falling off an unpaginated state=all page — was reported as
#     'unclaimed', which is wrong when the issue simply closed). The
#     individual lookup must tell the two apart and report 'closed', not
#     'unclaimed'.
# ===========================================================================
reset_env
SD8="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_CLOSE=$'901\topen\t0\tagent:C-CLOSE\tWill close, not get unlabeled'
out21="$(run_watch "$SD8" --agent C-CLOSE 2>&1)"
if printf '%s' "$out21" | grep -qF "WATCH-ARMED agent=C-CLOSE lane=none claimed=1 untriaged=0 queue=0" \
   && [ -f "$SD8/issue-901.state" ]; then
  pass "closed-via-vanish setup: baseline armed with issue #901 claimed"
else
  fail "closed-via-vanish setup (out=[$out21])"
fi

export FAKE_CLAIMED_TSV_C_CLOSE=""
export FAKE_ISSUE_LOOKUP_901=$'closed\tagent:C-CLOSE'
out22="$(run_watch "$SD8" --agent C-CLOSE 2>&1)"
if printf '%s' "$out22" | grep -qF "ISSUE-EVENT #901 closed" \
   && ! printf '%s' "$out22" | grep -q 'unclaimed' \
   && [ ! -f "$SD8/issue-901.state" ]; then
  pass "ISSUE-EVENT: an issue that vanished from the open-only claimed scan and lookup shows closed is reported 'closed', not 'unclaimed'"
else
  fail "closed-via-vanish event (out=[$out22] state-exists=$([ -f "$SD8/issue-901.state" ] && echo yes || echo no))"
fi

# ===========================================================================
# 14. MUTATION CHECK: neutralize the closed/unclaimed branch so it always
# reports 'unclaimed' — case 13's 'closed' event must then flip to
# 'unclaimed', proving the branch (not a hardcoded string) drives the
# outcome.
# ===========================================================================
MUTANT3="$WORK/issue-watch.closed-branch-mutant.sh"
sed 's/if \[ "\$lstate" = "closed" \]; then/if false; then/' "$WATCH" > "$MUTANT3"
chmod +x "$MUTANT3"

reset_env
SD9="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_MUT3=$'902\topen\t0\tagent:C-MUT3\tWill close under the mutant'
"$MUTANT3" --once --state-dir "$SD9" --agent C-MUT3 >/dev/null 2>&1
export FAKE_CLAIMED_TSV_C_MUT3=""
export FAKE_ISSUE_LOOKUP_902=$'closed\tagent:C-MUT3'
mut_out3="$("$MUTANT3" --once --state-dir "$SD9" --agent C-MUT3 2>&1)"
if printf '%s' "$mut_out3" | grep -qF "ISSUE-EVENT #902 unclaimed"; then
  pass "MUTATION CHECK: disabling the closed-branch check misreports a real close as 'unclaimed' (case 13 is load-bearing)"
else
  fail "MUTATION CHECK: disabling the closed-branch check should have misreported 'unclaimed', but it didn't (mut_out3=[$mut_out3])"
fi

# ===========================================================================
# 15. Individual lookup failure: WATCH-ERROR, no closed/unclaimed guess, and
#     the state file is KEPT so the next poll retries instead of asserting
#     an outcome nobody confirmed.
# ===========================================================================
reset_env
SD10="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_LOOKUPFAIL=$'903\topen\t0\tagent:C-LOOKUPFAIL\tLookup will fail on vanish'
out23="$(run_watch "$SD10" --agent C-LOOKUPFAIL 2>&1)"
if printf '%s' "$out23" | grep -qF "WATCH-ARMED agent=C-LOOKUPFAIL lane=none claimed=1 untriaged=0 queue=0" \
   && [ -f "$SD10/issue-903.state" ]; then
  pass "lookup-failure setup: baseline armed with issue #903 claimed"
else
  fail "lookup-failure setup (out=[$out23])"
fi

export FAKE_CLAIMED_TSV_C_LOOKUPFAIL=""
export FAKE_ISSUE_LOOKUP_903_FAIL="gh: simulated lookup failure"
out24="$(run_watch "$SD10" --agent C-LOOKUPFAIL 2>&1)"
if printf '%s' "$out24" | grep -qF "WATCH-ERROR issue #903 lookup failed: gh: simulated lookup failure" \
   && ! printf '%s' "$out24" | grep -qE 'ISSUE-EVENT #903 (closed|unclaimed)' \
   && [ -f "$SD10/issue-903.state" ]; then
  pass "lookup failure: WATCH-ERROR emitted, no closed/unclaimed guess, state file kept for retry"
else
  fail "lookup failure (out=[$out24] state-exists=$([ -f "$SD10/issue-903.state" ] && echo yes || echo no))"
fi

# 15b. A deleted/transferred issue (lookup 404) is reported once as `gone` and
#      its state removed, instead of a WATCH-ERROR on every poll forever.
reset_env
SD11="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_GONE=$'904\topen\t0\tagent:C-GONE\tWill be deleted'
run_watch "$SD11" --agent C-GONE >/dev/null 2>&1
export FAKE_CLAIMED_TSV_C_GONE=""
export FAKE_ISSUE_LOOKUP_904_FAIL="gh: Not Found (HTTP 404)"
out25="$(run_watch "$SD11" --agent C-GONE 2>&1)"
out26="$(run_watch "$SD11" --agent C-GONE 2>&1)"
if printf '%s' "$out25" | grep -qF "ISSUE-EVENT #904 gone" && ! printf '%s' "$out25" | grep -q "WATCH-ERROR" \
   && [ ! -f "$SD11/issue-904.state" ] && [ -z "$out26" ]; then
  pass "lookup 404: reported once as gone, state removed, next poll silent"
else
  fail "lookup 404 (out25=[$out25] out26=[$out26] state-exists=$([ -f "$SD11/issue-904.state" ] && echo yes || echo no))"
fi

# ===========================================================================
# 16. Unclaimed diff must NOT fire when the claimed scan itself fails — a
#     failed gh call must never look like "everything unclaimed".
# ===========================================================================
reset_env
SD6="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_FAIL=$'701\topen\t0\tagent:C-FAIL\tWill hit a gh failure next poll'
out19="$(run_watch "$SD6" --agent C-FAIL 2>&1)"
if printf '%s' "$out19" | grep -qF "WATCH-ARMED agent=C-FAIL lane=none claimed=1 untriaged=0 queue=0"; then
  pass "unclaimed-on-failure setup: baseline armed with issue #701 claimed"
else
  fail "unclaimed-on-failure setup (out=[$out19])"
fi

export FAKE_CLAIMED_TSV_C_FAIL_FAIL="gh: simulated failure"
out20="$(run_watch "$SD6" --agent C-FAIL 2>&1)"
if printf '%s' "$out20" | grep -q "WATCH-ERROR claimed-issue scan failed" \
   && ! printf '%s' "$out20" | grep -q 'unclaimed' \
   && [ -f "$SD6/issue-701.state" ]; then
  pass "unclaimed diff skipped when the claimed scan fails: no false 'unclaimed', state file preserved"
else
  fail "unclaimed diff on failure (out=[$out20] state-exists=$([ -f "$SD6/issue-701.state" ] && echo yes || echo no))"
fi

# ===========================================================================
# 17. MUTATION CHECK: neutralize the vanished-issue detection guard — case
# 12's event must then stop firing, proving that test is exercising real
# logic.
# ===========================================================================
MUTANT2="$WORK/issue-watch.unclaim-mutant.sh"
sed 's/grep -qxF "\$stale_n" "\$current_nums" 2>\/dev\/null \&\& continue/true \&\& continue/' "$WATCH" > "$MUTANT2"
chmod +x "$MUTANT2"

reset_env
SD7="$(new_state_dir)"
export FAKE_FRESH_TSV=""
export FAKE_CLAIMED_TSV_C_MUT2=$'801\topen\t0\tagent:C-MUT2\tWill be unclaimed under the mutant'
"$MUTANT2" --once --state-dir "$SD7" --agent C-MUT2 >/dev/null 2>&1
export FAKE_CLAIMED_TSV_C_MUT2=""
export FAKE_ISSUE_LOOKUP_801=$'open\tsome-other-label'
mut_out2="$("$MUTANT2" --once --state-dir "$SD7" --agent C-MUT2 2>&1)"
if ! printf '%s' "$mut_out2" | grep -q 'unclaimed'; then
  pass "MUTATION CHECK: disabling the vanished-issue guard stops the 'unclaimed' event from firing (case 12 is load-bearing)"
else
  fail "MUTATION CHECK: disabling the vanished-issue guard should have suppressed the event, but it still fired (mut_out2=[$mut_out2])"
fi

# ===========================================================================
# 18. .intake.excludeLabels config wiring: the configured exclude list must
# reach the REAL --jq argument issue-watch.sh hands to `gh api`, end to end —
# not just via a hand-copied re-implementation. A special-purpose fake `gh`
# captures the --jq argument of the fetch_fresh()-shaped call (no `-f
# labels=` filter — that's what tells it apart from fetch_queue()/
# fetch_claimed()'s calls) instead of answering it, then the REAL `jq` runs
# that captured, fully-expanded expression against a synthetic fixture.
# ===========================================================================
CAPTURE_FILE="$WORK/captured-jq.txt"
cat > "$FAKE_BIN/gh" <<'FAKE_GH_CAPTURE'
#!/usr/bin/env bash
set -uo pipefail
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  printf '%s' "${FAKE_REPO:-owner/repo}"
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  has_labels=0
  jqval=""
  prev=""
  for a in "$@"; do
    if [ "$prev" = "-f" ] && printf '%s' "$a" | grep -q '^labels='; then has_labels=1; fi
    if [ "$prev" = "--jq" ]; then jqval="$a"; fi
    prev="$a"
  done
  if [ "$has_labels" = "0" ] && [ -n "$jqval" ]; then
    printf '%s' "$jqval" > "$CAPTURE_FILE"
  fi
  printf ''
  exit 0
fi
echo "fake gh (capture mode): unhandled $*" >&2
exit 1
FAKE_GH_CAPTURE
chmod +x "$FAKE_BIN/gh"
export CAPTURE_FILE

now_iso_18="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fixture18='[
  {"number":1,"pull_request":null,"created_at":"'"$now_iso_18"'","labels":[{"name":"operation-lock"}]},
  {"number":2,"pull_request":null,"created_at":"'"$now_iso_18"'","labels":[]}
]'

EXCLUDE_CONFIG="$WORK/agent-lanes-exclude.json"
cat > "$EXCLUDE_CONFIG" <<'JSON'
{ "intake": { "excludeLabels": ["operation-lock"] } }
JSON
SD_CAP="$(new_state_dir)"
: > "$CAPTURE_FILE"
LANES_CONFIG="$EXCLUDE_CONFIG" LANES_REPO_ROOT="$REPO_ROOT" "$WATCH" --once --state-dir "$SD_CAP" --agent C-CAP >/dev/null 2>&1
captured_jq_excl="$(cat "$CAPTURE_FILE" 2>/dev/null)"
kept_excl="$(printf '%s' "$fixture18" | jq -r "$captured_jq_excl" 2>"$WORK/excl.err" | cut -f1)"
if [ -n "$captured_jq_excl" ] && [ "$kept_excl" = "2" ]; then
  pass "intake.excludeLabels: an operation-lock-labeled issue is excluded end-to-end (config reaches the real --jq argument passed to gh)"
else
  fail "intake.excludeLabels exclusion (captured=[$captured_jq_excl] kept=[$kept_excl] err=[$(cat "$WORK/excl.err")])"
fi

# Control: with excludeLabels empty (the default), the SAME operation-lock-
# labeled issue is NOT excluded — proves the wiring above is load-bearing,
# not coincidental.
: > "$CAPTURE_FILE"
SD_CAP2="$(new_state_dir)"
LANES_CONFIG="$LANES_FIXTURE" LANES_REPO_ROOT="$REPO_ROOT" "$WATCH" --once --state-dir "$SD_CAP2" --agent C-CAP2 >/dev/null 2>&1
captured_jq_default="$(cat "$CAPTURE_FILE" 2>/dev/null)"
kept_default="$(printf '%s' "$fixture18" | jq -r "$captured_jq_default" 2>"$WORK/default.err" | cut -f1 | sort -n | tr '\n' ',')"
if [ -n "$captured_jq_default" ] && printf '%s' "$kept_default" | grep -q '^1,2,$'; then
  pass "intake.excludeLabels: control — with an empty exclude list, the same operation-lock-labeled issue is NOT excluded"
else
  fail "intake.excludeLabels control (captured=[$captured_jq_default] kept=[$kept_default] err=[$(cat "$WORK/default.err")])"
fi

print_summary "issue-watch.sh"
