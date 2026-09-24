#!/usr/bin/env bash
# agent-role.sh — UserPromptSubmit hook (wired in .claude/settings.json).
# Detects a prompt that assigns THIS session a standing lane role — Release
# Manager, feature agent, or bugfix agent — and records it to
# <state-dir>/<session_id>.json, so agent-compact.sh can remind the session who
# it is after compaction or resume, when the assigning prompt is gone.
#
# Contract (a role-tracking hook must never block a prompt):
#   - ALWAYS exits 0. Internal failures go to stderr, never silently.
#   - The prompt TEXT is never written anywhere — only which role matched.
#   - No match -> no output, no write.
#   - The same role matching again is a no-op (no write, no output), so a later
#     incidental mention doesn't reset set_at. A DIFFERENT role overwrites and
#     prints "Agent role CHANGED: <old> -> <new>" — visible, never silent.
#   - Fast: no network calls.
#
# Matching is case-insensitive and ANCHORED TO THE START of the prompt, so a
# mid-sentence mention ("read .claude/skills/feature-agent/SKILL.md") never
# assigns a role. Sentence forms also need the role NOUN (manager/agent/lane)
# after the topic word, so "you are a feature-flag expert" does not match:
#   release  ^/release-manager | ^you are (the |a )?release[- ]?manager
#   feature  ^/feature-agent   | ^you are (the |a )?feature (manager|agent|lane)
#   bugfix   ^/bugfix-agent    | ^you (handle|do|own) (the )?bug ?fix(es)?
#                              | ^you are (the |a )?bug ?fix(es)? (manager|agent|lane)
# A lane number ("feature agent 2") is taken ONLY when it directly follows the
# role noun in that anchored span; a number elsewhere ("... for issue #123")
# falls back to the first four characters of the session id.
# Names: <P>-RELEASE, <P>-FEATURE-<id>, <P>-BUGFIX-<id>; <P> = namePrefix in
# .claude/agent-lanes.json (default C).
set -uo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/agent-state.sh"

input="$(cat 2>/dev/null)"
[ -n "$input" ] || { hook_err "no stdin input — expected hook JSON"; exit 0; }

session_id="$(hook_json_field "$input" session_id)"
prompt="$(hook_json_field "$input" prompt)"
[ -n "$session_id" ] || { hook_err "could not read session_id from hook input"; exit 0; }
[ -n "$prompt" ] || exit 0
command -v python3 >/dev/null 2>&1 || { hook_err "python3 not found — cannot match role patterns"; exit 0; }

STATE_DIR="$(agent_state_dir)"
mkdir -p "$STATE_DIR" 2>/dev/null || { hook_err "could not create state dir $STATE_DIR"; exit 0; }

# `python3 -c`, not a heredoc: a heredoc on `python3 -` feeds the SCRIPT through
# stdin, and the piped prompt would never arrive (a silent no-op).
out="$(printf '%s' "$prompt" | SESSION_ID="$session_id" STATE_DIR="$STATE_DIR" \
  PREFIX="$(agent_name_prefix)" SET_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" python3 -c '
import json, os, re, sys

prompt = sys.stdin.read()
session_id, state_dir, prefix = os.environ["SESSION_ID"], os.environ["STATE_DIR"], os.environ["PREFIX"]

# Each role: the sentence patterns, and (for numbered lanes) the same anchored
# sentence with a number captured right after the role noun.
ROLES = [
    ("release", "release-manager", [
        r"^\s*/release-manager\b",
        r"^\s*you are (?:the |a )?release[ -]?manager\b",
    ], None),
    ("feature", "feature-agent", [
        r"^\s*/feature-agent\b",
        r"^\s*you are (?:the |a )?feature (?:manager|agent|lane)\b",
    ], r"^\s*you are (?:the |a )?feature (?:manager|agent|lane)\s*#?(\d{1,3})\b"),
    ("bugfix", "bugfix-agent", [
        r"^\s*/bugfix-agent\b",
        r"^\s*you (?:handle|do|own) (?:the )?bug ?fix(?:es)?\b",
        r"^\s*you are (?:the |a )?bug ?fix(?:es)? (?:manager|agent|lane)\b",
    ], r"^\s*you are (?:the |a )?bug ?fix(?:es)? (?:manager|agent|lane)\s*#?(\d{1,3})\b"),
]

match = next(((r, s, n) for r, s, pats, n in ROLES
              if any(re.search(p, prompt, re.IGNORECASE) for p in pats)), None)
if match is None:
    sys.exit(0)
role, skill, num_pattern = match

path = os.path.join(state_dir, "%s.json" % session_id)
existing = None
if os.path.exists(path):
    try:
        with open(path) as f:
            existing = json.load(f)
    except (OSError, ValueError):
        existing = None
if existing is not None and existing.get("role") == role:
    sys.exit(0)

if role == "release":
    name = "%s-RELEASE" % prefix
else:
    m = re.search(num_pattern, prompt, re.IGNORECASE)
    name = "%s-%s-%s" % (prefix, role.upper(), m.group(1) if m else (session_id[:4] or "0000"))

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump({"role": role, "skill": skill, "name": name, "set_at": os.environ["SET_AT"]}, f)
os.replace(tmp, path)

if existing is not None:
    print("Agent role CHANGED: %s -> %s" % (existing.get("name") or existing.get("role") or "?", name))
else:
    print("Agent role recorded: %s (%s lane). Load the %s skill and follow "
          ".claude/skills/_shared/agent-protocol.md. Use %s as your agent name everywhere."
          % (name, role, skill, name))
')"
rc=$?
[ "$rc" -eq 0 ] || { hook_err "role matching failed (python3 exit $rc) for session $session_id"; exit 0; }
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
