# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

This is a **project template** for AI agent-assisted development. There is no `src/` or `tests/` directory yet — those are created when the template is used for a specific project. The first step for any new project is filling in `prd/00_technology.md` with technology choices, then replacing `{placeholder}` commands throughout.

## Document Hierarchy

Understanding how the pieces fit together is critical:

```
CLAUDE.md (this file)          → Top-level guidance, commands, architecture
├── CONTRIBUTING.md            → Contributor workflow and standards
├── Makefile                   → One-command setup, dev, test, quality
├── scripts/                   → Utility scripts (scan-secrets.sh, statusline/)
├── .gitleaks.toml             → Secret & PII scanning config (gitleaks)
├── prd/
│   ├── 00_index.md            → Feature tracking, tech stack summary
│   ├── 00_technology.md       → TEMPLATE: technology choices + all commands
│   ├── _prd_template.md       → PRD template for new features
│   ├── _task_template.md      → Task tracking template
│   ├── _changelog_template.md → Changelog with breaking change policy
│   └── tasks/                 → Long-running feature progress tracking
├── docs/
│   ├── adopt-best-practices.md → Self-contained kit to land into ANY existing repo
│   ├── decisions/              → ADRs: read before proposing architectural changes
│   ├── coordination/           → Cross-repo coordination tracking (incoming/outgoing)
│   └── solutions/              → Knowledge capture from /compound skill
├── .claude/rules/             → 9 auto-loaded rules (~7K tokens)
├── .claude/rules-available/   → 8 opt-in rules (symlink to enable)
├── .claude/references/        → On-demand references (loaded by skills)
├── .claude/skills/            → 30 slash commands (invoke with /name)
├── .claude/agents/            → 10 specialized agents (see _template.md for structure)
└── .claude/mcp.json           → MCP server configuration template
```

**Key**: `.claude/rules/*.md` files are **automatically loaded** into context — do not duplicate their content here. They are the **source of truth** for universal standards (code quality, testing, error handling, git workflow, security-core, AI agent patterns, quality checks, task management, guardrails). Platform-specific rules live in `rules-available/` and must be symlinked into `rules/` to activate. Use `make enable-web`, `make enable-python`, `make enable-api`, `make enable-ios`, `make enable-android`, `make enable-mobile`, or `make enable-docker`.

## Commands

All commands are defined in `prd/00_technology.md` and wrapped by `Makefile`. Run `make help` for the full list. Key targets:

```bash
make setup          # First-time project setup
make dev            # Start development server
make test           # Run all tests
make quality        # Full pipeline: lint + typecheck + security + secrets + tests
make scan-secrets   # Secret & PII scanning (gitleaks)
```

For individual commands (`{lint_fix}`, `{test_unit}`, etc.), see `prd/00_technology.md`.

## Architecture

**Directory structure** (after project setup):
```
src/{project_name}/              # Source code
├── api/                         # Routes (thin — delegate to services)
├── services/                    # Business logic
├── models/                      # Request/response schemas
├── db/                          # Database singleton + utilities
└── logging/                     # Structured + audit logging
tests/
├── unit/                        # No I/O, mock externals
└── integration/                 # Real database, use fixtures
docs/
├── decisions/                   # ADRs (read before proposing architecture changes)
└── solutions/                   # Knowledge capture from /compound skill
```

**Key patterns**: Database singleton, environment-based config, structured logging with separate audit logger, service-layer business logic.

## Architectural Decisions

Before proposing changes to project architecture, patterns, or dependencies, check `docs/decisions/` for existing ADRs. These document why current patterns exist and what must not change. Run `/adr` to capture new decisions.

## Agent Routing

**Default model:** `claude-sonnet-4-6` (set in `.claude/settings.json`). Opus is reserved for `planner` and `judge` only — do not override other agents upward to Opus.

**Opus routing — use these two agents, nothing else:**
- **`planner` agent** — invoke before implementing any task that touches more than two modules, involves schema changes, or has non-obvious sequencing. Produces a concrete step-by-step plan with file paths. Do NOT invoke for single-file changes.
- **`judge` agent** — invoke after completing significant work (new feature, cross-cutting change, security-sensitive code) and before the final commit. Produces P1/P2/P3 findings with `file:line` citations. Skip for trivial one-line fixes.

**Subagent cost discipline:**
- For lookups (find X / grep Z / list files): use `Grep`/`Glob`/`Read` directly or the `codebase-researcher` agent (read-only). Do NOT use `general-purpose` for lookups.
- For multi-file research where reasoning matters, use `Explore` (built-in) or pass `model: "sonnet"` to `Agent`.
- **Project agents** (`.claude/agents/`) have their models pinned in frontmatter — do not override upward unless using `planner` or `judge`.

## PR / Issue Labels

The canonical label set lives in `.github/labels.yml` and is reconciled with the live repo by `.github/workflows/labels-sync.yml`. Path-based area labels (`area/python`, `area/database`, etc.) are auto-applied by `.github/workflows/labeler.yml` based on `.github/labeler.yml` rules.

When opening a PR, apply at minimum:
- One **type** label (`feature`, `bug`, `docs`, `chore`, `refactor`, `test`, `performance`, `security`, `breaking`).
- One **priority** label if not P3 default.
- `codex` if requesting cross-model review.

The PR template includes a Labels checklist.

## Cross-Repo Coordination

When work crosses a repository boundary (a schema change in another repo blocks shipping here, an ops task another team must complete first, etc.), open a coordination doc under `docs/coordination/` rather than rely on chat. See `docs/coordination/README.md` for the lifecycle and frontmatter schema, and `_template.md` for the blank.

Don't open a coordination doc for inside-one-repo work — issues and PRs are the right tool there.

## Adopt Into Any Existing Repo

`docs/adopt-best-practices.md` is a **self-contained markdown file** that any Claude Code (or compatible) agent can use to land this template's tooling discipline into another existing repo. Hand it to the agent in the target repo; it inlines all hook scripts, configs, workflows, and document templates so no external fetches are needed.

Use cases: onboarding an existing repo to the kit's secret-scan / commit / PR-template / ADR / PRD / coordination workflows in one PR.

## Skills (Slash Commands)

30 skills available in `.claude/skills/`. Each is auto-discovered from its `SKILL.md` frontmatter — invoke with `/name`. See README.md for the full catalog with descriptions.

## CI/CD

The active pipeline (`.github/workflows/ci.yml`) runs on push/PR to main with 5 gates: **Lint → Type Check → Test (66% coverage min) → Security → Build**. A generic template exists at `ci.yml.example`. See `.github/README.md` for customization.

## Context Recovery

When resuming after context compression, use `/resume` or follow manually:
1. Read `prd/00_index.md` → find "In Progress" features
2. Read `prd/tasks/{feature}_tasks.md` → load progress
3. Start from "Next Session Priorities"

## Template Setup

See README.md "Getting Started" for the full 7-step setup. Key steps: fill in `prd/00_technology.md`, replace `{placeholder}` values, enable platform rules (`make enable-*`), run `make setup`.

## Current State
<!-- MACHINE UPDATED — do not edit manually -->
<!-- Last updated by: claude on 2026-05-22 -->

**Active feature:** none — PRD-05 implementation complete
**Last action:** implemented all 5 phases of PRD-05 autonomous dev workflow
**Blockers:** none
**Next action:** review and merge PR for PRD-05
**Worktree:** worktree-feat+prd-05-autonomous-dev-workflow
