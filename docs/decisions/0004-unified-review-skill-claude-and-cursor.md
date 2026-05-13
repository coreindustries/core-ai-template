# 0004 — Unified `/review` skill for Claude Code and Cursor

- **Date:** 2026-05-13
- **Status:** Accepted
- **Deciders:** Core team

## Context and Problem Statement

The `.claude/skills/review` workflow assumed **Claude Code** primitives only: parallel `Agent` calls with explicit `haiku` / `sonnet` models and GitHub MCP tools for diffs and PR creation. **Cursor** uses the `Task` tool with `subagent_type` labels, default subagent models, and often **no** GitHub MCP. Agents following the old skill in Cursor issued the wrong tools and could not fetch PR diffs reliably.

## Decision Drivers

- Keep a **single** P1/P2/P3 rubric and checklists for every agent, regardless of IDE.
- Avoid **drift** between two full copies of the same skill.
- Ensure **diff and PR steps** work when GitHub MCP is absent (`gh`, `git`, workspace PR tooling).

## Considered Options

1. **Leave the skill Claude-only** and let Cursor users improvise (rejected: inconsistent reviews and repeated confusion).
2. **Duplicate the entire skill** under `.cursor/skills/review/` (rejected: two bodies to maintain; guaranteed drift).
3. **One canonical skill** with explicit Claude vs Cursor steps, plus a **thin Cursor wrapper** that links to it (chosen).

## Decision Outcome

Chosen option: **(3) Canonical skill + Cursor wrapper**.

1. **Single canonical specification** at `.claude/skills/review/SKILL.md` documenting both runtimes: shared Steps 2, 4, 6; **Step 1** via GitHub MCP when present **or** `gh pr diff` / `git`; **Step 3** via Claude `Agent` blocks **or** three parallel Cursor `Task` calls (`perf-auditor`, `security-reviewer`, `simplicity-reviewer` with combined simplicity + data-integrity prompt on the third); **Step 5** via MCP **or** `gh pr create` / workspace PR tooling.
2. **Cursor entry** at `.cursor/skills/review/SKILL.md` linking to the canonical file.

### Positive Consequences

- Same severity rubric and checklists in Claude Code and Cursor.
- PR review works without GitHub MCP when `gh` and repo remotes are available.

### Negative Consequences

- The skill file is longer; Step 3 must be updated in two subsections when review strategy changes.

## References

- Canonical skill: [.claude/skills/review/SKILL.md](../../.claude/skills/review/SKILL.md)
- Cursor entry: [.cursor/skills/review/SKILL.md](../../.cursor/skills/review/SKILL.md)
