#!/usr/bin/env bash
# board.test.sh — unit tests for scripts/dev/board/{board,release-prs}.sh
# against a FAKE gh/sleep/git on PATH (no network, no real GitHub calls).
#
# Fixture shapes below follow the JSON shapes documented in gh's own manual
# for `gh issue view/list --json ...` and `gh pr view/list --json ...`. Every
# issue/PR number, title, and org/repo name below is invented for this test
# (no real content, no PII).
#
# Run: bash scripts/dev/board/tests/board.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
BOARD="$BOARD_DIR/board.sh"
RELEASE_PRS="$BOARD_DIR/release-prs.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
export FAKE_GH_LOG="$WORK/gh.log"
: > "$FAKE_GH_LOG"

# Every mutant below is a `sed`-patched COPY of board.sh dropped directly
# into $WORK (never back into scripts/dev/board/) — it sources gh-checks.sh
# and lib.sh via SCRIPT_DIR="$(dirname "$0")", so copies of both (plus
# lib.sh's own lanes-config.sh) must sit next to it in $WORK too, or the
# mutant fails at source-time before any of the logic under test ever runs
# (a false PASS: the assertions below only check the mutated output differs
# from the original, which a source-time crash also satisfies, for the wrong
# reason).
cp "$BOARD_DIR/gh-checks.sh" "$WORK/gh-checks.sh"
cp "$BOARD_DIR/lib.sh" "$WORK/lib.sh"
cp "$BOARD_DIR/lanes-config.sh" "$WORK/lanes-config.sh"

# A disposable config fixture — tests must not depend on this repo's real
# .claude/agent-lanes.json. LANES_REPO_ROOT is also pinned explicitly: a
# mutant's lib.sh (copied into $WORK above) would otherwise derive it from
# $WORK, not this repo, breaking anything that shells back out to git.
LANES_FIXTURE="$WORK/agent-lanes.json"
cat > "$LANES_FIXTURE" <<'JSON'
{
  "namePrefix": "C",
  "defaultBranch": "main",
  "worktreeDir": ".worktrees",
  "boardTitle": "Agent Work Board",
  "prd": { "glob": "prd/[0-9]*.md", "frPattern": "FR-?[0-9]+", "idField": "prd_id" },
  "deploy": { "boundPaths": ["src/", "Dockerfile", "docker-compose", "supabase/migrations/"] }
}
JSON
export LANES_CONFIG="$LANES_FIXTURE"
export LANES_REPO_ROOT="$REPO_ROOT"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fake gh — dispatches on (subcommand, --json value), content from env vars
# set per-test. Every invocation is logged to $FAKE_GH_LOG for call/arg
# assertions.
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

# FAKE_FAIL_AFTER_RELEASE_MARKER (optional): once a `release:`-body
# comment is posted (see the `comment` case below, which touches this
# file), EVERY subsequent gh call fails — the judge's exact P1
# reproduction ("fake gh failing every call after the release comment").
# Checked before dispatch so the release-comment call itself succeeds.
if [ -n "${FAKE_FAIL_AFTER_RELEASE_MARKER:-}" ] && [ -f "$FAKE_FAIL_AFTER_RELEASE_MARKER" ]; then
  echo "fake gh: forced failure (fail-after-release marker set): $*" >&2
  exit 1
fi

jq_filter=""
json_arg=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--jq" ]; then jq_filter="$a"; fi
  if [ "$prev" = "--json" ]; then json_arg="$a"; fi
  prev="$a"
done

emit() {
  if [ -n "$jq_filter" ]; then
    printf '%s' "$1" | jq -r "$jq_filter"
  else
    printf '%s' "$1"
  fi
}

labels_default='{"labels":[]}'
comments_default='{"comments":[]}'
# "${VAR:-{}}" is NOT safe: bash's ${...} parser closes at the first
# unescaped '}', so it silently corrupts to VALUE+stray-'}' whenever VAR IS
# set (only looks right by coincidence when VAR is unset) — route the empty
# default through a plain variable instead.
empty_json_default='{}'

sub1="${1:-}"; sub2="${2:-}"

case "$sub1" in
  label)
    case "$sub2" in
      list) emit "${FAKE_LABEL_LIST_JSON:-[]}" ;;
      create) exit 0 ;;
      *) echo "fake gh: unhandled label $sub2" >&2; exit 1 ;;
    esac
    ;;
  issue)
    case "$sub2" in
      list) emit "${FAKE_ISSUE_LIST_JSON:-[]}" ;;
      view)
        case "$json_arg" in
          *comments*)
            # FAKE_COMMENTS_STATE (optional): a file tracking comments posted
            # by THIS fake within a single test, so a multi-step flow like
            # `reclaim` (which posts a comment, then re-reads comments inside
            # cmd_claim's own race check) sees its own writes — a static var
            # can't represent "the second read differs from the first".
            # Seeded from FAKE_ISSUE_VIEW_COMMENTS_JSON on first write; reads
            # before any write fall back to that same static fixture.
            if [ -n "${FAKE_COMMENTS_STATE:-}" ] && [ -f "$FAKE_COMMENTS_STATE" ]; then
              cat "$FAKE_COMMENTS_STATE"
            else
              emit "${FAKE_ISSUE_VIEW_COMMENTS_JSON:-$comments_default}"
            fi
            ;;
          # "labels,state" / "title,labels,state" (checkout, reclaim's meta
          # read) uses a DIFFERENT fixture than the bare "labels" re-read
          # cmd_claim makes on its own, so a test can simulate a label having
          # already changed between the two reads. Falls back to
          # FAKE_ISSUE_VIEW_LABELS_JSON when unset, so existing bare-"labels"
          # callers (e.g. checkout tests) are unaffected.
          #
          # FAKE_ISSUE_META_DIR (optional): per-ISSUE-NUMBER override
          # ($3 is the issue number: `issue view <N> --json labels,state`),
          # so a test with TWO candidate issues can make just ONE of them
          # carry a label (e.g. wip-keep) that only shows up at RECLAIM
          # time — simulating a real "state changed between the `next`
          # snapshot and the live reclaim re-check" race.
          *labels*state*)
            if [ -n "${FAKE_ISSUE_META_DIR:-}" ] && [ -f "${FAKE_ISSUE_META_DIR}/${3:-}.json" ]; then
              cat "${FAKE_ISSUE_META_DIR}/${3:-}.json"
            else
              emit "${FAKE_ISSUE_VIEW_META_JSON:-${FAKE_ISSUE_VIEW_LABELS_JSON:-$labels_default}}"
            fi
            ;;
          *labels*) emit "${FAKE_ISSUE_VIEW_LABELS_JSON:-$labels_default}" ;;
          *) emit "${FAKE_ISSUE_VIEW_JSON:-$empty_json_default}" ;;
        esac
        ;;
      edit) exit 0 ;;
      comment)
        body="" prevarg=""
        for a in "$@"; do
          if [ "$prevarg" = "--body" ]; then body="$a"; fi
          prevarg="$a"
        done
        if [ -n "${FAKE_COMMENTS_STATE:-}" ]; then
          base="${FAKE_ISSUE_VIEW_COMMENTS_JSON:-$comments_default}"
          [ -f "$FAKE_COMMENTS_STATE" ] && base="$(cat "$FAKE_COMMENTS_STATE")"
          new_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf '%s' "$base" | jq -c --arg b "$body" --arg t "$new_ts" \
            '.comments += [{"body":$b,"createdAt":$t}]' > "$FAKE_COMMENTS_STATE"
        fi
        # See the fail-after-release-marker check at the top of this
        # script: a `release:`-body comment flips the switch AFTER it
        # succeeds, so every gh call from this point on fails.
        if [ -n "${FAKE_FAIL_AFTER_RELEASE_MARKER:-}" ]; then
          case "$body" in
            release:*) touch "$FAKE_FAIL_AFTER_RELEASE_MARKER" ;;
          esac
        fi
        exit 0
        ;;
      create) printf '%s\n' "${FAKE_ISSUE_CREATE_URL:-https://github.com/example-org/example-repo/issues/999}" ;;
      *) echo "fake gh: unhandled issue $sub2" >&2; exit 1 ;;
    esac
    ;;
  pr)
    case "$sub2" in
      list)
        if [ "${FAKE_PR_LIST_FAIL:-0}" = "1" ]; then
          echo "fake gh: pr list forced failure" >&2
          exit 1
        fi
        # FAKE_PR_LIST_FAIL_ON_CALL (optional, with FAKE_PR_LIST_COUNTER): a
        # 1-indexed call counter across ALL `gh pr list` invocations in this
        # process — fails ONLY the Nth call, so a test can simulate one
        # specific lookup (e.g. reclaim's own re-verification, distinct
        # from `next`'s earlier, cached candidate-selection pass) going
        # transiently bad while every other call succeeds normally.
        if [ -n "${FAKE_PR_LIST_FAIL_ON_CALL:-}" ]; then
          cnt_file="${FAKE_PR_LIST_COUNTER:-/tmp/fake-pr-list-counter.$$}"
          n=0
          [ -f "$cnt_file" ] && n="$(cat "$cnt_file")"
          n=$((n + 1))
          printf '%s' "$n" > "$cnt_file"
          if [ "$n" = "$FAKE_PR_LIST_FAIL_ON_CALL" ]; then
            echo "fake gh: pr list forced failure (call #$n)" >&2
            exit 1
          fi
        fi
        emit "${FAKE_PR_LIST_JSON:-[]}"
        ;;
      view) emit "${FAKE_PR_VIEW_JSON:-$empty_json_default}" ;;
      edit) exit 0 ;;
      comment) exit 0 ;;
      update-branch) exit 0 ;;
      *) echo "fake gh: unhandled pr $sub2" >&2; exit 1 ;;
    esac
    ;;
  api) emit "${FAKE_API_JSON:-$empty_json_default}" ;;
  run)
    case "$sub2" in
      view) printf '%s\n' "${FAKE_RUN_VIEW_LOG:-}" ;;
      *) echo "fake gh: unhandled run $sub2" >&2; exit 1 ;;
    esac
    ;;
  *) echo "fake gh: unhandled subcommand $sub1" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$FAKE_BIN/gh"

# ---------------------------------------------------------------------------
# Fake sleep — instant (avoids the real 3s claim-race window in tests).
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
exit 0
FAKE_SLEEP
chmod +x "$FAKE_BIN/sleep"

# ---------------------------------------------------------------------------
# Fake git — for release-prs.sh.
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  log)
    case "${2:-}" in
      --pretty=%s) printf '%s\n' "${FAKE_GIT_LOG_SUBJECTS:-}" ;;
      *) echo "fake git: unhandled log ${2:-}" >&2; exit 1 ;;
    esac
    ;;
  *) echo "fake git: unhandled $*" >&2; exit 1 ;;
esac
FAKE_GIT
chmod +x "$FAKE_BIN/git"

export PATH="$FAKE_BIN:$PATH"

RESET_ENV_COUNTER=0
reset_env() {
  unset FAKE_ISSUE_LIST_JSON FAKE_ISSUE_VIEW_LABELS_JSON FAKE_ISSUE_VIEW_META_JSON \
        FAKE_ISSUE_VIEW_COMMENTS_JSON FAKE_COMMENTS_STATE FAKE_ISSUE_META_DIR \
        FAKE_LABEL_LIST_JSON FAKE_PR_LIST_JSON FAKE_PR_LIST_FAIL FAKE_PR_LIST_FAIL_ON_CALL FAKE_PR_LIST_COUNTER FAKE_PR_VIEW_JSON FAKE_API_JSON \
        FAKE_RUN_VIEW_LOG FAKE_ISSUE_CREATE_URL FAKE_GIT_LOG_SUBJECTS FAKE_FAIL_AFTER_RELEASE_MARKER
  : > "$FAKE_GH_LOG"
  # Real `gh issue view --json comments` reflects every comment this same
  # process just posted — a static fixture that never gains the claimant's
  # own `claim:`/`release:` comment isn't a faithful fake and (correctly,
  # since the race resolver now REQUIRES finding your own claim comment in
  # the read-back — see _claim_race_winner) makes every claim look
  # unverifiable. Default EVERY test to the stateful comments fake, seeded
  # from FAKE_ISSUE_VIEW_COMMENTS_JSON on first write; a test that wants a
  # SPECIFIC shared file (e.g. to hand-craft a race) just overrides this
  # after calling reset_env, same as before.
  RESET_ENV_COUNTER=$((RESET_ENV_COUNTER + 1))
  FAKE_COMMENTS_STATE="$WORK/comments-auto-${RESET_ENV_COUNTER}.json"
  export FAKE_COMMENTS_STATE
  rm -f "$FAKE_COMMENTS_STATE"
}

echo ""
echo "=== board.sh / release-prs.sh unit tests ==="

# ===========================================================================
# 1. next picks P0 before P1 and oldest first
# ===========================================================================
reset_env
# Deliberately shaped so priority-first vs createdAt-first sorting disagree:
# the OLDEST issue overall (#10) is only P1, so a correct P0-first sort must
# skip it in favor of #12 (the oldest P0) — a date-first sort would wrongly
# pick #10. This is what makes the mutation check below meaningful.
export FAKE_ISSUE_LIST_JSON='[
  {"number":10,"title":"oldest overall but only P1","labels":[{"name":"lane:bug"},{"name":"P1"}],"createdAt":"2026-06-01T00:00:00Z","url":"https://example/10"},
  {"number":11,"title":"newer P0","labels":[{"name":"lane:bug"},{"name":"P0"}],"createdAt":"2026-09-01T00:00:00Z","url":"https://example/11"},
  {"number":12,"title":"older P0","labels":[{"name":"lane:bug"},{"name":"P0"}],"createdAt":"2026-07-01T00:00:00Z","url":"https://example/12"},
  {"number":13,"title":"claimed P0 already, oldest of all","labels":[{"name":"lane:bug"},{"name":"P0"},{"name":"agent:OTHER"}],"createdAt":"2026-05-01T00:00:00Z","url":"https://example/13"}
]'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P0"}]}'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[]}'

out="$(bash "$BOARD" next --lane bug --agent AGENT1 2>/dev/null)"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '^#12  older P0$'; then
  pass "next: picks oldest P0 (#12) over newer P0 and older P1"
else
  fail "next: picks oldest P0 (#12) over newer P0 and older P1 (got rc=$rc out=[$out])"
fi

# Mutation check: reversing sort precedence (createdAt before priority)
# must change the pick — proves the ordering assertion is load-bearing.
mutant="$WORK/board.next-mutant.sh"
sed 's/sort_by(\._p, \.createdAt)/sort_by(.createdAt, ._p)/' "$BOARD" > "$mutant"
chmod +x "$mutant"
mut_out="$(bash "$mutant" next --lane bug --agent AGENT1 2>/dev/null)"
if [ -z "$mut_out" ]; then
  fail "next: MUTATION CHECK — mutant produced no output at all (source-time crash?), cannot prove the ordering assertion is sensitive to anything"
elif printf '%s' "$mut_out" | grep -q '^#12  older P0$'; then
  fail "next: MUTATION CHECK — reversing sort precedence should change the pick, but #12 was still chosen (test is not sensitive to ordering)"
else
  pass "next: MUTATION CHECK — reversing sort precedence changes the pick away from #12 (got [$(printf '%s' "$mut_out" | tail -2 | head -1)])"
fi

# ===========================================================================
# 2. claim race: an earlier unreleased claim by another agent wins
# ===========================================================================
reset_env
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"}]}'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[{"body":"claim: OTHER 2000-01-01T00:00:00Z","createdAt":"2000-01-01T00:00:00Z"}]}'
# The race resolver breaks ties by COMMENT ARRAY POSITION, not just the
# timestamp text (see _claim_race_winner) — it locates "my own" just-posted
# claim comment in the re-fetched array to know its index. A real `gh` read
# after `gh issue comment` would show it; the static fixture above would
# not, so this test needs the stateful comments fake (seeded from the
# fixture, appended to by ME's own `claim:`/`claim-lost:` comments).
export FAKE_COMMENTS_STATE="$WORK/comments-42.json"
rm -f "$FAKE_COMMENTS_STATE"

bash "$BOARD" claim 42 ME >/dev/null 2>"$WORK/claim-race.err"
rc=$?
if [ "$rc" = "4" ] && grep -q "claim-lost" "$FAKE_GH_LOG" && grep -q "remove-label agent:ME" "$FAKE_GH_LOG"; then
  pass "claim: loses race to an earlier unreleased claim, exits 4, removes own label"
else
  fail "claim: race-loss path (rc=$rc, log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# Mutation check: disabling the claim-lost exit must make the test's exit-code
# assertion fail — proves it is not vacuous.
mutant="$WORK/board.claim-mutant.sh"
sed 's/exit 4/exit 0/' "$BOARD" > "$mutant"
chmod +x "$mutant"
: > "$FAKE_GH_LOG"
bash "$mutant" claim 42 ME >/dev/null 2>/dev/null
mut_rc=$?
# Assert the SPECIFIC rc the sed mutation produces (0, since it replaced
# `exit 4` with `exit 0`) rather than merely `!= 4` — a source-time crash
# (e.g. a missing gh-checks.sh sibling) would also produce a non-4 rc
# (typically 127 or 2) and would wrongly pass a "not 4" check.
if [ "$mut_rc" = "0" ]; then
  pass "claim: MUTATION CHECK — removing the claim-lost exit changes rc from 4 to 0 (the sed-mutated value), not a crash"
else
  fail "claim: MUTATION CHECK — removing the claim-lost exit should have produced rc=0 (sed replaced 'exit 4' with 'exit 0'), got rc=$mut_rc — either the exit path wasn't reached or the mutant crashed for an unrelated reason"
fi

# ===========================================================================
# 3. claim refuses when another agent:* label already present
# ===========================================================================
reset_env
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"agent:OTHER"}]}'

bash "$BOARD" claim 7 ME >/dev/null 2>"$WORK/claim-refuse.err"
rc=$?
if [ "$rc" = "5" ] && ! grep -q "^issue edit" "$FAKE_GH_LOG"; then
  pass "claim: refuses when another agent:* label is present, exits 5, no mutation attempted"
else
  fail "claim: refuse-on-conflict path (rc=$rc, log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# ===========================================================================
# 4. state swaps exactly one state:*
# ===========================================================================
reset_env
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:backlog"}]}'

: > "$FAKE_GH_LOG"
bash "$BOARD" state 55 implementing >/dev/null 2>"$WORK/state.err"
rc=$?
edit_line="$(grep '^issue edit' "$FAKE_GH_LOG" || true)"
add_count="$(printf '%s' "$edit_line" | grep -o -- '--add-label state:' | wc -l | tr -d ' ')"
remove_count="$(printf '%s' "$edit_line" | grep -o -- '--remove-label state:' | wc -l | tr -d ' ')"
if [ "$rc" = "0" ] && printf '%s' "$edit_line" | grep -q -- '--add-label state:implementing' \
   && printf '%s' "$edit_line" | grep -q -- '--remove-label state:backlog' \
   && [ "$add_count" = "1" ] && [ "$remove_count" = "1" ]; then
  pass "state: swaps state:backlog -> state:implementing in one edit call (exactly one add, one remove)"
else
  fail "state: swap (rc=$rc edit=[$edit_line] add=$add_count remove=$remove_count)"
fi

bash "$BOARD" state 55 not-a-state >/dev/null 2>/dev/null
if [ "$?" != "0" ]; then
  pass "state: rejects an invalid state name"
else
  fail "state: should reject an invalid state name"
fi

# ===========================================================================
# 4a. stale-claim reclaim: `list --stale` and `reclaim` compute claim
# staleness AT READ TIME from (a) the newest issue comment and (b) the
# newest updatedAt of an open PR labeled agent:<NAME> whose body references
# #<issue> — never the issue's own updatedAt. FAIL CLOSED on any lookup
# failure. See scripts/dev/board/board.sh's `_claim_stale_hours` header.
# ===========================================================================
reset_env
STALE_TS="$(date -u -v-25H -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-25 hours -10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
RECENT_TS="$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"

# --- (a) 25h-old claim comment, no PR -> stale; `reclaim` takes it over ---
export FAKE_ISSUE_LIST_JSON='[
  {"number":300,"title":"idle claim","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/300"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'

out="$(bash "$BOARD" list --stale 2>"$WORK/list-stale.err")"
if printf '%s' "$out" | grep -q '#300' && printf '%s' "$out" | grep -Eq 'stale 2[4-9]h'; then
  pass "list --stale: a claim idle 25h with no PR activity is reported stale"
else
  fail "list --stale: comment-only stale detection (out=[$out] err=[$(cat "$WORK/list-stale.err")])"
fi

# `list` (no --stale) still shows the same issue, with the STALE column filled in.
out_all="$(bash "$BOARD" list 2>/dev/null)"
if printf '%s' "$out_all" | grep -q '#300' && printf '%s' "$out_all" | grep -Eq 'stale 2[4-9]h'; then
  pass "list: STALE column shows 'stale <N>h' for #300"
else
  fail "list: STALE column for #300 (out=[$out_all])"
fi

# reclaim re-verifies staleness live, then posts release/claim as one flow:
# release: OLD ... reclaimed-by NEW (ends OLD's claim per the existing
# claim-race resolver), remove-label agent:OLD, then the normal claim path.
export FAKE_ISSUE_VIEW_META_JSON='{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}]}'
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"}]}'
# Stateful comments: reclaim's own `_claim_stale_hours` re-check reads
# comments BEFORE posting the release comment (must still see it as stale);
# cmd_claim's internal race check reads comments AFTER (must see the release
# it just posted, or it would wrongly lose the race to OTHER's old claim).
export FAKE_COMMENTS_STATE="$WORK/comments-300.json"
rm -f "$FAKE_COMMENTS_STATE"
: > "$FAKE_GH_LOG"
out="$(bash "$BOARD" reclaim 300 NEW 2>"$WORK/reclaim.err")"
rc=$?
if [ "$rc" = "0" ] \
   && grep -q "release: OTHER" "$FAKE_GH_LOG" && grep -q "reclaimed-by NEW" "$FAKE_GH_LOG" \
   && grep -q -- "remove-label agent:OTHER" "$FAKE_GH_LOG" \
   && grep -q -- "add-label agent:NEW" "$FAKE_GH_LOG" \
   && grep -q "claim: NEW" "$FAKE_GH_LOG"; then
  pass "reclaim: re-verifies staleness live, posts release/claim comment pair, swaps the agent:* label"
else
  fail "reclaim: takeover flow (rc=$rc out=[$out] err=[$(cat "$WORK/reclaim.err")] log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# MUTATION CHECK: replacing the PR-lookup fail-closed block with the
# tempting-looking "just default to no PR data on failure" (`|| prs='[]'`)
# must make a stale-check that should be SKIPPED instead silently compute a
# bogus staleness from the stale comment data alone — proving the
# fail-closed guard is load-bearing, not decorative. A plain
# `s/return 1/return 0/` does NOT exercise this: `return` unconditionally
# exits the function regardless of its argument, so that swap only changes
# the caller's exit code, not whether staleness gets computed at all — a
# python3 multi-line replacement removes the guard for real. Exercised via
# the gh-pr-list-failure case further below, against a mutant of THIS
# board.sh (never the real file).
STALE_MUTANT="$WORK/board.stale-mutant.sh"
python3 - "$BOARD" "$STALE_MUTANT" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
old = (
    '    prs="$(gh pr list --state open --label "agent:${agent}" --json number,updatedAt,body,isDraft --limit 100 2>&1)" || {\n'
    '      echo "stale-check SKIPPED #${num}: gh pr list --label agent:${agent} failed: ${prs}" >&2\n'
    '      return 1 # fail-closed: pr lookup failed\n'
    '    }\n'
)
new = (
    "    prs=\"$(gh pr list --state open --label \"agent:${agent}\" --json number,updatedAt,body,isDraft --limit 100 2>&1)\""
    " || prs='[]' # MUTATED: fail-closed removed, silently treats a failed lookup as \"no PR data\"\n"
)
count = text.count(old)
if count != 1:
    sys.stderr.write(f"expected exactly 1 occurrence of the fail-closed block, found {count}\n")
    sys.exit(1)
open(dst, "w").write(text.replace(old, new))
PY
mutant_gen_rc=$?
chmod +x "$STALE_MUTANT" 2>/dev/null || true
if [ "$mutant_gen_rc" = "0" ] && ! diff -q "$BOARD" "$STALE_MUTANT" >/dev/null 2>&1; then
  pass "stale-check MUTATION CHECK setup: mutant differs from board.sh (fail-closed block found and replaced)"
else
  fail "stale-check MUTATION CHECK setup: could not locate/replace the pr-lookup fail-closed block — assertion below proves nothing (rc=$mutant_gen_rc)"
fi

# --- (b) an open PR referencing the issue, updated recently, overrides an
# old claim comment: the claim is NOT stale. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":301,"title":"active via PR","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/301"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON="[{\"number\":9001,\"updatedAt\":\"${RECENT_TS}\",\"body\":\"Fixes #301\"}]"

out="$(bash "$BOARD" list --stale 2>/dev/null)"
if ! printf '%s' "$out" | grep -q '#301'; then
  pass "list --stale: an open PR touching #301 updated 1h ago keeps the claim non-stale (overrides the 25h-old comment)"
else
  fail "list --stale: PR activity should have kept #301 out of --stale (out=[$out])"
fi

out_all="$(bash "$BOARD" list 2>/dev/null)"
line301="$(printf '%s' "$out_all" | grep '#301' || true)"
if [ -n "$line301" ] && ! printf '%s' "$line301" | grep -q 'stale '; then
  pass "list: #301's STALE column is '-' (recent PR activity, not stale)"
else
  fail "list: expected a non-stale STALE column for #301 (line=[$line301])"
fi

# --- (c) gh pr list failing -> FAIL CLOSED: not stale, SKIPPED on stderr ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":302,"title":"pr lookup fails","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/302"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_FAIL=1

out="$(bash "$BOARD" list --stale 2>"$WORK/skip.err")"
err="$(cat "$WORK/skip.err")"
if ! printf '%s' "$out" | grep -q '#302' && printf '%s' "$err" | grep -q 'stale-check SKIPPED #302:'; then
  pass "list --stale: a failing gh pr list fails closed (not stale) and logs 'stale-check SKIPPED' to stderr"
else
  fail "list --stale: fail-closed on gh pr list failure (out=[$out] err=[$err])"
fi

# Run the SAME scenario against the fail-closed mutant: the return-1 guard
# gone means the (stale) comment timestamp alone now decides staleness, so
# #302 wrongly comes back stale. This is the mutation check for (c).
mut_out="$(bash "$STALE_MUTANT" list --stale 2>/dev/null)"
if printf '%s' "$mut_out" | grep -q '#302'; then
  pass "stale-check MUTATION CHECK — removing the pr-lookup fail-closed guard wrongly reports #302 stale on a failed PR lookup (not vacuous)"
else
  fail "stale-check MUTATION CHECK — mutant should have wrongly reported #302 stale; it did not (out=[$mut_out])"
fi
unset FAKE_PR_LIST_FAIL

# --- (d) wip-keep opts an issue out, even past the TTL ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":303,"title":"kept alive","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"},{"name":"wip-keep"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/303"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'

out="$(bash "$BOARD" list --stale 2>/dev/null)"
if ! printf '%s' "$out" | grep -q '#303'; then
  pass "list --stale: the wip-keep label opts an issue out of reclaim even past ttlHours"
else
  fail "list --stale: wip-keep should have excluded #303 (out=[$out])"
fi

# --- (e) claims.ttlHours: 0 disables the whole check ---
reset_env
ZERO_TTL_CONFIG="$WORK/agent-lanes-zero-ttl.json"
cat > "$ZERO_TTL_CONFIG" <<JSON
{ "namePrefix": "C", "claims": { "ttlHours": 0, "keepLabel": "wip-keep" } }
JSON
export FAKE_ISSUE_LIST_JSON='[
  {"number":304,"title":"ttl disabled","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/304"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'

out="$(LANES_CONFIG="$ZERO_TTL_CONFIG" bash "$BOARD" list --stale 2>/dev/null)"
if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
  pass "list --stale: claims.ttlHours=0 disables the whole check — nothing reported stale"
else
  fail "list --stale: ttlHours=0 should report nothing (out=[$out])"
fi

out_all="$(LANES_CONFIG="$ZERO_TTL_CONFIG" bash "$BOARD" list 2>/dev/null)"
line304="$(printf '%s' "$out_all" | grep '#304' || true)"
if [ -n "$line304" ] && ! printf '%s' "$line304" | grep -q 'stale '; then
  pass "list: claims.ttlHours=0 shows '-' in the STALE column, never 'stale <N>h'"
else
  fail "list: ttlHours=0 STALE column (line=[$line304])"
fi

# ===========================================================================
# 4b. judge findings on PR C: an OPEN, NON-DRAFT PR referencing the issue
# makes the claim LIVE regardless of age (P1); only a DRAFT PR's updatedAt
# counts as ordinary activity; `next` excludes the caller's own claims from
# stale candidates and retries the next one on refusal (P2); PR linkage
# also matches an `/issues/<n>` URL (P2); `list --json` carries staleHours,
# gh pr list is cached per agent within one _claim_stale_map call, and the
# claim-race resolver breaks same-second ties by comment order (P3).
# ===========================================================================
DAY30_TS="$(date -u -v-30H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-30 hours' +%Y-%m-%dT%H:%M:%SZ)"

# --- P1(a): open, non-draft PR referencing the issue -> NOT stale, however
# old the PR or the last comment. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":500,"title":"green PR awaiting merge click","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/500"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON="[{\"number\":9100,\"updatedAt\":\"${DAY30_TS}\",\"isDraft\":false,\"body\":\"Fixes #500\"}]"

out="$(bash "$BOARD" list --stale 2>/dev/null)"
if ! printf '%s' "$out" | grep -q '#500'; then
  pass "P1: an open, non-draft PR referencing #500 keeps the claim live regardless of its 30h age"
else
  fail "P1: non-draft PR should have kept #500 out of --stale (out=[$out])"
fi

# --- P1(b): open DRAFT PR, updated 30h ago, no recent comments -> stale
# (only the DRAFT's age counts, and 30h has passed the 24h default TTL). ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":501,"title":"stale draft","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/501"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON="[{\"number\":9101,\"updatedAt\":\"${DAY30_TS}\",\"isDraft\":true,\"body\":\"Fixes #501\"}]"

out="$(bash "$BOARD" list --stale 2>/dev/null)"
if printf '%s' "$out" | grep -q '#501' && printf '%s' "$out" | grep -Eq 'stale (2[4-9]|3[0-9])h'; then
  pass "P1: an open DRAFT PR's age counts as activity — 30h idle draft is stale"
else
  fail "P1: draft-PR staleness (out=[$out])"
fi

# --- P2: PR linkage also matches an /issues/<n> URL, anchored so #12/12x
# don't collide (a PR body referencing /issues/5011 must NOT keep #501
# alive). ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":501,"title":"url-linked","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/501"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON="[{\"number\":9102,\"updatedAt\":\"${DAY30_TS}\",\"isDraft\":false,\"body\":\"Closes https://github.com/example-org/example-repo/issues/501\"}]"

out="$(bash "$BOARD" list --stale 2>/dev/null)"
if ! printf '%s' "$out" | grep -q '#501'; then
  pass "P2: a PR body referencing an /issues/501 URL (no leading #) also makes the claim live"
else
  fail "P2: /issues/<n> URL linkage (out=[$out])"
fi

export FAKE_PR_LIST_JSON="[{\"number\":9103,\"updatedAt\":\"${DAY30_TS}\",\"isDraft\":false,\"body\":\"See https://github.com/example-org/example-repo/issues/5011 for context\"}]"
out="$(bash "$BOARD" list --stale 2>/dev/null)"
if printf '%s' "$out" | grep -q '#501'; then
  pass "P2: /issues/5011 does NOT collide with #501 — the URL match is right-anchored"
else
  fail "P2: /issues/<n> URL match should be right-anchored, wrongly matched issues/5011 (out=[$out])"
fi

# --- P3: `list --json` carries staleHours instead of computing and
# discarding it. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":502,"title":"json stale hours","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/502"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'

out_json="$(bash "$BOARD" list --json 2>/dev/null)"
sh_val="$(printf '%s' "$out_json" | jq -r '.[] | select(.number==502) | .staleHours')"
if [ "$sh_val" != "null" ] && [ -n "$sh_val" ] && [ "$sh_val" -ge 24 ] 2>/dev/null; then
  pass "list --json: carries staleHours ($sh_val) instead of discarding the computed stale map"
else
  fail "list --json: expected numeric staleHours >= 24, got '$sh_val' (out=[$out_json])"
fi

# --- P3: gh pr list is cached PER AGENT within one _claim_stale_map call —
# two stale issues held by the SAME agent should cost exactly one
# `pr list --label agent:SAME` call, not two. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":510,"title":"same agent A","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:SAME"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/510"},
  {"number":511,"title":"same agent B","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:SAME"}],"createdAt":"2026-01-02T00:00:00Z","url":"https://example/511"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: SAME ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
: > "$FAKE_GH_LOG"

out="$(bash "$BOARD" list --stale 2>/dev/null)"
pr_list_calls="$(grep -c '^pr list --state open --label agent:SAME' "$FAKE_GH_LOG" || true)"
if printf '%s' "$out" | grep -q '#510' && printf '%s' "$out" | grep -q '#511' && [ "$pr_list_calls" = "1" ]; then
  pass "list --stale: gh pr list --label agent:SAME is called once (cached), not once per issue, and both issues are still reported stale"
else
  fail "list --stale: pr-list caching (calls=$pr_list_calls out=[$out])"
fi

# --- P3: _claim_stale_map's per-call `mktemp -d` cache dir is actually
# removed afterward, by the RETURN trap it sets. Point TMPDIR at a
# dedicated, otherwise-empty directory so any leftover `mktemp -d` output
# is unambiguous; the SAME scenario above (two stale issues, one agent)
# guarantees a cache dir gets created and used. ---
CACHE_PROBE_DIR="$WORK/cache-probe-tmp"
mkdir -p "$CACHE_PROBE_DIR"
out="$(TMPDIR="$CACHE_PROBE_DIR" bash "$BOARD" list --stale 2>/dev/null)"
leftover="$(find "$CACHE_PROBE_DIR" -mindepth 1 2>/dev/null)"
if printf '%s' "$out" | grep -q '#510' && [ -z "$leftover" ]; then
  pass "_claim_stale_map: the per-call PR-list cache dir (mktemp -d under TMPDIR) is gone after list --stale"
else
  fail "_claim_stale_map: cache dir not cleaned up (leftover=[$leftover] out=[$out])"
fi

# --- P3: the RETURN trap that cleans that cache dir must disarm itself —
# a bare `trap ... RETURN` is a single global slot, not scoped to the
# function that armed it (confirmed directly: `f(){ trap ... RETURN; };
# g(){ f; }; g` fires the trap AGAIN on g's return, with whatever `f`
# declared local now unbound). Every current call site invokes
# `_claim_stale_map` via `$(...)`, which forks a subshell, so today that
# leakage is confined to a throwaway process and this exact scenario can't
# actually crash `next` — but that's a property of how it's called, not of
# the trap, so this regression test exercises the deepest real call chain
# available (next's full stale-fallback: _claim_stale_map -> cmd_reclaim ->
# cmd_claim -> _claim_race_winner) and asserts it stays clean, in case a
# future direct (non-subshell) call is ever added. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":900,"title":"exercises the full reclaim+claim chain","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OLD"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/900"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OLD ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
export FAKE_ISSUE_VIEW_META_JSON='{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OLD"}]}'
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"}]}'

out="$(bash "$BOARD" next --lane bug --agent NEW 2>"$WORK/trap-persist.err")"
rc=$?
err="$(cat "$WORK/trap-persist.err")"
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '#900' && ! printf '%s' "$err" | grep -qi "unbound variable"; then
  pass "RETURN trap: does not persist past _claim_stale_map — the full reclaim+claim chain afterward succeeds with no unbound-variable errors"
else
  fail "RETURN trap persistence (rc=$rc out=[$out] err=[$err])"
fi

# --- P2: `next` excludes the CALLER's own claim from stale candidates —
# reclaiming your own claim is nonsensical, not a race, and must never even
# be attempted. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":520,"title":"my own stale claim","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:NEW"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/520"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: NEW ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
: > "$FAKE_GH_LOG"

out="$(bash "$BOARD" next --lane bug --agent NEW 2>"$WORK/next-own.err")"
rc=$?
if [ "$rc" = "3" ] && ! grep -q "issue view 520 --json labels,state" "$FAKE_GH_LOG"; then
  pass "next: excludes the caller's own stale claim from candidates — never even attempts to reclaim it"
else
  fail "next: own-claim exclusion (rc=$rc out=[$out] log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# --- P2: wip-keep found only at reclaim time (a race between the `next`
# snapshot and the live re-check) is a "not eligible, nothing written"
# refusal — cmd_reclaim now dies 3 for it, not the generic usage code 2 —
# so `next` RETRIES the next candidate and succeeds on #522. Before this
# fix wip-keep died 2, which `next`'s stricter retry-only-on-3/6 policy
# would have wrongly treated as a hard stop, contradicting this very
# comment block's own claim that wip-keep refusals are retried. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":521,"title":"race: wip-keep only in live meta","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OTHER1"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/521"},
  {"number":522,"title":"genuinely reclaimable","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER2"}],"createdAt":"2026-01-02T00:00:00Z","url":"https://example/522"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER2 ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
export FAKE_ISSUE_META_DIR="$WORK/issue-meta"
mkdir -p "$FAKE_ISSUE_META_DIR"
printf '%s' '{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OTHER1"},{"name":"wip-keep"}]}' > "$FAKE_ISSUE_META_DIR/521.json"
printf '%s' '{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER2"}]}' > "$FAKE_ISSUE_META_DIR/522.json"
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"}]}'
: > "$FAKE_GH_LOG"

out="$(bash "$BOARD" next --lane bug --agent NEW 2>"$WORK/next-retry.err")"
rc=$?
err="$(cat "$WORK/next-retry.err")"
if [ "$rc" = "0" ] && printf '%s' "$err" | grep -q "wip-keep" \
   && printf '%s' "$err" | grep -q "exit 3, not a write failure" \
   && printf '%s' "$out" | grep -q '#522'; then
  pass "next: retries past a wip-keep refusal (exit 3, not eligible) and reclaims #522"
else
  fail "next: wip-keep retry (rc=$rc out=[$out] err=[$err])"
fi

# --- P2: a POST-write failure (the release comment succeeds, but
# completing the claim afterward fails) must exit 7 and PROPAGATE — never
# retried, since retrying would abandon #600 (OLD's claim already
# released) while `next` moved on and looked successful. #601 is a
# perfectly good second candidate that must NEVER be tried. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":600,"title":"release succeeds, claim fails after","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OLD"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/600"},
  {"number":601,"title":"never reached","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OLD2"}],"createdAt":"2026-01-02T00:00:00Z","url":"https://example/601"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OLD ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
export FAKE_ISSUE_VIEW_META_JSON='{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OLD"}]}'
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"}]}'
export FAKE_FAIL_AFTER_RELEASE_MARKER="$WORK/fail-after-release-p2.marker"
rm -f "$FAKE_FAIL_AFTER_RELEASE_MARKER"

out="$(bash "$BOARD" next --lane bug --agent NEW 2>"$WORK/next-postwrite.err")"
rc=$?
err="$(cat "$WORK/next-postwrite.err")"
if [ "$rc" = "7" ] && printf '%s' "$err" | grep -q "OLD's claim is already released" \
   && ! printf '%s' "$out" | grep -q '#601' \
   && ! grep -q "issue view 601 --json labels,state" "$FAKE_GH_LOG"; then
  pass "next: a post-write failure (exit 7) propagates — never retries #601"
else
  fail "next: exit-7 propagation (rc=$rc out=[$out] err=[$err])"
fi
unset FAKE_FAIL_AFTER_RELEASE_MARKER

# --- P2: `next` DOES retry the next candidate on exit 6 (staleness could
# not be verified — refused BEFORE any write). #521's own PR-list lookup
# succeeds during `next`'s candidate-selection pass (so it's offered as a
# candidate) but fails on reclaim's SEPARATE, uncached re-verification —
# call #3 overall (selection queries #521 then #522's agents once each,
# cached; reclaim's re-check is a fresh 3rd call) — simulating exactly the
# kind of transient failure that must fall through to #522, not abort. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":521,"title":"pr lookup flakes on reclaim re-check","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OTHER1"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/521"},
  {"number":522,"title":"genuinely reclaimable","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER2"}],"createdAt":"2026-01-02T00:00:00Z","url":"https://example/522"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OTHER2 ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
export FAKE_PR_LIST_FAIL_ON_CALL=3
export FAKE_PR_LIST_COUNTER="$WORK/pr-list-counter"
rm -f "$FAKE_PR_LIST_COUNTER"
export FAKE_ISSUE_META_DIR="$WORK/issue-meta-6"
mkdir -p "$FAKE_ISSUE_META_DIR"
printf '%s' '{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OTHER1"}]}' > "$FAKE_ISSUE_META_DIR/521.json"
printf '%s' '{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"},{"name":"agent:OTHER2"}]}' > "$FAKE_ISSUE_META_DIR/522.json"
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P2"},{"name":"state:implementing"}]}'
: > "$FAKE_GH_LOG"

out="$(bash "$BOARD" next --lane bug --agent NEW 2>"$WORK/next-retry6.err")"
rc=$?
err="$(cat "$WORK/next-retry6.err")"
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '#522' \
   && printf '%s' "$err" | grep -q "exit 6" \
   && printf '%s' "$err" | grep -q "trying the next candidate"; then
  pass "next: retries the next candidate (#522) on exit 6 — a transient PR-lookup failure at reclaim time, not a real race"
else
  fail "next: exit-6 retry (rc=$rc out=[$out] err=[$err])"
fi
unset FAKE_PR_LIST_FAIL_ON_CALL FAKE_PR_LIST_COUNTER

# --- P1 (judge's exact reproduction): a fake gh that fails every call AFTER
# the release comment (the release comment itself, and everything up to it,
# succeeds) must make `next` exit NON-ZERO and never print "claimed" — not
# silently report success while every write past that point failed. The
# judge reproduced this with `next` printing `claimed: #7 as NEW` and
# exiting 0 while cmd_claim's own gh calls (labels read, add-label, claim
# comment, comments read-back) all failed; feeding the resulting
# empty/failed comments into the OLD race resolver produced an empty
# "winner" that read as a win. ---
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":600,"title":"fails after release comment","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OLD"}],"createdAt":"2026-01-01T00:00:00Z","url":"https://example/600"}
]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON="{\"comments\":[{\"body\":\"claim: OLD ${STALE_TS}\",\"createdAt\":\"${STALE_TS}\"}]}"
export FAKE_PR_LIST_JSON='[]'
# cmd_reclaim's meta fetch (--json labels,state) and cmd_claim's own bare
# "labels" re-check both need real fixtures here — without them they fall
# back to the empty defaults ({"labels":[]}, no "state" key at all), which
# makes cmd_reclaim die at its OWN "is #600 open" precondition check
# BEFORE ever reaching the release comment, and the test would pass for
# the wrong reason (an unrelated early die) without ever exercising the
# gh-fails-after-release path at all.
export FAKE_ISSUE_VIEW_META_JSON='{"state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"},{"name":"agent:OLD"}]}'
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:implementing"}]}'
export FAKE_FAIL_AFTER_RELEASE_MARKER="$WORK/fail-after-release.marker"
rm -f "$FAKE_FAIL_AFTER_RELEASE_MARKER"

out="$(bash "$BOARD" next --lane bug --agent NEW 2>"$WORK/p1-repro.err")"
rc=$?
err="$(cat "$WORK/p1-repro.err")"
if [ "$rc" != "0" ] && ! printf '%s' "$out" | grep -qi "claimed" && ! printf '%s' "$err" | grep -qi "^claimed:"; then
  pass "P1 repro: gh failing after the release comment makes next exit non-zero (rc=$rc) and never print 'claimed'"
else
  fail "P1 repro: expected a non-zero exit and no 'claimed' output (rc=$rc out=[$out] err=[$err])"
fi
unset FAKE_FAIL_AFTER_RELEASE_MARKER

# --- P2: the claim-race resolver must FAIL (not "win") when our own
# just-posted claim comment is not in the comments read-back — a permanent
# absence (comments never gain it, unlike the stateful-fake default used
# everywhere else in this file) must end in claim exiting 4, never
# "claimed". A static, non-stateful FAKE_ISSUE_VIEW_COMMENTS_JSON models
# exactly this: it never reflects what cmd_claim just posted. ---
reset_env
unset FAKE_COMMENTS_STATE
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"}]}'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[]}'

out="$(bash "$BOARD" claim 601 NEW 2>"$WORK/my-idx-null.err")"
rc=$?
err="$(cat "$WORK/my-idx-null.err")"
if [ "$rc" = "4" ] && ! printf '%s' "$out" | grep -qi "claimed" \
   && printf '%s' "$err" | grep -q "could not be verified after a retry"; then
  pass "claim: own claim comment permanently missing from the read-back exits 4 (unverified), never wins"
else
  fail "claim: null my_idx handling (rc=$rc out=[$out] err=[$err])"
fi

# --- P1 (judge's exact reproduction): the resolver treats ONLY `release:`
# as ending a claim, not a lost racer's OWN `claim-lost: NAME to WINNER`
# comment. History: claim A, claim B, claim-lost: B to A, release: A,
# claim C. B never posted a `release:` for itself (only its claim-lost),
# so B's claim looked forever-unreleased and EVERY later claimant —
# including C here — lost to a racer who lost two comments ago. C must
# win: A released, and B's own claim-lost now correctly ends B's claim
# too. ---
reset_env
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"}]}'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[
  {"body":"claim: A 2026-01-01T00:00:00Z"},
  {"body":"claim: B 2026-01-01T00:00:01Z"},
  {"body":"claim-lost: B to A"},
  {"body":"release: A 2026-01-01T00:00:02Z"}
]}'

out="$(bash "$BOARD" claim 700 C 2>"$WORK/claim-lost-chain.err")"
rc=$?
err="$(cat "$WORK/claim-lost-chain.err")"
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "claimed: #700 as C"; then
  pass "claim: sequential A-claims/B-loses/A-releases/C-claims — C wins (claim-lost ends B's claim too)"
else
  fail "claim: claim-lost-as-release chain (rc=$rc out=[$out] err=[$err])"
fi

# --- P1: the unverified-race path posts `release: NAME ts unverified`
# before dying — otherwise D's abandoned claim comment is never released
# either, the exact same class of bug as the claim-lost case above (dying
# silently leaves a claim nothing ever ends). Two checks: (a) D's own run
# actually posts that comment, and (b) given such a comment already exists
# in history, a LATER claimant is not blocked by the abandoned claim it
# refers to. ---
reset_env
unset FAKE_COMMENTS_STATE
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"}]}'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[]}'
: > "$FAKE_GH_LOG"

bash "$BOARD" claim 701 D >/dev/null 2>"$WORK/unverified-release.err"
rc=$?
if [ "$rc" = "4" ] && grep -q -- "--body release: D .* unverified" "$FAKE_GH_LOG"; then
  pass "claim: the unverified path posts 'release: D ... unverified' before dying — the claim doesn't die unreleased"
else
  fail "claim: unverified path should post a release comment (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

reset_env
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"}]}'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[
  {"body":"claim: D 2026-01-01T00:00:00Z"},
  {"body":"release: D 2026-01-01T00:00:01Z unverified"}
]}'

out="$(bash "$BOARD" claim 702 E 2>"$WORK/unverified-then-claim.err")"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "claimed: #702 as E"; then
  pass "claim: a later claimant is not blocked by an unverified-path release already in history"
else
  fail "claim: unverified-release unblocks a later claimant (rc=$rc out=[$out] err=[$(cat "$WORK/unverified-then-claim.err")])"
fi

# --- P3: the claim-race resolver breaks a SAME-SECOND tie by comment ORDER,
# not by comparing the timestamp text (which is identical for both claims
# at second resolution, so a naive `.ts < $myts` sees neither as earlier and
# BOTH would wrongly think they won). BOARD_NOW_ISO freezes `now_iso()` so
# ME's claim is posted with the exact same timestamp text as OTHER's
# pre-existing one; OTHER's is seeded first (array index 0), ME's is
# appended after (index 1) — OTHER must still be found "earlier" and win. ---
reset_env
# now_iso() only honors BOARD_NOW_ISO when BOARD_TEST=1 is ALSO set and the
# value matches the exact ISO8601 shape — never a stray env var in a real
# operator's shell.
export BOARD_TEST=1
export BOARD_NOW_ISO="2026-01-01T00:00:00Z"
export FAKE_ISSUE_VIEW_LABELS_JSON='{"labels":[{"name":"lane:bug"}]}'
export FAKE_LABEL_LIST_JSON='[{"name":"bug"}]'
export FAKE_ISSUE_VIEW_COMMENTS_JSON='{"comments":[{"body":"claim: OTHER 2026-01-01T00:00:00Z"}]}'
export FAKE_COMMENTS_STATE="$WORK/comments-tie.json"
rm -f "$FAKE_COMMENTS_STATE"

bash "$BOARD" claim 900 ME >/dev/null 2>"$WORK/tie.err"
rc=$?
if [ "$rc" = "4" ] && grep -q "claim-lost" "$FAKE_GH_LOG"; then
  pass "claim: a same-second tie (identical timestamp text) is broken by comment ORDER — OTHER posted first (index 0) and wins"
else
  fail "claim: same-second tie-break (rc=$rc err=[$(cat "$WORK/tie.err")] log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi
unset BOARD_NOW_ISO BOARD_TEST

# A malformed BOARD_NOW_ISO, or BOARD_TEST unset, must be ignored — never
# freeze the clock on a bad or accidental value.
reset_env
export BOARD_NOW_ISO="not-a-timestamp"
if out="$(cd "$BOARD_DIR" && BOARD_SH_SOURCED=1 bash -c '. ./lib.sh; now_iso' 2>&1)" \
   && printf '%s' "$out" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  pass "now_iso: a malformed BOARD_NOW_ISO (BOARD_TEST unset) is ignored — real clock used"
else
  fail "now_iso: malformed BOARD_NOW_ISO should fall back to the real clock (out=[$out])"
fi
export BOARD_TEST=1
if out="$(cd "$BOARD_DIR" && BOARD_SH_SOURCED=1 bash -c '. ./lib.sh; now_iso' 2>&1)" \
   && printf '%s' "$out" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  pass "now_iso: a malformed BOARD_NOW_ISO is ignored even with BOARD_TEST=1 (must match the ISO shape too)"
else
  fail "now_iso: malformed BOARD_NOW_ISO with BOARD_TEST=1 should still fall back (out=[$out])"
fi
unset BOARD_NOW_ISO BOARD_TEST

# ===========================================================================
# 5. deploy-queue flags missing Real Proof
# ===========================================================================
reset_env
export FAKE_PR_LIST_JSON='[
  {"number":100,"title":"with proof","mergeCommit":{"oid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"mergedAt":"2026-09-20T00:00:00Z","body":"## Summary\nx\n## Real Proof\nchecked on staging\n"},
  {"number":101,"title":"no proof","mergeCommit":{"oid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"mergedAt":"2026-09-21T00:00:00Z","body":"## Summary\nx\n"}
]'

out="$(bash "$BOARD" deploy-queue --json 2>/dev/null)"
has_true="$(printf '%s' "$out" | jq '[.[] | select(.number==100)][0].hasRealProof')"
has_false="$(printf '%s' "$out" | jq '[.[] | select(.number==101)][0].hasRealProof')"
if [ "$has_true" = "true" ] && [ "$has_false" = "false" ]; then
  pass "deploy-queue: flags PR with '## Real Proof' true, PR without it false"
else
  fail "deploy-queue: real-proof flag (100=$has_true 101=$has_false)"
fi

# ===========================================================================
# 6. render produces HTML containing issue numbers
# ===========================================================================
reset_env
export FAKE_ISSUE_LIST_JSON='[
  {"number":200,"title":"render me","labels":[{"name":"lane:feature"},{"name":"state:backlog"},{"name":"P2"}],"createdAt":"2026-09-01T00:00:00Z","url":"https://example/200"}
]'
out_html="$WORK/board.html"
bash "$BOARD" render --out "$out_html" >/dev/null 2>"$WORK/render.err"
rc=$?
if [ "$rc" = "0" ] && [ -f "$out_html" ] && grep -q '"number":200' "$out_html" \
   && grep -q 'prefers-color-scheme' "$out_html"; then
  pass "render: writes self-contained HTML containing the issue number + dark-mode CSS"
else
  fail "render: rc=$rc file-exists=$([ -f "$out_html" ] && echo yes || echo no)"
fi

# ===========================================================================
# 7. init-labels: reads the "Priority" and "Agent lanes" sections of a
# labels.yml fixture, each stopping at the next "# ----------" marker, and
# dry-runs the create calls in the documented output shape.
# ===========================================================================
reset_env
LABELS_FIXTURE="$WORK/labels.yml"
cat > "$LABELS_FIXTURE" <<'YAML'
# ---------- Type (what kind of change) ----------
- name: bug
  color: "d73a4a"
  description: "Something isn't working"

# ---------- Priority ----------
- name: P0
  color: "b60205"
  description: "Drop everything"

- name: P3
  color: "c5def5"
  description: "Low"

# ---------- Status ----------
- name: status/wip
  color: "ededed"
  description: "Work in progress"

# ---------- Agent lanes ----------
# Read by `scripts/dev/board/board.sh init-labels`.
- name: lane:bug
  color: "d73a4a"
  description: "Bugfix lane"

- name: lane:feature
  color: "0e8a16"
  description: "Feature lane"

# ---------- Area (what part of the codebase) ----------
- name: area:api
  color: "c2e0c6"
  description: "API area"

- name: area:web
  color: "c2e0c6"
  description: "Web area"
YAML

export FAKE_LABEL_LIST_JSON='[{"name":"lane:bug"}]'
out="$(BOARD_LABELS_FILE="$LABELS_FIXTURE" bash "$BOARD" init-labels --dry-run 2>"$WORK/init-labels.err")"
rc=$?
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qF 'exists: lane:bug' \
   && printf '%s' "$out" | grep -qF 'gh label create "lane:feature" --color "0e8a16" --description "Feature lane"' \
   && printf '%s' "$out" | grep -qF 'gh label create "P0" --color "b60205" --description "Drop everything"' \
   && printf '%s' "$out" | grep -qF 'gh label create "P3"' \
   && ! printf '%s' "$out" | grep -q 'status/wip' \
   && ! printf '%s' "$out" | grep -q 'area:api' \
   && ! printf '%s' "$out" | grep -qF '"bug"'; then
  pass "init-labels: reads only the Priority and Agent-lanes sections (not Type/Status/Area), skips an existing label, dry-runs the rest"
else
  fail "init-labels: section scoping (rc=$rc out=[$out] err=[$(cat "$WORK/init-labels.err")])"
fi

# Mutation check: break the section-end guard (never stop at the next marker)
# — the Area label leaks into the output, proving the scoping assertion above
# is load-bearing.
mutant="$WORK/board.init-labels-mutant.sh"
sed 's/\/\^# -+\/ { flush(); on = 0; next }/\/^# -+\/ { flush(); next }/' "$BOARD" > "$mutant"
chmod +x "$mutant"
if ! diff -q "$BOARD" "$mutant" >/dev/null 2>&1; then
  mut_out="$(BOARD_LABELS_FILE="$LABELS_FIXTURE" bash "$mutant" init-labels --dry-run 2>/dev/null)"
  if printf '%s' "$mut_out" | grep -q 'area:api' && printf '%s' "$mut_out" | grep -q 'status/wip'; then
    pass "init-labels: MUTATION CHECK — removing the section-end guard lets the Area section leak in (scoping assertion is load-bearing)"
  else
    fail "init-labels: MUTATION CHECK — removing the section-end guard should have leaked area:api into the output, but it did not"
  fi
else
  fail "init-labels: MUTATION CHECK — the sed mutation did not change board.sh at all (mutant is identical to the original, proves nothing)"
fi

# Missing file -> a clear error, not a silent empty run.
out="$(BOARD_LABELS_FILE="$WORK/does-not-exist.yml" bash "$BOARD" init-labels --dry-run 2>&1)"
rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q 'not found'; then
  pass "init-labels: missing labels file is a clear error, not a silent empty run"
else
  fail "init-labels: missing file (rc=$rc out=[$out])"
fi

# ===========================================================================
# 8. release-prs classifies deploy-bound files (deploy.boundPaths)
# ===========================================================================
reset_env
export FAKE_GIT_LOG_SUBJECTS='feat: add thing (#300)
docs: update readme (#301)'

cat > "$FAKE_BIN/gh" <<'FAKE_GH2'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  case "${3:-}" in
    300) printf '%s' "$FAKE_PR_VIEW_300" ;;
    301) printf '%s' "$FAKE_PR_VIEW_301" ;;
    *) echo "{}" ;;
  esac
  exit 0
fi
echo "fake gh (release-prs mode): unhandled $*" >&2
exit 1
FAKE_GH2
chmod +x "$FAKE_BIN/gh"

export FAKE_PR_VIEW_300='{"number":300,"title":"platform change","mergeCommit":{"oid":"cccccccccccccccccccccccccccccccccccccccc"},"body":"## Real Proof\nran it on staging\n","files":[{"path":"src/tools/x.js"}]}'
export FAKE_PR_VIEW_301='{"number":301,"title":"docs change","mergeCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"body":"## Real Proof\nN/A - docs only\n","files":[{"path":"docs/WORKFLOWS.md"}]}'

out="$(bash "$RELEASE_PRS" abc123 def456 --json 2>"$WORK/release-prs.err")"
bound_300="$(printf '%s' "$out" | jq -r '.[] | select(.number==300) | .deployBound')"
bound_301="$(printf '%s' "$out" | jq -r '.[] | select(.number==301) | .deployBound')"
proof_300="$(printf '%s' "$out" | jq -r '.[] | select(.number==300) | .realProof')"
if [ "$bound_300" = "true" ] && [ "$bound_301" = "false" ] && printf '%s' "$proof_300" | grep -q "ran it on staging"; then
  pass "release-prs.sh: classifies src/ as deploy-bound (per deploy.boundPaths), docs/ as not, extracts Real Proof verbatim"
else
  fail "release-prs.sh: deploy-bound classification (300=$bound_300 301=$bound_301 proof=[$proof_300])"
fi

# A PR with no Real Proof section prints a NO-PROOF line in the text view.
out_text="$(bash "$RELEASE_PRS" abc123 def456 2>/dev/null)"
export FAKE_PR_VIEW_301='{"number":301,"title":"docs change, no proof","mergeCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"body":"## Summary\nno proof section here\n","files":[{"path":"docs/WORKFLOWS.md"}]}'
out_text="$(bash "$RELEASE_PRS" abc123 def456 2>/dev/null)"
if printf '%s' "$out_text" | grep -q "NO-PROOF: body has no ## Real Proof section"; then
  pass "release-prs.sh: a PR with no Real Proof section prints a NO-PROOF line"
else
  fail "release-prs.sh: NO-PROOF line (out=[$out_text])"
fi

# restore the general-purpose fake gh for subsequent tests
cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

jq_filter=""
json_arg=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--jq" ]; then jq_filter="$a"; fi
  if [ "$prev" = "--json" ]; then json_arg="$a"; fi
  prev="$a"
done

emit() {
  if [ -n "$jq_filter" ]; then
    printf '%s' "$1" | jq -r "$jq_filter"
  else
    printf '%s' "$1"
  fi
}

labels_default='{"labels":[]}'
comments_default='{"comments":[]}'
# "${VAR:-{}}" is NOT safe: bash's ${...} parser closes at the first
# unescaped '}', so it silently corrupts to VALUE+stray-'}' whenever VAR IS
# set (only looks right by coincidence when VAR is unset) — route the empty
# default through a plain variable instead.
empty_json_default='{}'

sub1="${1:-}"; sub2="${2:-}"

case "$sub1" in
  label)
    case "$sub2" in
      list) emit "${FAKE_LABEL_LIST_JSON:-[]}" ;;
      create) exit 0 ;;
      *) echo "fake gh: unhandled label $sub2" >&2; exit 1 ;;
    esac
    ;;
  issue)
    case "$sub2" in
      list) emit "${FAKE_ISSUE_LIST_JSON:-[]}" ;;
      view)
        case "$json_arg" in
          *comments*) emit "${FAKE_ISSUE_VIEW_COMMENTS_JSON:-$comments_default}" ;;
          *labels*) emit "${FAKE_ISSUE_VIEW_LABELS_JSON:-$labels_default}" ;;
          *) emit "${FAKE_ISSUE_VIEW_JSON:-$empty_json_default}" ;;
        esac
        ;;
      edit) exit 0 ;;
      comment) exit 0 ;;
      create) printf '%s\n' "${FAKE_ISSUE_CREATE_URL:-https://github.com/example-org/example-repo/issues/999}" ;;
      *) echo "fake gh: unhandled issue $sub2" >&2; exit 1 ;;
    esac
    ;;
  pr)
    case "$sub2" in
      list) emit "${FAKE_PR_LIST_JSON:-[]}" ;;
      view) emit "${FAKE_PR_VIEW_JSON:-$empty_json_default}" ;;
      edit) exit 0 ;;
      comment) exit 0 ;;
      update-branch) exit 0 ;;
      *) echo "fake gh: unhandled pr $sub2" >&2; exit 1 ;;
    esac
    ;;
  api) emit "${FAKE_API_JSON:-$empty_json_default}" ;;
  run)
    case "$sub2" in
      view) printf '%s\n' "${FAKE_RUN_VIEW_LOG:-}" ;;
      *) echo "fake gh: unhandled run $sub2" >&2; exit 1 ;;
    esac
    ;;
  *) echo "fake gh: unhandled subcommand $sub1" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$FAKE_BIN/gh"

# ===========================================================================
# 9. prd-scan: FR1 tracked by an issue -> only FR2/FR3 reported
# ===========================================================================
reset_env
prd_fixture="$WORK/PRD-fixture.md"
cat > "$prd_fixture" <<'PRDEOF'
---
title: Fixture feature
prd_id: PRD-fixture
status: draft
---

# PRD: Fixture feature

### FR1: first requirement
Some text.

### FR2: second requirement
Some text.

**FR3** third requirement, bolded id form.
PRDEOF

export FAKE_LABEL_LIST_JSON='[]'
# The fake gh below returns a hit ONLY when the search string contains "FR1".
cat > "$FAKE_BIN/gh" <<'FAKE_GH3'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  full="$*"
  if printf '%s' "$full" | grep -q ' FR1]'; then
    echo '[{"number":1,"title":"tracks FR1","url":"https://example/1","state":"OPEN"}]'
  else
    echo '[]'
  fi
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  echo '[]'
  exit 0
fi
echo "fake gh (prd-scan mode): unhandled $*" >&2
exit 1
FAKE_GH3
chmod +x "$FAKE_BIN/gh"

out="$(bash "$BOARD" prd-scan --json --prd "$prd_fixture" 2>"$WORK/prd-scan.err")"
untracked="$(printf '%s' "$out" | jq -r '[.[] | select(.tracked==false) | .fr] | sort | join(",")')"
tracked_frs="$(printf '%s' "$out" | jq -r '[.[] | select(.tracked==true) | .fr] | sort | join(",")')"
if [ "$untracked" = "FR2,FR3" ] && [ "$tracked_frs" = "FR1" ]; then
  pass "prd-scan: FR1 (tracked by an issue) excluded, FR2/FR3 reported as untracked candidates"
else
  fail "prd-scan: tracked-FR exclusion (untracked=[$untracked] tracked=[$tracked_frs])"
fi

# ===========================================================================
# 10. file-feature refuses a duplicate token
# ===========================================================================
reset_env
cat > "$FAKE_BIN/gh" <<'FAKE_GH4'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  echo '[{"number":55,"title":"already tracks this","url":"https://example/55","state":"OPEN"}]'
  exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "create" ]; then
  echo "SHOULD NOT BE CALLED" >&2
  exit 1
fi
echo "fake gh (file-feature mode): unhandled $*" >&2
exit 1
FAKE_GH4
chmod +x "$FAKE_BIN/gh"

body_file="$WORK/body.md"
printf 'Body text.\n' > "$body_file"
bash "$BOARD" file-feature --prd "$prd_fixture" --fr FR1 --priority P2 \
  --title "duplicate check" --body-file "$body_file" >/dev/null 2>"$WORK/file-feature.err"
rc=$?
if [ "$rc" = "5" ] && ! grep -q '^issue create' "$FAKE_GH_LOG"; then
  pass "file-feature: refuses a duplicate token (exit 5), never calls issue create"
else
  fail "file-feature: duplicate-token refusal (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# ===========================================================================
# 11. pr-status extracts the failing job name + error line
# ===========================================================================
reset_env
cat > "$FAKE_BIN/gh" <<'FAKE_GH5'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

jq_filter=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--jq" ]; then jq_filter="$a"; fi
  prev="$a"
done
emit() {
  if [ -n "$jq_filter" ]; then printf '%s' "$1" | jq -r "$jq_filter"; else printf '%s' "$1"; fi
}

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  emit "$FAKE_PR_VIEW_JSON"
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  emit '{"behind_by":2}'
  exit 0
fi
if [ "${1:-}" = "run" ] && [ "${2:-}" = "view" ]; then
  printf '%s\n' "$FAKE_RUN_VIEW_LOG"
  exit 0
fi
echo "fake gh (pr-status mode): unhandled $*" >&2
exit 1
FAKE_GH5
chmod +x "$FAKE_BIN/gh"

export FAKE_PR_VIEW_JSON='{"number":900,"isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","reviewDecision":"","baseRefName":"main","headRefOid":"abc123","statusCheckRollup":[
  {"__typename":"CheckRun","conclusion":"SUCCESS","detailsUrl":"https://github.com/x/y/actions/runs/1/job/111","name":"lint","status":"COMPLETED","workflowName":"CI"},
  {"__typename":"CheckRun","conclusion":"FAILURE","detailsUrl":"https://github.com/x/y/actions/runs/1/job/222","name":"unit-tests","status":"COMPLETED","workflowName":"CI"}
]}'
export FAKE_RUN_VIEW_LOG="2026-01-01T00:00:00.0000000Z unit-tests	  running suite...
2026-01-01T00:00:01.0000000Z unit-tests	  Error: assertion failed at foo.test.js:12
2026-01-01T00:00:02.0000000Z unit-tests	  process exited 1"

out="$(bash "$BOARD" pr-status 900 2>"$WORK/pr-status.err")"
if printf '%s' "$out" | grep -q "unit-tests:" && printf '%s' "$out" | grep -q "assertion failed at foo.test.js:12"; then
  pass "pr-status: extracts failing job name (unit-tests) + first matching error log line"
else
  fail "pr-status: failing-job extraction (out=[$out])"
fi

out_json="$(bash "$BOARD" pr-status 900 --json 2>/dev/null)"
behind="$(printf '%s' "$out_json" | jq -r '.behindMain')"
if [ "$behind" = "2" ]; then
  pass "pr-status: --json reports behindMain from the compare API"
else
  fail "pr-status: --json behindMain (got $behind)"
fi

# Restore the general-purpose fake gh (test 11's pr-status block installed
# its own custom one) — tests 12-14 below need --jq filtering + pr edit/
# comment support, which the general template now provides.
cat > "$FAKE_BIN/gh" <<'FAKE_GH6'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

jq_filter=""
json_arg=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--jq" ]; then jq_filter="$a"; fi
  if [ "$prev" = "--json" ]; then json_arg="$a"; fi
  prev="$a"
done

emit() {
  if [ -n "$jq_filter" ]; then
    printf '%s' "$1" | jq -r "$jq_filter"
  else
    printf '%s' "$1"
  fi
}

labels_default='{"labels":[]}'
comments_default='{"comments":[]}'
empty_json_default='{}'

sub1="${1:-}"; sub2="${2:-}"

case "$sub1" in
  label)
    case "$sub2" in
      list) emit "${FAKE_LABEL_LIST_JSON:-[]}" ;;
      create) exit 0 ;;
      *) echo "fake gh: unhandled label $sub2" >&2; exit 1 ;;
    esac
    ;;
  issue)
    case "$sub2" in
      list) emit "${FAKE_ISSUE_LIST_JSON:-[]}" ;;
      view)
        case "$json_arg" in
          *comments*)
            if [ -n "${FAKE_COMMENTS_STATE:-}" ] && [ -f "$FAKE_COMMENTS_STATE" ]; then
              cat "$FAKE_COMMENTS_STATE"
            else
              emit "${FAKE_ISSUE_VIEW_COMMENTS_JSON:-$comments_default}"
            fi
            ;;
          *labels*) emit "${FAKE_ISSUE_VIEW_LABELS_JSON:-$labels_default}" ;;
          *) emit "${FAKE_ISSUE_VIEW_JSON:-$empty_json_default}" ;;
        esac
        ;;
      edit) exit 0 ;;
      comment)
        if [ -n "${FAKE_COMMENTS_STATE:-}" ]; then
          body="" prevarg=""
          for a in "$@"; do
            if [ "$prevarg" = "--body" ]; then body="$a"; fi
            prevarg="$a"
          done
          base="${FAKE_ISSUE_VIEW_COMMENTS_JSON:-$comments_default}"
          [ -f "$FAKE_COMMENTS_STATE" ] && base="$(cat "$FAKE_COMMENTS_STATE")"
          new_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf '%s' "$base" | jq -c --arg b "$body" --arg t "$new_ts" \
            '.comments += [{"body":$b,"createdAt":$t}]' > "$FAKE_COMMENTS_STATE"
        fi
        exit 0
        ;;
      create) printf '%s\n' "${FAKE_ISSUE_CREATE_URL:-https://github.com/example-org/example-repo/issues/999}" ;;
      *) echo "fake gh: unhandled issue $sub2" >&2; exit 1 ;;
    esac
    ;;
  pr)
    case "$sub2" in
      list) emit "${FAKE_PR_LIST_JSON:-[]}" ;;
      view) emit "${FAKE_PR_VIEW_JSON:-$empty_json_default}" ;;
      edit) exit 0 ;;
      comment) exit 0 ;;
      update-branch) exit 0 ;;
      *) echo "fake gh: unhandled pr $sub2" >&2; exit 1 ;;
    esac
    ;;
  api) emit "${FAKE_API_JSON:-$empty_json_default}" ;;
  run)
    case "$sub2" in
      view) printf '%s\n' "${FAKE_RUN_VIEW_LOG:-}" ;;
      *) echo "fake gh: unhandled run $sub2" >&2; exit 1 ;;
    esac
    ;;
  *) echo "fake gh: unhandled subcommand $sub1" >&2; exit 1 ;;
esac
FAKE_GH6
chmod +x "$FAKE_BIN/gh"

# ===========================================================================
# 12. pr-own: refuses when a different agent:* label is already on the PR
# ===========================================================================
reset_env
export FAKE_PR_VIEW_JSON='{"labels":[{"name":"agent:OTHER"}]}'

bash "$BOARD" pr-own 9001 ME >/dev/null 2>"$WORK/pr-own-refuse.err"
rc=$?
if [ "$rc" = "5" ] && ! grep -q '^pr edit' "$FAKE_GH_LOG"; then
  pass "pr-own: refuses when a different agent:* label is already present, exits 5, no edit attempted"
else
  fail "pr-own: refuse-on-conflict path (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# ===========================================================================
# 13. pr-own: succeeds when unclaimed, adds label + posts a comment
# ===========================================================================
reset_env
export FAKE_PR_VIEW_JSON='{"labels":[]}'
export FAKE_LABEL_LIST_JSON='[]'

out="$(bash "$BOARD" pr-own 9002 ME 2>"$WORK/pr-own-ok.err")"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'pr-owned: #9002 as ME' \
   && grep -q -- '--add-label agent:ME' "$FAKE_GH_LOG" && grep -q '^pr comment' "$FAKE_GH_LOG"; then
  pass "pr-own: unclaimed PR -> adds agent:ME label and posts a pr-own comment"
else
  fail "pr-own: accept path (rc=$rc out=[$out] log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# ===========================================================================
# 14. my-prs: lists open PRs carrying the agent label
# ===========================================================================
reset_env
export FAKE_PR_LIST_JSON='[
  {"number":9003,"isDraft":false,"mergeStateStatus":"CLEAN","statusCheckRollup":[{"conclusion":"SUCCESS","status":"COMPLETED"}],"title":"my pr"}
]'
out="$(bash "$BOARD" my-prs ME 2>"$WORK/my-prs.err")"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q '#9003' && printf '%s' "$out" | grep -q 'my pr' \
   && grep -q -- '--label agent:ME' "$FAKE_GH_LOG"; then
  pass "my-prs: lists an open PR carrying agent:ME, filtered via --label"
else
  fail "my-prs: listing (rc=$rc out=[$out] log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# ===========================================================================
# show / comment / checkout — the issue monitor-checkout-update surface.
# `show` and `checkout` end in issue-fetch.sh, which reads BOARD_REPO and one
# `gh api graphql` response (shape: .data.repository.issue{title,state,...}).
# ===========================================================================
ISSUE_GQL='{"data":{"repository":{"issue":{"number":4242,"title":"Widget export silently drops rows","state":"OPEN","url":"https://github.com/example-org/example-repo/issues/4242","author":{"login":"someone"},"createdAt":"2026-01-01T00:00:00Z","labels":{"nodes":[{"name":"lane:bug"}]},"body":"steps to repro","bodyHTML":"<p>steps to repro</p>","comments":{"nodes":[]}}}}}'

reset_env
export BOARD_REPO=example-org/example-repo BOARD_ISSUE_DIR="$WORK/issues" FAKE_API_JSON="$ISSUE_GQL"
out="$(bash "$BOARD" show 4242 2>&1)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "Widget export silently drops rows" && grep -q "^api graphql" "$FAKE_GH_LOG"; then
  pass "show: delegates to issue-fetch.sh and prints the issue"
else
  fail "show: (rc=$rc out=[$(printf '%s' "$out" | head -5 | tr '\n' '|')])"
fi

reset_env
printf 'progress: repro confirmed\n' > "$WORK/note.md"
: > "$FAKE_GH_LOG"
bash "$BOARD" comment 4242 --file "$WORK/note.md" >/dev/null 2>&1; rc=$?
if [ "$rc" = "0" ] && grep -q "^issue comment 4242 --body-file $WORK/note.md" "$FAKE_GH_LOG"; then
  pass "comment: posts the file as the comment body"
else
  fail "comment: post (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi
: > "$FAKE_GH_LOG"
out_bad="$(bash "$BOARD" comment 4242 --file 2>&1)"; rc=$?
if [ "$rc" = "2" ] && ! printf '%s' "$out_bad" | grep -q 'unbound variable' \
   && printf '%s' "$out_bad" | grep -q -- "--file requires a value" \
   && ! grep -q "^issue comment" "$FAKE_GH_LOG"; then
  pass "comment: --file with no value dies cleanly (no \$2: unbound variable), posts nothing"
else
  fail "comment: --file with no value (rc=$rc out=[$out_bad] log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

: > "$WORK/empty.md"; : > "$FAKE_GH_LOG"
bash "$BOARD" comment 4242 --file "$WORK/empty.md" >/dev/null 2>&1; rc=$?
if [ "$rc" != "0" ] && ! grep -q "^issue comment" "$FAKE_GH_LOG"; then
  pass "comment: refuses an empty file, posts nothing"
else
  fail "comment: empty file (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# checkout on an unclaimed backlog issue: claim + state + show.
reset_env
export BOARD_REPO=example-org/example-repo BOARD_ISSUE_DIR="$WORK/issues" FAKE_API_JSON="$ISSUE_GQL"
export FAKE_ISSUE_VIEW_LABELS_JSON='{"title":"Widget export silently drops rows","state":"OPEN","labels":[{"name":"lane:bug"},{"name":"P1"},{"name":"state:backlog"}]}'
: > "$FAKE_GH_LOG"
out="$(bash "$BOARD" checkout 4242 ME 2>&1)"; rc=$?
if [ "$rc" = "0" ] && grep -q -- "^issue edit 4242 --add-label agent:ME" "$FAKE_GH_LOG" \
   && grep -q -- "--add-label state:implementing" "$FAKE_GH_LOG" \
   && printf '%s' "$out" | grep -q "Widget export silently drops rows"; then
  pass "checkout: claims, moves to implementing, then shows the issue"
else
  fail "checkout: fresh (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG") out=[$(printf '%s' "$out" | tail -3 | tr '\n' '|')])"
fi

# checkout again when already ours + implementing: no mutation, says so.
export FAKE_ISSUE_VIEW_LABELS_JSON='{"title":"Widget export silently drops rows","state":"OPEN","labels":[{"name":"lane:bug"},{"name":"agent:ME"},{"name":"state:implementing"}]}'
: > "$FAKE_GH_LOG"
out="$(bash "$BOARD" checkout 4242 ME 2>&1)"; rc=$?
if [ "$rc" = "0" ] && ! grep -q "^issue edit" "$FAKE_GH_LOG" \
   && printf '%s' "$out" | grep -q "claim skipped" && printf '%s' "$out" | grep -q "state change skipped"; then
  pass "checkout: re-run on our own implementing issue mutates nothing and names what it skipped"
else
  fail "checkout: idempotent re-run (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# checkout of a closed issue: refuses, mutates nothing.
export FAKE_ISSUE_VIEW_LABELS_JSON='{"title":"Old","state":"CLOSED","labels":[{"name":"lane:bug"}]}'
: > "$FAKE_GH_LOG"
bash "$BOARD" checkout 4242 ME >/dev/null 2>&1; rc=$?
if [ "$rc" != "0" ] && ! grep -q "^issue edit" "$FAKE_GH_LOG"; then
  pass "checkout: refuses a closed issue without claiming it"
else
  fail "checkout: closed issue (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi

# checkout on an issue another agent holds: claim's exit 5 stops it before state.
export FAKE_ISSUE_VIEW_LABELS_JSON='{"title":"Taken","state":"OPEN","labels":[{"name":"lane:bug"},{"name":"agent:OTHER"},{"name":"state:backlog"}]}'
: > "$FAKE_GH_LOG"
bash "$BOARD" checkout 4242 ME >/dev/null 2>&1; rc=$?
if [ "$rc" = "5" ] && ! grep -q "state:implementing" "$FAKE_GH_LOG"; then
  pass "checkout: stops at claim (exit 5) when another agent holds the issue"
else
  fail "checkout: foreign claim (rc=$rc log=$(tr '\n' '|' < "$FAKE_GH_LOG"))"
fi
unset BOARD_REPO BOARD_ISSUE_DIR FAKE_API_JSON

# ===========================================================================
# checkout --worktree, against a REAL disposable temp git repo (main
# checkout + bare "origin"), the same pattern tests/wt-clean.test.sh builds.
# `BOARD_MAIN_ROOT` overrides board.sh's repo discovery (git -C "$SCRIPT_DIR"
# ... would otherwise always answer about THIS repo, not the disposable one).
# The fake `git` on PATH here only understands `log` (see its definition
# above) — `worktree prune`/`worktree add` are unhandled there, so these
# cases run with a NARROWER PATH: a copy of the fake `gh` (for the
# issue-view/show calls) in front of the REAL system git, never the fake git.
# ===========================================================================
WT_BIN="$WORK/wtbin"
mkdir -p "$WT_BIN"
cp "$FAKE_BIN/gh" "$WT_BIN/gh"
chmod +x "$WT_BIN/gh"
REAL_PATH="$(command -v env >/dev/null 2>&1 && printf '%s' "$PATH" | sed "s#^$FAKE_BIN:##")"
WT_TEST_PATH="$WT_BIN:$REAL_PATH"
rgit() { PATH="$REAL_PATH" command git "$@"; }

export GIT_AUTHOR_NAME="board-test" GIT_AUTHOR_EMAIL="board-test@example.invalid"
export GIT_COMMITTER_NAME="board-test" GIT_COMMITTER_EMAIL="board-test@example.invalid"

WT_SEED="$WORK/wt-seed"
WT_ORIGIN="$WORK/wt-origin.git"
WT_MAIN="$WORK/wt-main"

rgit init -q "$WT_SEED"
rgit -C "$WT_SEED" symbolic-ref HEAD refs/heads/main
echo "seed" > "$WT_SEED/README.md"
rgit -C "$WT_SEED" add README.md
rgit -C "$WT_SEED" commit -q -m seed
rgit clone -q --bare "$WT_SEED" "$WT_ORIGIN"
rgit clone -q "$WT_ORIGIN" "$WT_MAIN"

reset_env
export BOARD_REPO=example-org/example-repo BOARD_ISSUE_DIR="$WORK/issues" FAKE_API_JSON="$ISSUE_GQL" BOARD_MAIN_ROOT="$WT_MAIN"
export FAKE_ISSUE_VIEW_LABELS_JSON='{"title":"Widget export silently drops rows","state":"OPEN","labels":[{"name":"lane:feature"},{"name":"agent:ME"},{"name":"state:implementing"}]}'

# 1. Fresh branch/worktree cut from origin/main.
out="$(PATH="$WT_TEST_PATH" LANES_CONFIG="$LANES_FIXTURE" LANES_REPO_ROOT="$REPO_ROOT" bash "$BOARD" checkout 4242 ME --worktree 2>&1)"; rc=$?
WT_PATH="$(find "$WT_MAIN/.worktrees" -maxdepth 1 -mindepth 1 -name '4242-*' -print -quit 2>/dev/null)"
if [ "$rc" = "0" ] && [ -n "$WT_PATH" ] && [ -d "$WT_PATH" ] \
   && printf '%s' "$out" | grep -qF "checkout: worktree ${WT_PATH} on feat/4242-" \
   && printf '%s' "$out" | grep -qF "(from origin/main)"; then
  pass "checkout --worktree: fresh branch created from origin/main"
else
  fail "checkout --worktree: fresh (rc=$rc wt_path=[$WT_PATH] out=[$out])"
fi
WT_BRANCH="$(rgit -C "$WT_PATH" symbolic-ref --short HEAD 2>/dev/null || true)"

# 2. Remove the worktree the way wt-clean.sh can (worktree gone, branch
#    survives — see wt-clean.sh: `branch -D` only runs when the worktree's
#    HEAD still matches the recorded PR head; it is skipped otherwise, e.g.
#    detached or diverged) — re-running checkout must REUSE the branch, not
#    fail forever on "branch already exists".
rgit -C "$WT_MAIN" worktree remove --force "$WT_PATH"
if rgit -C "$WT_MAIN" show-ref --verify --quiet "refs/heads/${WT_BRANCH}"; then
  pass "checkout --worktree setup: worktree removed, branch ${WT_BRANCH} survives"
else
  fail "checkout --worktree setup: expected branch ${WT_BRANCH} to survive worktree removal"
fi

out2="$(PATH="$WT_TEST_PATH" LANES_CONFIG="$LANES_FIXTURE" LANES_REPO_ROOT="$REPO_ROOT" bash "$BOARD" checkout 4242 ME --worktree 2>&1)"; rc2=$?
if [ "$rc2" = "0" ] && [ -d "$WT_PATH" ] \
   && printf '%s' "$out2" | grep -qF "checkout: worktree ${WT_PATH} reusing existing branch ${WT_BRANCH}"; then
  pass "checkout --worktree: re-run after wt-clean-style removal reuses the existing branch"
else
  fail "checkout --worktree: branch reuse (rc=$rc2 out=[$out2])"
fi

# 3. Existing worktree path -> skipped, no new git mutation.
out3="$(PATH="$WT_TEST_PATH" LANES_CONFIG="$LANES_FIXTURE" LANES_REPO_ROOT="$REPO_ROOT" bash "$BOARD" checkout 4242 ME --worktree 2>&1)"; rc3=$?
if [ "$rc3" = "0" ] && printf '%s' "$out3" | grep -qF "checkout: worktree already exists: ${WT_PATH} — creation skipped"; then
  pass "checkout --worktree: existing worktree path is skipped"
else
  fail "checkout --worktree: existing path skip (rc=$rc3 out=[$out3])"
fi

# 4. Empty/non-ASCII title -> slug falls back to "issue" (never an empty
# path segment or a trailing-hyphen branch name).
export FAKE_ISSUE_VIEW_LABELS_JSON='{"title":"日本語のみ","state":"OPEN","labels":[{"name":"lane:bug"},{"name":"agent:ME"},{"name":"state:implementing"}]}'
out4="$(PATH="$WT_TEST_PATH" LANES_CONFIG="$LANES_FIXTURE" LANES_REPO_ROOT="$REPO_ROOT" bash "$BOARD" checkout 4243 ME --worktree 2>&1)"; rc4=$?
if [ "$rc4" = "0" ] \
   && printf '%s' "$out4" | grep -qF "checkout: worktree ${WT_MAIN}/.worktrees/4243-issue on fix/4243-issue" \
   && [ -d "${WT_MAIN}/.worktrees/4243-issue" ]; then
  pass "checkout --worktree: empty/non-ASCII title falls back to slug 'issue'"
else
  fail "checkout --worktree: slug fallback (rc=$rc4 out=[$out4])"
fi

unset BOARD_REPO BOARD_ISSUE_DIR FAKE_API_JSON BOARD_MAIN_ROOT

print_summary "board.sh / release-prs.sh"
