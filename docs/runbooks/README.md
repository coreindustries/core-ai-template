# Runbooks

Operational procedures — what to do, in order, under pressure.

## When to add a runbook here

Write a runbook when a sequence of steps:

- Runs repeatedly (every deploy, every secret rotation, every incident class)
- Must run in a **specific order** to be safe (rotate before revoke, migrate before deploy)
- Has **time pressure** (an incident, a production cutover)
- Is **error-prone from memory** (multi-tool invocations, sequenced CLI commands)

If it's a one-off or a decision, it belongs elsewhere (see below).

## How runbooks differ from adjacent doc types

| Type | Lives in | Answers | Immutable? |
|---|---|---|---|
| **Runbook** | `docs/runbooks/` | *What do I run, in what order, right now?* | No — update as tooling evolves |
| **ADR** | `docs/decisions/` | *Why did we choose this approach over alternatives?* | Yes — superseded, not edited |
| **Solution** | `docs/solutions/` | *We hit this problem and solved it like this.* | Yes — append new entries, don't rewrite |
| **Rule** | `.claude/rules/` | *What are the invariants agents must follow?* | Rarely — changing a rule is a governance event |
| **PRD** | `prd/` | *What are we building and why?* | Until shipped, then archived |

A runbook can link to any of the above (e.g., a deployment runbook links to the ADR that chose the deployment target). The reverse is usually wrong — an ADR that embeds a step-by-step procedure will rot.

## Structure of a runbook

Every runbook should open with:

1. **Trigger** — the one-line condition under which you run it.
2. **Time target** — how fast this should complete (e.g., "rotation within 60 minutes").
3. **Prerequisites** — what tools, credentials, or access you need before starting.

Then the body, in strict time order:

- Labeled phases with elapsed-time markers (`First 5 minutes — contain`, `Next 30 minutes — rotate`).
- Copy-pasteable commands in fenced blocks. No `{placeholder}` tokens unless explicitly flagged.
- Anti-patterns at the end (`## What NOT to do`) — the common wrong turns under pressure.

## Current runbooks

- [`dev-to-prod-pipeline.md`](dev-to-prod-pipeline.md) — staged validation from local change to production deploy.
- [`multi-agent-worktrees.md`](multi-agent-worktrees.md) — running multiple agents in parallel on isolated branches via git worktrees.
- [`secret-leak.md`](secret-leak.md) — discovered a plaintext credential; contain, rotate, audit.

## Adding a new runbook

1. Copy the structure of `secret-leak.md`.
2. Name the file for the triggering event, not the solution (`database-restore.md`, not `how-we-back-up.md`).
3. Link it from this README.
4. If the runbook exists because of a real incident, file the incident report under `docs/incidents/YYYY-MM-DD-<slug>.md` — runbooks reference incidents; they don't replace them.
