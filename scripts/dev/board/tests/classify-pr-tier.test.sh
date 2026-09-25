#!/usr/bin/env bash
# classify-pr-tier.test.sh — unit tests for scripts/dev/board/classify-pr-tier.sh
# against a FAKE `gh` on PATH (no network, no real GitHub calls), plus a few
# static checks on .github/workflows/auto-merge.yml's wiring (GH_REPO,
# concurrency group, the Tier-3 --disable-auto step) extracted directly from
# the workflow file so they can't silently drift from what actually ships.
#
# Supersedes the old auto-merge-sensitive-paths.test.sh, which tested an
# inline YAML regex snippet that no longer exists now that classification
# lives in this script instead.
#
# Run: bash scripts/dev/board/tests/classify-pr-tier.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
CLASSIFY="$BOARD_DIR/classify-pr-tier.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/auto-merge.yml"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
export FAKE_GH_LOG="$WORK/gh.log"
: > "$FAKE_GH_LOG"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fake gh — dispatches `gh api --paginate repos/<r>/pulls/<n>/files --jq
# '<expr>'` by running the REAL `--jq` expression classify-pr-tier.sh ships
# (via the real `jq`) against $FAKE_PR_FILES_JSON, so this exercises the
# actual jq program, not a hand-copied re-implementation of it.
# $FAKE_GH_API_FAIL, when set, makes any `api` call fail with that message
# on stderr (simulating a network/API error).
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
: "${FAKE_GH_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

if [ "${1:-}" = "api" ] && [ -n "${FAKE_GH_API_FAIL:-}" ]; then
  echo "$FAKE_GH_API_FAIL" >&2
  exit 1
fi

if [ "${1:-}" = "api" ]; then
  jq_filter=""
  prev=""
  for a in "$@"; do
    [ "$prev" = "--jq" ] && jq_filter="$a"
    prev="$a"
  done
  if [ -z "$jq_filter" ]; then
    echo "fake gh: api call with no --jq filter: $*" >&2
    exit 1
  fi
  # FAKE_PR_FILES_FILE: large fixtures live in a file — Linux caps a single
  # environment variable at 128KB (MAX_ARG_STRLEN), so a big JSON in
  # FAKE_PR_FILES_JSON makes exec fail with 126 before gh even runs.
  files_json() {
    if [ -n "${FAKE_PR_FILES_FILE:-}" ]; then cat "$FAKE_PR_FILES_FILE"; else printf '%s' "${FAKE_PR_FILES_JSON:-[]}"; fi
  }
  case "$*" in
    */files*)
      files_json | jq -r "$jq_filter" ;;
    *)
      # PR metadata (repos/<r>/pulls/<n>): changed_files defaults to the
      # number of listed files, i.e. a consistent PR.
      meta="${FAKE_PR_META_JSON:-$(files_json | jq -c '{changed_files: length}')}"
      printf '%s' "$meta" | jq -r "$jq_filter" ;;
  esac
  exit 0
fi

echo "fake gh: unhandled subcommand: $*" >&2
exit 1
FAKE_GH
chmod +x "$FAKE_BIN/gh"
export PATH="$FAKE_BIN:$PATH"

reset_env() {
  unset FAKE_PR_FILES_JSON FAKE_PR_FILES_FILE FAKE_PR_META_JSON FAKE_GH_API_FAIL PR_TITLE LABELS
  : > "$FAKE_GH_LOG"
}

run_classify() {
  # run_classify <pr-number> — GH_REPO/GH_TOKEN are constant across cases.
  GH_REPO="example-org/example-repo" GH_TOKEN="fake-token" "$CLASSIFY" "$@"
}

echo ""
echo "=== classify-pr-tier.sh unit tests ==="

# ===========================================================================
# 1. A new PRD file -> tier 3, regardless of a feat-shaped title.
# ===========================================================================
reset_env
export PR_TITLE="✨ feat: add a thing"
export FAKE_PR_FILES_JSON='[{"filename":"prd/2026-09-25-example.md"}]'
out="$(run_classify 101 2>"$WORK/case1.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ]; then
  pass "a new PRD file forces tier=3 even with a feat-shaped title"
else
  fail "prd-file-forces-tier-3 (rc=$rc out=[$out] err=[$(cat "$WORK/case1.err")])"
fi

# ===========================================================================
# 2. >100 changed files, the prd/ file arriving LAST — proves the script
# scans the full (paginated) file list rather than being capped at a single
# 100-file page the way `gh pr view --json files` would be.
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: bulk rename"
files_json="$(python3 -c '
import json
files = [{"filename": "src/file-%d.ts" % i} for i in range(120)]
files.append({"filename": "prd/2026-09-25-example.md"})
print(json.dumps(files))
')"
export FAKE_PR_FILES_JSON="$files_json"
out="$(run_classify 102 2>"$WORK/case2.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ]; then
  pass "a prd/ file past the 100th entry still forces tier=3 (pagination, not a single page)"
else
  fail "paginated-prd-file (rc=$rc out=[$out] err=[$(cat "$WORK/case2.err")])"
fi

# ===========================================================================
# 3. A rename OUT of prd/ (current filename is elsewhere, previous_filename
# is under prd/) still forces tier=3 — the GraphQL-backed `gh pr view --json
# files` path this replaced has no previous_filename field at all, so this
# case was invisible before.
# ===========================================================================
reset_env
export PR_TITLE="📝 docs: reorganize"
export FAKE_PR_FILES_JSON='[{"filename":"docs/moved-out-of-prd.md","previous_filename":"prd/2026-09-25-example.md","status":"renamed"}]'
out="$(run_classify 103 2>"$WORK/case3.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ]; then
  pass "a rename OUT of prd/ (previous_filename) still forces tier=3"
else
  fail "rename-out-of-prd (rc=$rc out=[$out] err=[$(cat "$WORK/case3.err")])"
fi

# ===========================================================================
# 4. gh/api failure -> fail CLOSED to tier=3 with a visible warning, never a
# crash and never a silent fall-through to the title-based tier.
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: looks harmless"
export FAKE_GH_API_FAIL="fake network error"
out="$(run_classify 104 2>"$WORK/case4.err")"; rc=$?
err4="$(cat "$WORK/case4.err")"
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ] && printf '%s' "$err4" | grep -q '::warning'; then
  pass "a gh/api failure fails CLOSED to tier=3 with a visible ::warning (never the title-based tier)"
else
  fail "gh-failure-fails-closed (rc=$rc out=[$out] err=[$err4])"
fi

# ===========================================================================
# 5. An ordinary non-prd docs PR still gets its normal tier — the prd/ gate
# must not swallow every other classification.
# ===========================================================================
reset_env
export PR_TITLE="📝 docs: fix a typo in the README"
export FAKE_PR_FILES_JSON='[{"filename":"README.md"}]'
out="$(run_classify 105 2>"$WORK/case5.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=0" ]; then
  pass "a non-prd docs PR still classifies as tier=0"
else
  fail "non-prd-docs-normal-tier (rc=$rc out=[$out] err=[$(cat "$WORK/case5.err")])"
fi

# ===========================================================================
# 6. Missing GH_REPO -> fail closed, not a crash (the exact bug that made
# every PR fail before this script existed: `gh` ran with no checkout and no
# repo context).
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: x"
out="$(GH_TOKEN=fake-token "$CLASSIFY" 106 2>"$WORK/case6.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ] && grep -q 'GH_REPO' "$WORK/case6.err"; then
  pass "a missing GH_REPO fails closed to tier=3 instead of crashing"
else
  fail "missing-gh-repo-fails-closed (rc=$rc out=[$out] err=[$(cat "$WORK/case6.err")])"
fi

# ===========================================================================
# 7. prd/ path FIRST, then >64KB of other paths. Under pipefail,
# `printf | grep -q` returned 141 here (grep exits on the first match, printf
# gets SIGPIPE with >64KB still to write), so the prd/ guard read as "no
# match" and the PR fell through to its title tier (chore -> tier 0).
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: bulk move"
files_json="$(python3 -c '
import json
files = [{"filename": "prd/2026-09-25-example.md"}]
files += [{"filename": "src/some/fairly/long/directory/name/file-%05d.ts" % i} for i in range(2500)]
print(json.dumps(files))
')"
printf '%s' "$files_json" > "$WORK/case7-files.json"
export FAKE_PR_FILES_FILE="$WORK/case7-files.json"
out="$(run_classify 108 2>"$WORK/case7.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ]; then
  pass "a prd/ path followed by >64KB of other paths still forces tier=3 (no SIGPIPE fail-open)"
else
  fail "sigpipe-large-list (rc=$rc out=[$out] err=[$(cat "$WORK/case7.err")])"
fi

# ===========================================================================
# 8. The files endpoint returned fewer paths than the PR's changed_files
# (truncated listing) -> fail closed: an unseen file could be under prd/.
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: x"
export FAKE_PR_FILES_JSON='[{"filename":"README.md"}]'
export FAKE_PR_META_JSON='{"changed_files": 2}'
out="$(run_classify 109 2>"$WORK/case8.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ] && grep -q '::warning' "$WORK/case8.err"; then
  pass "a files listing shorter than changed_files fails closed to tier=3"
else
  fail "truncated-listing-fails-closed (rc=$rc out=[$out] err=[$(cat "$WORK/case8.err")])"
fi

# ===========================================================================
# 9. A PR at the REST files cap (3000) -> fail closed: the endpoint cannot
# list anything past 3000 files, so prd/ could be hiding beyond it.
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: x"
export FAKE_PR_FILES_JSON='[{"filename":"README.md"}]'
export FAKE_PR_META_JSON='{"changed_files": 3000}'
out="$(run_classify 110 2>"$WORK/case9.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ]; then
  pass "a PR at the 3000-file API cap fails closed to tier=3"
else
  fail "files-cap-fails-closed (rc=$rc out=[$out] err=[$(cat "$WORK/case9.err")])"
fi

# ===========================================================================
# 10. A hand-applied needs-review hold forces tier=3: a `labeled` event must
# not re-enable auto-merge on a PR someone deliberately held.
# ===========================================================================
reset_env
export PR_TITLE="🔧 chore: x"
export FAKE_PR_FILES_JSON='[{"filename":"README.md"}]'
export LABELS='["needs-review"]'
out="$(run_classify 111 2>"$WORK/case10.err")"; rc=$?
if [ "$rc" = "0" ] && [ "$out" = "tier=3" ]; then
  pass "a needs-review hold label forces tier=3 on an otherwise tier-0 PR"
else
  fail "needs-review-hold (rc=$rc out=[$out] err=[$(cat "$WORK/case10.err")])"
fi

# ===========================================================================
# MUTATION CHECK: break PRD_SENSITIVE_PATTERN (swap it for a pattern that can
# never match anything real) and confirm case 1 above would then flip to a
# non-3 tier — proving the prd/ assertions are actually exercising the
# pattern, not passing vacuously.
# ===========================================================================
MUTANT="$WORK/classify-pr-tier.mutant.sh"
python3 -c '
import sys
src = open(sys.argv[1]).read()
old = "PRD_SENSITIVE_PATTERN=%s^prd/%s" % ("\x27", "\x27")
new = "PRD_SENSITIVE_PATTERN=%s^THIS-CAN-NEVER-MATCH-ANYTHING/%s" % ("\x27", "\x27")
if old not in src:
    sys.exit(2)
open(sys.argv[2], "w").write(src.replace(old, new))
' "$CLASSIFY" "$MUTANT"
mutant_rc=$?
chmod +x "$MUTANT"

if [ "$mutant_rc" -ne 0 ]; then
  fail "MUTATION CHECK: could not locate PRD_SENSITIVE_PATTERN='^prd/' in classify-pr-tier.sh to mutate (source drifted)"
else
  reset_env
  export PR_TITLE="✨ feat: add a thing"
  export FAKE_PR_FILES_JSON='[{"filename":"prd/2026-09-25-example.md"}]'
  mut_out="$(GH_REPO="example-org/example-repo" GH_TOKEN="fake-token" "$MUTANT" 107 2>/dev/null)"
  if [ "$mut_out" = "tier=3" ]; then
    fail "MUTATION CHECK: breaking PRD_SENSITIVE_PATTERN should have changed the tier away from 3, but it stayed tier=3"
  else
    pass "MUTATION CHECK: breaking PRD_SENSITIVE_PATTERN changes the outcome (prd/ gate is load-bearing, got [$mut_out])"
  fi
fi

echo ""
echo "=== auto-merge.yml wiring (static checks against the real workflow file) ==="

WORKFLOW_TEXT="$(cat "$WORKFLOW")"

if printf '%s' "$WORKFLOW_TEXT" | grep -qE "GH_REPO:\s*\\\$\{\{\s*github\.repository\s*\}\}"; then
  pass "auto-merge.yml sets GH_REPO from github.repository"
else
  fail "auto-merge.yml is missing a GH_REPO: \${{ github.repository }} env entry"
fi

if printf '%s' "$WORKFLOW_TEXT" | grep -q 'concurrency:' \
   && printf '%s' "$WORKFLOW_TEXT" | grep -qE "group:\s*auto-merge-\\\$\{\{\s*github\.event\.pull_request\.number\s*\}\}" \
   && printf '%s' "$WORKFLOW_TEXT" | grep -qE "cancel-in-progress:\s*true"; then
  pass "auto-merge.yml has a per-PR concurrency group with cancel-in-progress"
else
  fail "auto-merge.yml is missing the per-PR concurrency group (group: auto-merge-<pr>, cancel-in-progress: true)"
fi

if printf '%s' "$WORKFLOW_TEXT" | grep -qE "steps\.tier\.outputs\.tier == '3'" \
   && printf '%s' "$WORKFLOW_TEXT" | grep -q -- '--disable-auto'; then
  pass "auto-merge.yml revokes auto-merge on tier 3 (--disable-auto)"
else
  fail "auto-merge.yml has no tier==3 step calling --disable-auto"
fi

# Job-level, not workflow-level: a workflow-level group is joined before the
# job's `if:` runs, so a skipped body-only `edited` run would still cancel a
# sleeping Tier-1 run.
# Text check (no PyYAML dependency): no column-0 `concurrency:` key, and an
# indented one present.
if ! grep -qE '^concurrency:' <<<"$WORKFLOW_TEXT" && grep -qE '^[[:space:]]+concurrency:' <<<"$WORKFLOW_TEXT"; then
  pass "auto-merge.yml concurrency group is job-level (tier-check), not workflow-level"
else
  fail "auto-merge.yml concurrency must be on jobs.tier-check, not at workflow level"
fi

enable_calls="$(grep -c -- '--auto --squash' <<<"$WORKFLOW_TEXT")"
guarded_calls="$(grep -c -- '--auto --squash --match-head-commit' <<<"$WORKFLOW_TEXT")"
if [ "$enable_calls" -ge 2 ] && [ "$enable_calls" = "$guarded_calls" ]; then
  pass "every auto-merge enable call in auto-merge.yml pins --match-head-commit"
else
  fail "auto-merge.yml has an enable call without --match-head-commit (enable=$enable_calls guarded=$guarded_calls)"
fi

if printf '%s' "$WORKFLOW_TEXT" | grep -qE "ref:\s*\\\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\}\}"; then
  pass "auto-merge.yml checks out the PR's BASE commit before classifying (anti-tamper)"
else
  fail "auto-merge.yml does not check out the base commit — a PR could edit the classifier to pass itself"
fi

print_summary "classify-pr-tier.sh + auto-merge.yml wiring"
