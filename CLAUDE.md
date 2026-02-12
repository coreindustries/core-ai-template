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
├── prd/
│   ├── 00_index.md            → Feature tracking, tech stack summary
│   ├── 00_technology.md       → TEMPLATE: technology choices + all commands
│   ├── _prd_template.md       → PRD template for new features
│   ├── _task_template.md      → Task tracking template
│   └── tasks/                 → Long-running feature progress tracking
├── .claude/rules/             → 8 auto-loaded rules (~6K tokens)
├── .claude/rules-available/   → 8 opt-in rules (symlink to enable)
├── .claude/references/        → On-demand references (loaded by skills)
├── .claude/skills/            → 18 slash commands (invoke with /name)
├── .claude/agents/            → 5 specialized agents (invoke on demand)
└── .claude/mcp.json           → MCP server configuration template
```

**Key**: `.claude/rules/*.md` files are **automatically loaded** into context — do not duplicate their content here. They are the **source of truth** for universal standards (code quality, testing, error handling, git workflow, security-core, AI agent patterns, quality checks, task management). Platform-specific rules live in `rules-available/` and must be symlinked into `rules/` to activate. Use `make enable-web`, `make enable-python`, `make enable-api`, `make enable-ios`, `make enable-android`, `make enable-mobile`, or `make enable-docker`.

## Commands

All commands come from `prd/00_technology.md`. Replace placeholders with your stack.

```bash
# Development
{start_dev_server}               # Start API with hot reload
{start_dependencies}             # Start database, cache, etc.

# Database
{db_generate}                    # Generate client after schema changes
{db_migrate}                     # Create/run migrations

# Quality (run before commits)
{lint_fix}                       # Lint and format
{type_check}                     # Type checking
{test_with_coverage}             # Tests with coverage

# Testing
{test_unit}                      # Unit tests only
{test_integration}               # Integration tests only
{test_specific} tests/unit/test_{module}  # Single test file
{test_stop_first}                # Stop on first failure
```

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
```

**Key patterns**: Database singleton, environment-based config, structured logging with separate audit logger, service-layer business logic.

## Skills (Slash Commands)

| Skill | Purpose |
|-------|---------|
| `/feature` | Full feature lifecycle: PRD → code → tests → PR (in worktree) |
| `/commit` | Conventional commit with Gitmoji |
| `/pr` | Create pull request |
| `/test` | Run tests with coverage |
| `/lint` | Lint, format, type check |
| `/refactor` | Safe refactoring with TDD approach |
| `/review` | Code review against project standards |
| `/debug` | Systematic debugging workflow |
| `/checkpoint` | Update task tracking file |
| `/hotfix` | Quick production patch |
| `/init` | Initialize new project from template |
| `/deps` | Audit and manage dependencies |
| `/scan` | Security scanning |
| `/migrate` | Database migrations |
| `/api` | Design REST/GraphQL endpoints |
| `/docs` | Generate documentation |
| `/onboard` | Guided walkthrough for new contributors |
| `/resume` | Recover context after session break |

## CI/CD

The active pipeline (`.github/workflows/ci.yml`) runs on push/PR to main with 5 gates: **Lint → Type Check → Test (66% coverage min) → Security → Build**. A generic template exists at `ci.yml.example`. See `.github/README.md` for customization.

## Context Recovery

When resuming after context compression, use `/resume` or follow manually:
1. Read `prd/00_index.md` → find "In Progress" features
2. Read `prd/tasks/{feature}_tasks.md` → load progress
3. Start from "Next Session Priorities"

## Template Setup

When using this template for a new project:
1. Fill in `prd/00_technology.md` with technology choices
2. Replace `{placeholder}` values in this file and `Makefile`
3. Update `prd/00_index.md` tech stack summary
4. Customize `.github/workflows/ci.yml` for your stack
5. Uncomment your stack in `.github/dependabot.yml`
6. Run `make setup` (installs deps, copies .env, configures git)
