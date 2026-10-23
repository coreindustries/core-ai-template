#!/usr/bin/env bash
# post-compact.sh — PostCompact hook (wired in .claude/settings.json).
# Keeps Claude Code's own compaction summary, with the trigger and the
# transcript path, so a lane can recover a detail the summary dropped.
# Claude Code cannot be told what a summary must keep, so the backstop is to
# keep the summary and point at the full transcript.
#
# Written to <git-common-dir>/claude-compactions/<session_id>/<utc>-<trigger>.md,
# beside agent-role.sh's claude-agent-roles state dir, so every worktree of
# this repo shares it and nothing lands in the tracked tree.
# agent-compact.sh lists the newest files in its re-brief.
#
# Contract: side effects only, ALWAYS exits 0, failures reported on stderr.
set -uo pipefail

err() { echo "post-compact hook: $1" >&2; }

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

input="$(cat 2>/dev/null)"
if [ -z "$input" ]; then
  err "no stdin input — expected hook JSON; summary NOT saved"
  exit 0
fi

common_dir="$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"
if [ -z "$common_dir" ]; then
  err "git rev-parse --git-common-dir failed in $PROJECT_DIR; summary NOT saved"
  exit 0
fi
case "$common_dir" in /*) : ;; *) common_dir="$PROJECT_DIR/$common_dir" ;; esac

printf '%s' "$input" | python3 -c '
import json, os, sys, time
root = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception as e:
    sys.exit(f"post-compact hook: hook JSON unparseable ({e}); summary NOT saved")
sid = d.get("session_id") or "unknown-session"
trigger = d.get("trigger") or "unknown"
summary = d.get("compact_summary") or ""
if not summary:
    print(f"post-compact hook: compact_summary empty (session {sid}, trigger {trigger}); saving header only", file=sys.stderr)
out_dir = os.path.join(root, "claude-compactions", sid)
os.makedirs(out_dir, exist_ok=True)
stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
path = os.path.join(out_dir, f"{stamp}-{trigger}.md")
with open(path, "w") as f:
    transcript = d.get("transcript_path") or "?"
    f.write(f"<!-- trigger={trigger} chars={len(summary)} transcript={transcript} -->\n")
    f.write(summary)
    f.write("\n")
' "$common_dir" || err "python3 failed writing the compaction summary (exit $?)"

exit 0
