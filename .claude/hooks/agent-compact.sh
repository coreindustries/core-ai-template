#!/usr/bin/env bash
# agent-compact.sh — SessionStart hook (matcher "compact|resume", wired in
# .claude/settings.json). Re-injects a session's lane role — recorded by
# agent-role.sh — plus its claimed issues and open PRs after context is
# compacted or a session resumed. The compaction summary alone does not keep
# a lane; this hook does.
#
# Contract (must never block or stall a session start):
#   - ALWAYS exits 0; internal failures go to stderr, never silently.
#   - No role recorded for this session -> no output.
#   - Each board.sh call is bounded to AGENT_COMPACT_BOARD_TIMEOUT_SECONDS
#     (default 15s). macOS ships no `timeout`/`setsid`, so run_bounded uses
#     bash job control: `set -m` gives the background job its own process
#     group, and the deadline kills the whole group (`kill -- -PGID`) —
#     killing only the direct child leaves board.sh's `gh` grandchild running.
#     Two calls worst-case = ~2x the deadline, which must stay under this
#     hook's timeout in settings.json (40s).
set -uo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/agent-state.sh"

BOARD="$AGENT_PROJECT_DIR/scripts/dev/board/board.sh"
DEADLINE="${AGENT_COMPACT_BOARD_TIMEOUT_SECONDS:-15}"

input="$(cat 2>/dev/null)"
[ -n "$input" ] || { hook_err "no stdin input — expected hook JSON"; exit 0; }
session_id="$(hook_json_field "$input" session_id)"
[ -n "$session_id" ] || { hook_err "could not read session_id from hook input"; exit 0; }

role_file="$(agent_state_dir)/$session_id.json"
[ -f "$role_file" ] || exit 0

role_json="$(cat "$role_file" 2>/dev/null)"
name="$(hook_json_field "$role_json" name)"
role="$(hook_json_field "$role_json" role)"
skill="$(hook_json_field "$role_json" skill)"
if [ -z "$name" ] || [ -z "$role" ] || [ -z "$skill" ]; then
  hook_err "role file $role_file unreadable or missing a field — no reminder"
  exit 0
fi

# run_bounded <deadline-seconds> <cmd...> — prints combined output; returns the
# command's exit code (124 on timeout) via a sidecar file, because `$?` after
# the cleanup `rm` would report rm's status instead.
run_bounded() {
  local deadline="$1"; shift
  local out_file rc_file waited pid pgid rc
  set -m
  out_file="$(mktemp)"; rc_file="$(mktemp)"
  ( "$@" > "$out_file" 2>&1; echo $? > "$rc_file" ) &
  pid=$!
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$deadline" ]; then
      if [ -n "$pgid" ]; then kill -KILL -- -"$pgid" 2>/dev/null; else kill -9 "$pid" 2>/dev/null; fi
      echo "(timed out after ${deadline}s)" >> "$out_file"
      echo 124 > "$rc_file"
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
  cat "$out_file"
  rc="$(cat "$rc_file" 2>/dev/null)"
  rm -f "$out_file" "$rc_file"
  return "${rc:-1}"
}

# board_section <label> <board.sh args...> — the command's output, or a line
# saying why it is unavailable. Never an empty, success-shaped section.
board_section() {
  local label="$1" out rc; shift
  out="$(run_bounded "$DEADLINE" "$BOARD" "$@")"; rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    printf '(%s unavailable: %s exit %s)' "$label" "$out" "$rc"
  else
    printf '%s\n' "$out" | head -n 15
  fi
}

cat <<EOF
You are $name ($role lane). Context was just compacted/resumed — before acting:
1. Re-read .claude/skills/$skill/SKILL.md and .claude/skills/_shared/agent-protocol.md.
2. Your claimed issues:
$(board_section list list --agent "$name")
3. Your open PRs:
$(board_section my-prs my-prs "$name")
4. Re-arm your PR watch: scripts/dev/board/pr-watch.sh --agent $name
EOF
exit 0
