# AI Agent Development Patterns

**Scope:** Project-specific agent behavior. Claude API defaults live in `claude-api.md` (path-scoped). Examples and decision trees: `.claude/references/ai-agent-patterns-detail.md`.

## Autonomy

Operate end-to-end: gather context, implement, verify, and explain in one pass. Deliver working code, not only a plan. Pause only if explicitly redirected or truly blocked on missing external information.

## Bias to Action

Default to implementation over clarification. Implement when requirements are reasonably clear, patterns exist in the codebase, or missing details can be inferred; pick the most standard approach. Ask only for (a) architectural decisions with significant tradeoffs, (b) conflicting requirements, (c) inputs that cannot be inferred and matter significantly.

## Correctness Over Speed

Fix root causes, not symptoms. Read enough context and follow existing patterns before changing files. No speculative changes or hacks to get code working; consider edge cases and error paths; write production-ready code. Never hardcode a model id in code, config, scripts or docs; read it from env/config (Claude API call shape: `claude-api.md`).

## Comprehensiveness

Cover every relevant surface (schema, migration, model, service, API, tests, audit log), not just the first one.

## Behavior-Safe Defaults

- Don't change existing behavior without explicit request.
- Gate intentional behavior changes with a feature flag or a new parameter with a safe default.
- Add tests when behavior shifts; note the change in the commit message.

## Delegating to Subagents

Handle direct lookups and routine edits locally; delegate concrete independent work when useful. Follow CLAUDE.md role routing, including mandatory judge review, and the active runtime capacity. Claude Code uses the configured model tiers and explicit `model:` on built-in agents; Codex follows `docs/codex.md`. Keep compact evidence rather than file dumps.

**Every brief states:** the goal and the invariant; the files the agent owns versus may only read; its worktree path; "use negative controls for material regressions per `.claude/rules/testing.md`"; and "report in ≤400 words with `file:line`, no file dumps".

**Isolation for code-writing subagents.** The failure to prevent is an *isolation leak*: a subagent editing the parent's worktree instead of its own.

1. **Classify first.** Operational tasks (probes, queries, deploy checks) make no repo edits and need no worktree. Only code-editing tasks get one.
2. **Don't nest isolation.** From inside a worktree session, do not spawn an `isolation: "worktree"` subagent. Create a dedicated worktree (`git worktree add`) with disjoint file ownership and pass the subagent that path.
3. **Make the subagent confirm where it is.** Its first step is `pwd && git rev-parse --show-toplevel`, and it refuses to edit if that is not the worktree you gave it.
4. **Verify within seconds of spawning.** `git -C <their-worktree> status` shows their changes; your own `git status` stays clean. Don't trust the isolation label alone.
5. **Treat an unexpected "file X was modified" as a leak** and investigate before continuing.
6. **Commit your own work before you fan out**, staging explicit paths, never `git add -A`.

Recovery if a leak happens: commit or stash the leaked changes under a unique tag, restore your worktree to its HEAD, create a fresh worktree for the subagent's work, and reapply there. Committed and pushed work is always safe; only working trees leak.

## Failure Modes and Recovery

- **Loop detection:** edited the same file >3 times without tests improving or the problem resolving → STOP. Write a diagnosis (tried, expected, actual) to the task file (`prd/tasks/`) and surface it to the user.
- **Partial state risk:** before any operation touching >5 files or migrations/schema: run `/checkpoint`, create a commit or stash as a recovery point. If it fails mid-way, report exactly what was and wasn't applied; never leave the codebase half-modified undocumented.
- **Context drift:** when unsure your understanding matches the task, re-read the task file (`prd/tasks/`) and relevant ADRs (`docs/decisions/`); don't continue from memory after long sessions. Resume from the authoritative issue/PR or task file; create a task file only when it is the chosen progress owner.
- **Max iterations:** implicit 10-iteration limit. If not converged: stop, summarize what you tried / what failed / what you need, and ask for a decision. Don't retry the same approach.
