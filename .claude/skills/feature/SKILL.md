---
name: feature
description: >-
  Run a feature end to end in an isolated worktree: PRD, implementation, tests, and pull
  request. Use for substantial multi-file work that warrants its own branch and PRD. Do
  not use for a single-file fix (`/commit` directly), for generating one module's
  boilerplate (`/scaffold`), or before requirements are settled (`/brainstorm`).
---

# /feature

Full-cycle feature development: PRD creation, implementation, testing, and PR creation in an isolated worktree.

## Usage

```
/feature <feature_name> [options]
```

## Arguments

- `feature_name`: Name of the feature in kebab-case (e.g., `user-authentication`, `payment-processing`)

## Options

| Flag | Description |
|------|-------------|
| `--prd-only` | Only create the PRD, don't implement |
| `--skip-prd` | Skip PRD creation if one already exists |
| `--scaffold` | Generate CRUD scaffolding (routes, models, services) |
| `--with-db` | Include database model (requires `--scaffold`) |
| `--link-prd <number>` | Link to existing PRD branch instead of creating new |
| `--brainstorm` | Run `/brainstorm` before PRD creation to explore requirements |
| `--compound` | Run `/compound` after PR creation to capture learnings |

## Workflow

1. Read `prd/00_technology.md`, the relevant PRD and project rules. Name the requested outcome and reuse existing implementations. Use `--brainstorm` when requested; clarify only material missing requirements. Existing approval remains valid.
2. Use an isolated worktree and the repository's branch conventions. Preserve dirty work. Concurrent writers need exclusive files and independent test databases, ports, volumes and artifact tags; a worktree alone does not isolate these.
3. Reuse the existing PRD with `--skip-prd` or `--link-prd`; otherwise use `prd/_prd_template.md` for work that needs one. `--prd-only` ends with the PRD. Keep one authoritative issue or task record; link related documents to it.
4. Follow `CLAUDE.md` role routing: architect when shape is undecided, planner for cross-cutting sequencing. Resolve applicable ownership, retirement, rollback and early seam proof in `.claude/rules/delivery-contract.md` before broad implementation.
5. Implement the smallest complete outcome. `--scaffold` uses existing CRUD conventions; `--with-db` requires it and follows `.claude/rules/database-migrations.md`. Do not invent a platform rebuild or delete unrelated code to satisfy a simplification goal.
6. Follow `.claude/rules/testing.md` for TDD, affected tests, real seam evidence and required gates. Diagnose failures; do not hide them behind retries or widened timeouts. Run the mandatory independent judge after implementation and checks, then resolve P1/P2 findings.
7. Complete the authorized delivery: explicit-path commits and a PR when requested by the workflow; preserve local git/security policies. Use the existing PR template and delivery contract. Do not infer deployment or production authority. Lane agents follow their shared protocol for PR ownership and monitoring.
8. `--compound` captures useful reusable findings through the existing skill. Report changed behavior, proof, and remaining uncertainty without inventing productivity metrics.
