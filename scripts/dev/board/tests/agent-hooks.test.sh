#!/usr/bin/env bash
# agent-hooks.test.sh — unit tests for .claude/hooks/agent-role.sh and
# .claude/hooks/agent-compact.sh (and their shared .claude/hooks/lib/
# agent-state.sh), against DISPOSABLE temp git repos as CLAUDE_PROJECT_DIR —
# never this repo's own .git — and a fake scripts/dev/board/board.sh (never
# the real one — this repo's real board.sh is owned/edited by a different
# concurrent agent and must not be depended on for test correctness).
#
# Every fixture project root gets its OWN copy of the three hook files (see
# copy_hooks_into below) so no invocation here ever reads from, or could ever
# write role state under, this repo's real .claude/hooks or .git.
#
# Run: bash scripts/dev/board/tests/agent-hooks.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
REAL_HOOKS_DIR="$REPO_ROOT/.claude/hooks"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

# Resolved via `cd ... && pwd -P`, not just mktemp's raw output: on macOS
# mktemp -d returns an unresolved /var/... path while git itself records the
# symlink-resolved /private/var/... form in `git rev-parse
# --path-format=absolute --git-common-dir` — without this, every
# git-common-dir-based state-file assertion below silently mismatches (see
# wt-clean.test.sh for the same fix, same reason).
WORK="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# copy_hooks_into <project-root> — installs this repo's CURRENT hook files
# (read-only source) into a disposable project root's .claude/hooks/, in the
# same relative layout (agent-role.sh/agent-compact.sh source lib/
# agent-state.sh relative to their own location, so the lib/ subdir must come
# along too).
copy_hooks_into() {
  local root="$1"
  mkdir -p "$root/.claude/hooks/lib"
  cp "$REAL_HOOKS_DIR/agent-role.sh" "$root/.claude/hooks/agent-role.sh"
  cp "$REAL_HOOKS_DIR/agent-compact.sh" "$root/.claude/hooks/agent-compact.sh"
  cp "$REAL_HOOKS_DIR/lib/agent-state.sh" "$root/.claude/hooks/lib/agent-state.sh"
  chmod +x "$root/.claude/hooks/agent-role.sh" "$root/.claude/hooks/agent-compact.sh"
}

# ---------------------------------------------------------------------------
# Main fixture: a REAL (non-worktree) disposable git repo, its own copy of
# the hooks, and its own board.sh fixture. Used for the bulk of the
# agent-role.sh/agent-compact.sh cases below.
# ---------------------------------------------------------------------------
FAKE_PROJECT="$WORK/fake-project"
git init -q "$FAKE_PROJECT"
copy_hooks_into "$FAKE_PROJECT"
ROLE_HOOK="$FAKE_PROJECT/.claude/hooks/agent-role.sh"
COMPACT_HOOK="$FAKE_PROJECT/.claude/hooks/agent-compact.sh"
STATE_DIR="$FAKE_PROJECT/.git/claude-agent-roles"
mkdir -p "$FAKE_PROJECT/scripts/dev/board"

# fake_board <mode>
#   pass — list/my-prs both print one fixture line and exit 0
#   fail — list/my-prs both exit 1 with no output
#   hang — sleeps far longer than any deadline this suite uses
#   hang_with_child — hangs AND forks a grandchild (a uniquely-named script,
#     since macOS `sleep` rejects a trailing marker argument) that must also
#     die when the deadline kill fires — proves the kill targets the whole
#     process group, not just the directly-backgrounded pid.
# Suffixed with this test run's own PID so a leftover process from a PRIOR
# (possibly still-sleeping) run of this suite can never contaminate this
# run's leftover-process check — a real risk empirically hit while
# developing this test: a stale marker from an earlier manual repro was
# still alive and made a later broken-kill mutation look clean.
HANG_CHILD_MARKER="board_hang_child_marker_$$"
fake_board() {
  local mode="$1"
  local path="$FAKE_PROJECT/scripts/dev/board/board.sh"
  case "$mode" in
    pass)
      {
        echo '#!/bin/sh'
        echo 'case "$1" in'
        echo '  list) echo "issue #1 fixture claimed"; exit 0 ;;'
        echo '  my-prs) echo "PR #99 fixture open"; exit 0 ;;'
        echo '  *) exit 1 ;;'
        echo 'esac'
      } > "$path"
      ;;
    fail)
      printf '#!/bin/sh\nexit 1\n' > "$path"
      ;;
    hang)
      printf '#!/bin/sh\nsleep 100\n' > "$path"
      ;;
    hang_with_child)
      local child="$FAKE_PROJECT/scripts/dev/board/$HANG_CHILD_MARKER.sh"
      printf '#!/bin/sh\nsleep 100\n' > "$child"
      chmod +x "$child"
      {
        echo '#!/bin/sh'
        echo "\"$child\" &"
        echo 'sleep 100'
      } > "$path"
      ;;
  esac
  chmod +x "$path"
}
fake_board pass

# run_role_hook <prompt-file> <session-id>
# Writes {"session_id":..., "prompt": <content of prompt-file>} and feeds it
# to agent-role.sh under a fresh, isolated CLAUDE_PROJECT_DIR. Prints the
# hook's stdout; state file (if any) lands under $STATE_DIR/<session-id>.json.
run_role_hook() {
  local prompt="$1" session_id="$2"
  local payload="$WORK/role-payload.json"
  python3 -c '
import json, sys
prompt = open(sys.argv[1]).read()
print(json.dumps({"session_id": sys.argv[2], "prompt": prompt}))
' "$prompt" "$session_id" > "$payload"
  CLAUDE_PROJECT_DIR="$FAKE_PROJECT" "$ROLE_HOOK" < "$payload"
}

role_of() {
  local session_id="$1"
  [ -f "$STATE_DIR/$session_id.json" ] || { echo ""; return; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("role",""))' "$STATE_DIR/$session_id.json" 2>/dev/null
}
name_of() {
  local session_id="$1"
  [ -f "$STATE_DIR/$session_id.json" ] || { echo ""; return; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$STATE_DIR/$session_id.json" 2>/dev/null
}

echo ""
echo "=== agent-role.sh unit tests ==="

# ── Positive matches (exact phrases named in the task spec) ────────────────
rm -rf "$STATE_DIR"; printf '%s' "You are the Release Manager" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-release >/dev/null
[ "$(role_of sess-release)" = "release" ] && pass "release-manager-phrase-matches" \
  || fail "release-manager-phrase-matches (got role='$(role_of sess-release)')"
[ "$(name_of sess-release)" = "C-RELEASE" ] && pass "release-manager-name-is-c-release" \
  || fail "release-manager-name-is-c-release (got '$(name_of sess-release)')"

rm -rf "$STATE_DIR"; printf '%s' "You are the Feature manager" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-feature >/dev/null
[ "$(role_of sess-feature)" = "feature" ] && pass "feature-manager-phrase-matches" \
  || fail "feature-manager-phrase-matches (got role='$(role_of sess-feature)')"

rm -rf "$STATE_DIR"; printf '%s' "you handle bug fixes" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-bugfix >/dev/null
[ "$(role_of sess-bugfix)" = "bugfix" ] && pass "handle-bug-fixes-phrase-matches" \
  || fail "handle-bug-fixes-phrase-matches (got role='$(role_of sess-bugfix)')"

rm -rf "$STATE_DIR"; printf '%s' "You are feature agent 2" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-feature2 >/dev/null
[ "$(name_of sess-feature2)" = "C-FEATURE-2" ] && pass "feature-agent-2-numbered-name" \
  || fail "feature-agent-2-numbered-name (got '$(name_of sess-feature2)')"

rm -rf "$STATE_DIR"; printf '%s' "you are bugfix agent #3" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-bugfix3 >/dev/null
[ "$(name_of sess-bugfix3)" = "C-BUGFIX-3" ] && pass "bugfix-agent-3-numbered-name" \
  || fail "bugfix-agent-3-numbered-name (got '$(name_of sess-bugfix3)')"

rm -rf "$STATE_DIR"; printf '%s' "You are the bugfix agent #4" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-bugfix4 >/dev/null
[ "$(name_of sess-bugfix4)" = "C-BUGFIX-4" ] && pass "bugfix-agent-hash4-numbered-name" \
  || fail "bugfix-agent-hash4-numbered-name (got '$(name_of sess-bugfix4)')"

rm -rf "$STATE_DIR"; printf '%s' "You handle bug fixes" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-bugfixplain >/dev/null
[ "$(name_of sess-bugfixplain)" = "C-BUGFIX-sess" ] && pass "handle-bug-fixes-plain-falls-back-to-session-id" \
  || fail "handle-bug-fixes-plain-falls-back-to-session-id (got '$(name_of sess-bugfixplain)')"

# P1 regression: a number that appears LATER in the prompt, after the role
# sentence has already ended, must NOT be captured as the lane suffix — even
# though it happens to be preceded by the word "lane". Before the fix, the
# number regex re-scanned the WHOLE prompt for `(agent|manager|lane)\s*#?\d+`
# and matched "lane 7" here, producing C-FEATURE-7.
rm -rf "$STATE_DIR"; printf '%s' "You are the feature agent. Start with lane 7 backlog" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-lanetrap >/dev/null
[ "$(role_of sess-lanetrap)" = "feature" ] && pass "lane-trap-role-still-matches-feature" \
  || fail "lane-trap-role-still-matches-feature (got '$(role_of sess-lanetrap)')"
[ "$(name_of sess-lanetrap)" = "C-FEATURE-sess" ] && pass "lane-trap-number-not-captured-falls-back-to-session-id (mutation-checked)" \
  || fail "lane-trap-number-not-captured-falls-back-to-session-id (mutation-checked) (got '$(name_of sess-lanetrap)')"

# MUTATION CHECK: revert the number extraction to the OLD whole-prompt scan
# (`re.search(r"(?:agent|manager|lane)\s*#?(\d{1,3})\b", prompt, ...)`, no
# anchor, group(1)) and confirm the lane-trap prompt above now regresses to
# capturing "lane 7" as the suffix — proving the anchored-match fix above is
# what makes lane-trap pass, not some other incidental guard. Built via a
# literal python3 string replace (not sed) so the regex escaping in the
# mutant source is unambiguous.
# agent-role.sh sources lib/agent-state.sh relative to its OWN location, so
# the mutant needs a copy of lib/ sitting next to it too, or it fails at
# source-time (a false pass/fail unrelated to the mutation itself).
MUTANT_ROLE_DIR="$WORK/mutant-role-dir"
mkdir -p "$MUTANT_ROLE_DIR/lib"
cp "$REAL_HOOKS_DIR/lib/agent-state.sh" "$MUTANT_ROLE_DIR/lib/agent-state.sh"
MUTANT_ROLE="$MUTANT_ROLE_DIR/agent-role.sh"
python3 -c '
import sys
src = open(sys.argv[1]).read()
old = "    m = re.search(num_pattern, prompt, re.IGNORECASE)\n"
new = "    m = re.search(r\"(?:agent|manager|lane)\\s*#?(\\d{1,3})\\b\", prompt, re.IGNORECASE)\n"
if old not in src:
    sys.exit(2)
open(sys.argv[2], "w").write(src.replace(old, new))
' "$ROLE_HOOK" "$MUTANT_ROLE"
mutant_rc=$?
chmod +x "$MUTANT_ROLE"

if [ "$mutant_rc" -ne 0 ]; then
  fail "MUTATION CHECK: could not locate the number-extraction block to mutate in agent-role.sh (source drifted from the expected text)"
else
  rm -rf "$STATE_DIR"; printf '%s' "You are the feature agent. Start with lane 7 backlog" > "$WORK/p.txt"
  mutant_payload="$WORK/mutant-role-payload.json"
  python3 -c '
import json, sys
prompt = open(sys.argv[1]).read()
print(json.dumps({"session_id": sys.argv[2], "prompt": prompt}))
' "$WORK/p.txt" "sess-mutanttrap" > "$mutant_payload"
  CLAUDE_PROJECT_DIR="$FAKE_PROJECT" "$MUTANT_ROLE" < "$mutant_payload" >/dev/null
  if [ "$(name_of sess-mutanttrap)" = "C-FEATURE-7" ]; then
    pass "MUTATION CHECK: reverting to the whole-prompt number scan re-captures 'lane 7' as C-FEATURE-7 (anchored fix is load-bearing)"
  else
    fail "MUTATION CHECK: reverting to the whole-prompt number scan should have produced C-FEATURE-7 (got '$(name_of sess-mutanttrap)')"
  fi
fi

# Hyphen variant of the release regex's [- ]? class.
rm -rf "$STATE_DIR"; printf '%s' "You are the release-manager" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-hyphen >/dev/null
[ "$(role_of sess-hyphen)" = "release" ] && pass "release-manager-hyphen-variant-matches" \
  || fail "release-manager-hyphen-variant-matches (got role='$(role_of sess-hyphen)')"

# Slash-command forms.
rm -rf "$STATE_DIR"; printf '%s' "/feature-agent please continue" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-slash-feature >/dev/null
[ "$(role_of sess-slash-feature)" = "feature" ] && pass "slash-feature-agent-matches" \
  || fail "slash-feature-agent-matches (got role='$(role_of sess-slash-feature)')"

# ── Negative matches (named in the task spec) — mutation-checks the anchor:
#    a regex that degraded to a bare keyword search would wrongly match both. ─
rm -rf "$STATE_DIR"; printf '%s' "fix the release notes" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-neg1)"
[ -z "$out" ] && pass "fix-the-release-notes-no-match-stdout" || fail "fix-the-release-notes-no-match-stdout (got '$out')"
[ ! -f "$STATE_DIR/sess-neg1.json" ] && pass "fix-the-release-notes-no-state-file" || fail "fix-the-release-notes-no-state-file"

rm -rf "$STATE_DIR"; printf '%s' "what features remain" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-neg2)"
[ -z "$out" ] && pass "what-features-remain-no-match-stdout" || fail "what-features-remain-no-match-stdout (got '$out')"
[ ! -f "$STATE_DIR/sess-neg2.json" ] && pass "what-features-remain-no-state-file" || fail "what-features-remain-no-state-file"

# ── P1 mutation checks: an unanchored/keyword-only regex would wrongly
#    match all three of these (verified against the pre-fix pattern) ───────
rm -rf "$STATE_DIR"; printf '%s' "please read .claude/skills/feature-agent/SKILL.md" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-neg3)"
[ -z "$out" ] && pass "skill-path-mid-sentence-no-match-stdout" || fail "skill-path-mid-sentence-no-match-stdout (got '$out')"
[ ! -f "$STATE_DIR/sess-neg3.json" ] && pass "skill-path-mid-sentence-no-state-file" || fail "skill-path-mid-sentence-no-state-file"

rm -rf "$STATE_DIR"; printf '%s' "you are a feature-flag expert" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-neg4)"
[ -z "$out" ] && pass "feature-flag-expert-no-match-stdout" || fail "feature-flag-expert-no-match-stdout (got '$out')"
[ ! -f "$STATE_DIR/sess-neg4.json" ] && pass "feature-flag-expert-no-state-file" || fail "feature-flag-expert-no-state-file"

rm -rf "$STATE_DIR"; printf '%s' "look at scripts/release-manager/foo" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-neg5)"
[ -z "$out" ] && pass "release-manager-path-mid-sentence-no-match-stdout" || fail "release-manager-path-mid-sentence-no-match-stdout (got '$out')"
[ ! -f "$STATE_DIR/sess-neg5.json" ] && pass "release-manager-path-mid-sentence-no-state-file" || fail "release-manager-path-mid-sentence-no-state-file"

# ── P2 mutation check: a number NOT directly following agent|manager|lane
#    must not be captured — falls back to the session-id-derived suffix ────
rm -rf "$STATE_DIR"; printf '%s' "you handle bug fixes for issue #3700" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess1234 >/dev/null
[ "$(name_of sess1234)" = "C-BUGFIX-sess" ] && pass "unrelated-issue-number-not-captured-falls-back-to-session-id" \
  || fail "unrelated-issue-number-not-captured-falls-back-to-session-id (got '$(name_of sess1234)')"

# ── Prompt text is never written to the state file ──────────────────────────
rm -rf "$STATE_DIR"; printf '%s' "You are the Release Manager — secret-token-xyz" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-noleak >/dev/null
if [ -f "$STATE_DIR/sess-noleak.json" ] && ! grep -q 'secret-token-xyz' "$STATE_DIR/sess-noleak.json"; then
  pass "prompt-text-not-persisted-to-state-file"
else
  fail "prompt-text-not-persisted-to-state-file"
fi

# ── Hook always exits 0, even on match ──────────────────────────────────────
rm -rf "$STATE_DIR"; printf '%s' "You are the Release Manager" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-exit0 >/dev/null
rc=$?
[ "$rc" -eq 0 ] && pass "role-hook-exits-0-on-match" || fail "role-hook-exits-0-on-match (got $rc)"

# ── No-overwrite guard + visible CHANGED transition ─────────────────────────
rm -rf "$STATE_DIR"; printf '%s' "You are the Release Manager" > "$WORK/p.txt"
run_role_hook "$WORK/p.txt" sess-noover >/dev/null
[ "$(role_of sess-noover)" = "release" ] && pass "noover-initial-role-is-release" \
  || fail "noover-initial-role-is-release (got '$(role_of sess-noover)')"

# Plant a sentinel set_at directly in the state file. A rewrite (broken
# no-overwrite guard) would replace it with a real UTC timestamp; a correct
# no-op guard leaves it untouched — this is the mutation check, since two
# calls landing in the same wall-clock second would otherwise make a
# before/after timestamp comparison a false pass.
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["set_at"] = "SENTINEL-DO-NOT-REWRITE"
json.dump(d, open(p, "w"))
' "$STATE_DIR/sess-noover.json"

# Re-asserting the SAME role bucket must be a complete no-op: no stdout,
# state file untouched (sentinel survives).
printf '%s' "You are the Release Manager, again" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-noover)"
[ -z "$out" ] && pass "same-role-reassert-no-stdout" || fail "same-role-reassert-no-stdout (got '$out')"
set_at_after="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("set_at",""))' "$STATE_DIR/sess-noover.json")"
[ "$set_at_after" = "SENTINEL-DO-NOT-REWRITE" ] && pass "same-role-reassert-does-not-rewrite-state (mutation-checked)" \
  || fail "same-role-reassert-does-not-rewrite-state (mutation-checked) (got '$set_at_after')"
[ "$(name_of sess-noover)" = "C-RELEASE" ] && pass "same-role-reassert-name-unchanged" \
  || fail "same-role-reassert-name-unchanged (got '$(name_of sess-noover)')"

# A DIFFERENT role bucket DOES overwrite — deliberate reassignment — and
# prints the visible CHANGED line naming old and new.
printf '%s' "you are bugfix agent #7" > "$WORK/p.txt"
out="$(run_role_hook "$WORK/p.txt" sess-noover)"
printf '%s' "$out" | grep -qx 'Agent role CHANGED: C-RELEASE -> C-BUGFIX-7' \
  && pass "different-role-overwrite-prints-changed-line" || fail "different-role-overwrite-prints-changed-line (got '$out')"
[ "$(role_of sess-noover)" = "bugfix" ] && pass "different-role-overwrite-updates-role" \
  || fail "different-role-overwrite-updates-role (got '$(role_of sess-noover)')"
[ "$(name_of sess-noover)" = "C-BUGFIX-7" ] && pass "different-role-overwrite-updates-name" \
  || fail "different-role-overwrite-updates-name (got '$(name_of sess-noover)')"
set_at_final="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("set_at",""))' "$STATE_DIR/sess-noover.json")"
[ "$set_at_final" != "SENTINEL-DO-NOT-REWRITE" ] && pass "different-role-overwrite-does-rewrite-state" \
  || fail "different-role-overwrite-does-rewrite-state"

echo ""
echo "=== agent-compact.sh unit tests ==="

payload_for() {
  local session_id="$1"
  local f="$WORK/compact-payload.json"
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "source": "compact"}))' "$session_id" > "$f"
  echo "$f"
}

# ── No role file -> prints nothing, exits 0 ──────────────────────────────────
rm -rf "$STATE_DIR"
p="$(payload_for no-such-session)"
out="$(CLAUDE_PROJECT_DIR="$FAKE_PROJECT" "$COMPACT_HOOK" < "$p")"
rc=$?
[ -z "$out" ] && pass "compact-no-role-file-prints-nothing" || fail "compact-no-role-file-prints-nothing (got '$out')"
[ "$rc" -eq 0 ] && pass "compact-no-role-file-exits-0" || fail "compact-no-role-file-exits-0 (got $rc)"

# ── Role file present -> prints the full reminder block ────────────────────
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/sess-block.json" <<'EOF'
{"role":"bugfix","skill":"bugfix-agent","name":"C-BUGFIX-1","set_at":"2026-09-23T00:00:00Z"}
EOF
fake_board pass
p="$(payload_for sess-block)"
out="$(CLAUDE_PROJECT_DIR="$FAKE_PROJECT" AGENT_COMPACT_BOARD_TIMEOUT_SECONDS=10 "$COMPACT_HOOK" < "$p")"
rc=$?
[ "$rc" -eq 0 ] && pass "compact-with-role-file-exits-0" || fail "compact-with-role-file-exits-0 (got $rc)"
printf '%s' "$out" | grep -q 'You are C-BUGFIX-1 (bugfix lane)' \
  && pass "compact-block-names-agent-and-lane" || fail "compact-block-names-agent-and-lane"
printf '%s' "$out" | grep -q '\.claude/skills/bugfix-agent/SKILL\.md' \
  && pass "compact-block-cites-skill-path" || fail "compact-block-cites-skill-path"
printf '%s' "$out" | grep -q 'issue #1 fixture claimed' \
  && pass "compact-block-shows-claimed-issues" || fail "compact-block-shows-claimed-issues"
printf '%s' "$out" | grep -q 'PR #99 fixture open' \
  && pass "compact-block-shows-open-prs" || fail "compact-block-shows-open-prs"
printf '%s' "$out" | grep -q 'pr-watch.sh --agent C-BUGFIX-1' \
  && pass "compact-block-rearm-line" || fail "compact-block-rearm-line"

# ── board.sh failing (non-zero, no output) -> degrades to an explicit
#    "unavailable" note, never a crash or a silently empty section ─────────
fake_board fail
p="$(payload_for sess-block)"
out="$(CLAUDE_PROJECT_DIR="$FAKE_PROJECT" AGENT_COMPACT_BOARD_TIMEOUT_SECONDS=10 "$COMPACT_HOOK" < "$p")"
rc=$?
[ "$rc" -eq 0 ] && pass "compact-board-failure-still-exits-0" || fail "compact-board-failure-still-exits-0 (got $rc)"
printf '%s' "$out" | grep -q 'my-prs unavailable' \
  && pass "compact-board-failure-my-prs-unavailable-note" || fail "compact-board-failure-my-prs-unavailable-note"

# ── Deadline enforcement: a hanging board.sh must be killed, not waited out ─
#    Mutation check on the deadline itself: assert the ACTUAL elapsed time is
#    bounded well under the fixture's 100s sleep. If the kill logic were
#    ever removed/broken, this is the assertion that would catch it — a
#    passing-but-slow run (elapsed ~100s+) fails the bound below.
fake_board hang
p="$(payload_for sess-block)"
start_ts=$(date +%s)
out="$(CLAUDE_PROJECT_DIR="$FAKE_PROJECT" AGENT_COMPACT_BOARD_TIMEOUT_SECONDS=2 "$COMPACT_HOOK" < "$p")"
rc=$?
end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
[ "$rc" -eq 0 ] && pass "compact-hang-still-exits-0" || fail "compact-hang-still-exits-0 (got $rc)"
# Two sequential bounded calls at a 2s deadline: budget generously to 15s to
# absorb slow CI scheduling, while still being far below the 100s sleep — a
# broken kill would blow well past this.
[ "$elapsed" -le 15 ] && pass "compact-hang-killed-within-deadline (elapsed ${elapsed}s)" \
  || fail "compact-hang-killed-within-deadline (elapsed ${elapsed}s, expected <=15s)"
printf '%s' "$out" | grep -q 'timed out after 2s' \
  && pass "compact-hang-reports-timeout-reason" || fail "compact-hang-reports-timeout-reason"

echo ""
echo "=== state-dir resolution (git-common-dir) ==="

# Fallback path: a SEPARATE, deliberately non-git disposable project root
# (FAKE_PROJECT above is now a real git repo, used for the bulk of the
# role/compact cases — this one exists solely to exercise agent_state_dir()'s
# loud fallback when git itself fails), with its own copy of the hooks.
NONGIT_PROJECT="$WORK/nongit-project"
mkdir -p "$NONGIT_PROJECT"
copy_hooks_into "$NONGIT_PROJECT"
NONGIT_ROLE_HOOK="$NONGIT_PROJECT/.claude/hooks/agent-role.sh"

payload="$WORK/fallback-payload.json"
printf '%s' "You are the Release Manager" > "$WORK/p.txt"
python3 -c '
import json, sys
prompt = open(sys.argv[1]).read()
print(json.dumps({"session_id": sys.argv[2], "prompt": prompt}))
' "$WORK/p.txt" "sess-fallback" > "$payload"
stderr_out="$(CLAUDE_PROJECT_DIR="$NONGIT_PROJECT" "$NONGIT_ROLE_HOOK" < "$payload" 2>&1 1>/dev/null)"
printf '%s' "$stderr_out" | grep -q 'git rev-parse --git-common-dir failed' \
  && pass "non-git-project-dir-logs-fallback-to-stderr" || fail "non-git-project-dir-logs-fallback-to-stderr (got '$stderr_out')"
[ -f "$NONGIT_PROJECT/.claude/state/agent-roles/sess-fallback.json" ] && pass "non-git-project-dir-still-writes-fallback-state-file" \
  || fail "non-git-project-dir-still-writes-fallback-state-file"

# Real git-repo case, including a WORKTREE — the actual motivating scenario:
# a session running from a linked worktree must write role state under the
# MAIN repo's common .git dir, never under the worktree's own working tree
# (which would make `wt-clean` see the worktree as dirty).
GIT_FIXTURE="$WORK/git-fixture"
MAIN_REPO="$GIT_FIXTURE/main"
WT_REPO="$GIT_FIXTURE/wt"
git_fixture_ok=1
mkdir -p "$GIT_FIXTURE"
git init -q "$MAIN_REPO"
copy_hooks_into "$MAIN_REPO"
(
  set -e
  cd "$MAIN_REPO"
  git config user.email test@example.com
  git config user.name "Test"
  git add .claude
  git commit -q -m init
  git worktree add -q -b agent-hooks-test-wt "$WT_REPO" HEAD
) >/tmp/agent-hooks-test-gitfixture.log 2>&1 || git_fixture_ok=0

MAIN_ROLE_HOOK="$MAIN_REPO/.claude/hooks/agent-role.sh"
MAIN_COMPACT_HOOK="$MAIN_REPO/.claude/hooks/agent-compact.sh"
# The worktree checks out the SAME tracked files committed into MAIN_REPO
# above (git worktree add populates it from HEAD, which now includes
# .claude/hooks) — its own copy, not MAIN_REPO's, so a stray relative-path
# assumption in either hook would be caught here too.
WT_ROLE_HOOK="$WT_REPO/.claude/hooks/agent-role.sh"
WT_COMPACT_HOOK="$WT_REPO/.claude/hooks/agent-compact.sh"

if [ "$git_fixture_ok" -ne 1 ]; then
  fail "git-fixture-setup (see /tmp/agent-hooks-test-gitfixture.log)"
else
  pass "git-fixture-setup"

  payload="$WORK/gitmain-payload.json"
  python3 -c '
import json, sys
prompt = open(sys.argv[1]).read()
print(json.dumps({"session_id": sys.argv[2], "prompt": prompt}))
' "$WORK/p.txt" "sess-gitmain" > "$payload"
  CLAUDE_PROJECT_DIR="$MAIN_REPO" "$MAIN_ROLE_HOOK" < "$payload" >/dev/null
  [ -f "$MAIN_REPO/.git/claude-agent-roles/sess-gitmain.json" ] && pass "plain-repo-state-lands-under-its-own-git-common-dir" \
    || fail "plain-repo-state-lands-under-its-own-git-common-dir"
  [ ! -d "$MAIN_REPO/.claude/state" ] && pass "plain-repo-working-tree-not-polluted-by-state" \
    || fail "plain-repo-working-tree-not-polluted-by-state"

  payload="$WORK/gitwt-payload.json"
  python3 -c '
import json, sys
prompt = open(sys.argv[1]).read()
print(json.dumps({"session_id": sys.argv[2], "prompt": prompt}))
' "$WORK/p.txt" "sess-gitwt" > "$payload"
  CLAUDE_PROJECT_DIR="$WT_REPO" "$WT_ROLE_HOOK" < "$payload" >/dev/null
  [ -f "$MAIN_REPO/.git/claude-agent-roles/sess-gitwt.json" ] && pass "worktree-session-state-lands-under-MAIN-repo-common-dir" \
    || fail "worktree-session-state-lands-under-MAIN-repo-common-dir"
  [ ! -d "$WT_REPO/.claude/state" ] && pass "worktree-own-working-tree-not-polluted-by-state" \
    || fail "worktree-own-working-tree-not-polluted-by-state"

  # agent-compact.sh must resolve to the SAME location agent-role.sh wrote
  # to — running it with CLAUDE_PROJECT_DIR=WT_REPO must still find the role
  # file that landed under MAIN_REPO's common dir.
  compact_payload="$WORK/gitwt-compact-payload.json"
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "source": "compact"}))' "sess-gitwt" > "$compact_payload"
  out="$(CLAUDE_PROJECT_DIR="$WT_REPO" AGENT_COMPACT_BOARD_TIMEOUT_SECONDS=5 "$WT_COMPACT_HOOK" < "$compact_payload")"
  printf '%s' "$out" | grep -q '^You are C-RELEASE (release lane)\.' \
    && pass "compact-hook-finds-role-via-same-resolver-from-worktree" \
    || fail "compact-hook-finds-role-via-same-resolver-from-worktree (got '$out')"
fi

# ── P3 mutation check: the deadline kill must reach a GRANDCHILD board.sh
#    forks, not just the directly-backgrounded process ─────────────────────
fake_board hang_with_child
p="$(payload_for sess-block)"
CLAUDE_PROJECT_DIR="$FAKE_PROJECT" AGENT_COMPACT_BOARD_TIMEOUT_SECONDS=2 "$COMPACT_HOOK" < "$p" >/dev/null
rc=$?
[ "$rc" -eq 0 ] && pass "compact-grandchild-hang-still-exits-0" || fail "compact-grandchild-hang-still-exits-0 (got $rc)"
sleep 1
if pgrep -f "$HANG_CHILD_MARKER" >/dev/null 2>&1; then
  fail "compact-grandchild-hang-no-leftover-process (leftover found — process-group kill did not reach the grandchild)"
else
  pass "compact-grandchild-hang-no-leftover-process"
fi
# Safety net regardless of pass/fail — never leave a fixture process behind
# for a LATER run of this suite to trip over (see the marker-uniqueness
# comment above).
pkill -f "$HANG_CHILD_MARKER" 2>/dev/null || true

print_summary "agent-hooks (agent-role.sh + agent-compact.sh)"
