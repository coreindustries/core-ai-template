---
name: review
description: >-
  Multi-perspective code review (P1/P2/P3) for Cursor: inline checklists plus three
  parallel Task subagents (perf-auditor, security-reviewer, simplicity-reviewer with
  combined data-integrity prompt). Use when the user invokes /review, asks for a PR
  review, or wants repo-standard findings with severity.
---

# /review (Cursor)

This repository keeps **one canonical specification** for both IDEs:

**→ [Canonical /review skill](../../../.claude/skills/review/SKILL.md)** (path from repo root: `.claude/skills/review/SKILL.md`)

Follow that file end-to-end. When a step offers **Cursor** vs **Claude Code**, use **Cursor**.

### Cursor quick reference

| Step | What to use |
|------|-------------|
| **Diff** | `gh pr diff`, `git diff`, defaults from canonical skill |
| **Specialists** | Three parallel `Task` calls: `perf-auditor`, `security-reviewer`, `simplicity-reviewer` (third prompt includes **both** simplicity and data-integrity checks — see Step 3 in canonical skill) |
| **Read-only review** | `readonly: true` on each `Task` if you must not modify files |
| **Open PR after `--fix`** | `gh pr create` or the workspace PR tool; avoid hardcoding GitHub MCP names unless that MCP is actually connected |

If Cursor cannot resolve the relative link above, open `.claude/skills/review/SKILL.md` from the repository root.
