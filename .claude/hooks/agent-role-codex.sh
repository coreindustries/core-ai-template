#!/usr/bin/env bash
# agent-role-codex.sh — Codex UserPromptSubmit adapter for agent-role.sh.
#
# Wired from .codex/hooks.json (project-level; requires the user to run
# `/hooks` once to trust it — Codex hooks are inert until trusted). Codex's
# UserPromptSubmit stdin JSON was verified (2026-09, developers.openai.com/codex/hooks,
# cross-checked against public openai/codex issue reports on the same event)
# to carry the same top-level fields agent-role.sh already reads plus a few
# Codex-only ones: {session_id, turn_id, cwd, hook_event_name, model,
# permission_mode, prompt}. agent-role.sh reads session_id and prompt via
# hook_json_field()'s `.get(field)` lookup, which ignores unknown fields, so
# no parsing change is needed there. Plain stdout text on exit 0 is added as
# developer context under both runtimes — Codex renders it as a visible
# developer message (see openai/codex#16933) rather than Claude Code's silent
# system-reminder injection; either way, the lane-assignment message reaches
# the session. See docs/codex.md "UserPromptSubmit hook" for the parts of the
# contract we could NOT independently verify (SessionStart's additionalContext
# has a known open issue, openai/codex#45999 — irrelevant here since this
# adapter only wires UserPromptSubmit).
#
# This file exists (rather than pointing .codex/hooks.json straight at
# agent-role.sh) so the Codex-specific parts of the contract — which fields
# are Codex-only, why plain stdout still works, what's unverified — are
# recorded at the seam that would need to change if Codex's contract diverges
# further, without touching the Claude Code hook or its wiring in
# .claude/settings.json.
#
# Contract: identical to agent-role.sh — always exits 0 (a role-tracking hook
# must never block a prompt), writes nothing but which role matched, never the
# prompt text.
set -uo pipefail

export AGENT_HOOK_RUNTIME=codex

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-role.sh"
