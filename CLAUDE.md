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
├── scripts/                   → Utility scripts (scan-secrets.sh)
├── .gitleaks.toml             → Secret & PII scanning config (gitleaks)
├── prd/
│   ├── 00_index.md            → Feature tracking, tech stack summary
│   ├── 00_technology.md       → TEMPLATE: technology choices + all commands
│   ├── _prd_template.md       → PRD template for new features
│   ├── _task_template.md      → Task tracking template
│   ├── _changelog_template.md → Changelog with breaking change policy
│   └── tasks/                 → Long-running feature progress tracking
├── .claude/rules/             → 8 auto-loaded rules (~6K tokens)
├── .claude/rules-available/   → 8 opt-in rules (symlink to enable)
├── .claude/references/        → On-demand references (loaded by skills)
├── .claude/skills/            → 27 slash commands (invoke with /name)
├── .claude/agents/            → 8 specialized agents (invoke on demand)
└── .claude/mcp.json           → MCP server configuration template
```

**Key**: `.claude/rules/*.md` files are **automatically loaded** into context — do not duplicate their content here. They are the **source of truth** for universal standards (code quality, testing, error handling, git workflow, security-core, AI agent patterns, quality checks, task management). Platform-specific rules live in `rules-available/` and must be symlinked into `rules/` to activate. Use `make enable-web`, `make enable-python`, `make enable-api`, `make enable-ios`, `make enable-android`, `make enable-mobile`, or `make enable-docker`.

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
└── solutions/                   # Knowledge capture from /compound skill
```

**Key patterns**: Database singleton, environment-based config, structured logging with separate audit logger, service-layer business logic.

## Skills (Slash Commands)

27 skills available in `.claude/skills/`. Each is auto-discovered from its `SKILL.md` frontmatter — invoke with `/name`. See README.md for the full catalog with descriptions.

## CI/CD

The active pipeline (`.github/workflows/ci.yml`) runs on push/PR to main with 5 gates: **Lint → Type Check → Test (66% coverage min) → Security → Build**. A generic template exists at `ci.yml.example`. See `.github/README.md` for customization.

## Context Recovery

When resuming after context compression, use `/resume` or follow manually:
1. Read `prd/00_index.md` → find "In Progress" features
2. Read `prd/tasks/{feature}_tasks.md` → load progress
3. Start from "Next Session Priorities"

## Template Setup

See README.md "Getting Started" for the full 7-step setup. Key steps: fill in `prd/00_technology.md`, replace `{placeholder}` values, enable platform rules (`make enable-*`), run `make setup`.
