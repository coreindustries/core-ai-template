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

reset_env() {
  unset FAKE_ISSUE_LIST_JSON FAKE_ISSUE_VIEW_LABELS_JSON FAKE_ISSUE_VIEW_COMMENTS_JSON \
        FAKE_LABEL_LIST_JSON FAKE_PR_LIST_JSON FAKE_PR_VIEW_JSON FAKE_API_JSON \
        FAKE_RUN_VIEW_LOG FAKE_ISSUE_CREATE_URL FAKE_GIT_LOG_SUBJECTS
  : > "$FAKE_GH_LOG"
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
# 7. init-labels: reads the "Agent lanes" section of a labels.yml fixture,
# stopping at the next "# ----------" marker, and dry-runs the create calls
# in the documented output shape.
# ===========================================================================
reset_env
LABELS_FIXTURE="$WORK/labels.yml"
cat > "$LABELS_FIXTURE" <<'YAML'
# ---------- Type (what kind of change) ----------
- name: bug
  color: "d73a4a"
  description: "Something isn't working"

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
   && ! printf '%s' "$out" | grep -q 'area:api' \
   && ! printf '%s' "$out" | grep -qF '"bug"'; then
  pass "init-labels: reads only the Agent-lanes section of labels.yml (stops before Area), skips an existing label, dry-runs the rest"
else
  fail "init-labels: section scoping (rc=$rc out=[$out] err=[$(cat "$WORK/init-labels.err")])"
fi

# Mutation check: break the section-end guard (never stop at the next marker)
# — the Area label leaks into the output, proving the scoping assertion above
# is load-bearing.
mutant="$WORK/board.init-labels-mutant.sh"
sed 's/on && \/\^# -+\/ { if (name != "") print name "|" color "|" desc; exit }/on \&\& 0 { exit }/' "$BOARD" > "$mutant"
chmod +x "$mutant"
if ! diff -q "$BOARD" "$mutant" >/dev/null 2>&1; then
  mut_out="$(BOARD_LABELS_FILE="$LABELS_FIXTURE" bash "$mutant" init-labels --dry-run 2>/dev/null)"
  if printf '%s' "$mut_out" | grep -q 'area:api'; then
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
