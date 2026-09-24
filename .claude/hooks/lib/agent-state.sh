#!/usr/bin/env bash
# agent-state.sh — shared by agent-role.sh (writes a session's lane role) and
# agent-compact.sh (reads it back after compaction/resume). Source it.
#
# State lives under the repo's COMMON git dir (<git-common-dir>/claude-agent-roles/),
# shared by every worktree and never part of any working tree — so a role file
# never makes a worktree look dirty and never needs gitignoring.

AGENT_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

hook_err() { echo "$(basename "$0"): $1" >&2; }

# agent_state_dir — prints the role-state directory. Falls back, loudly, to a
# gitignored path inside the project if git cannot answer.
agent_state_dir() {
  local common
  common="$(cd "$AGENT_PROJECT_DIR" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -z "$common" ]; then
    hook_err "git rev-parse --git-common-dir failed — using $AGENT_PROJECT_DIR/.claude/state/agent-roles"
    printf '%s' "$AGENT_PROJECT_DIR/.claude/state/agent-roles"
    return
  fi
  printf '%s/claude-agent-roles' "$common"
}

# hook_json_field <json> <field> — top-level string field from hook input.
# jq when present, python3 otherwise; prints nothing if neither can parse it.
hook_json_field() {
  local out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$1" | jq -r --arg f "$2" '.[$f] // empty' 2>/dev/null)"
  fi
  if [ -z "$out" ] && command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$1" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get(sys.argv[1]) or "")
except Exception:
    print("")
' "$2" 2>/dev/null)"
  fi
  printf '%s' "$out"
}

# agent_name_prefix — from .claude/agent-lanes.json (namePrefix), default C.
agent_name_prefix() {
  local p=""
  if command -v jq >/dev/null 2>&1 && [ -f "$AGENT_PROJECT_DIR/.claude/agent-lanes.json" ]; then
    p="$(jq -r '.namePrefix // empty' "$AGENT_PROJECT_DIR/.claude/agent-lanes.json" 2>/dev/null)"
  fi
  printf '%s' "$p" | grep -Eq '^[A-Za-z][A-Za-z0-9]{0,11}$' || p="C"
  printf '%s' "$p"
}
