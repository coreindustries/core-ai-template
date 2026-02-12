# Rules System Guide

This guide explains how the rules system works in this template. It is a **reference document** — not auto-loaded into context.

## Architecture

```
.claude/
├── rules/                  # Auto-loaded (~6K tokens) - universal rules
├── rules-available/        # Opt-in - symlink into rules/ to activate
└── references/             # On-demand - loaded by skills when needed
```

### Auto-Loaded Rules (`rules/`)

All `.md` files in `.claude/rules/` are automatically loaded into Claude Code's context every session. These are kept lean to preserve context window for actual work.

| File | Purpose | ~Tokens |
|------|---------|---------|
| `code-quality.md` | DRY, typing, naming, docs | 785 |
| `testing.md` | Unit/integration tests, TDD, coverage | 424 |
| `ai-agent-patterns.md` | Autonomy, persistence, exploration | 1,212 |
| `error-handling.md` | Specific exceptions, tight handling | 474 |
| `git-workflow.md` | Commit standards, dirty worktrees | 564 |
| `quality-checks.md` | Frequent checks, pre-commit, CI/CD | 480 |
| `task-management.md` | Task tracking, PRD workflow | 732 |
| `security-core.md` | Secrets, database safety, dependencies | 1,659 |

### Opt-In Rules (`rules-available/`)

Platform-specific rules that only apply to certain project types. Enable by symlinking into `rules/`:

```bash
# Or use presets:
make enable-web      # Next.js / React
make enable-api      # Backend API
make enable-mobile   # React Native
make enable-python   # Python (uv, ruff, FastAPI)
make enable-ios      # Native iOS
make enable-android  # Native Android
make enable-docker   # Dockerized projects
```

| File | For | ~Tokens |
|------|-----|---------|
| `nextjs.md` | Next.js 16+ web apps | 7,776 |
| `security-web.md` | React / Next.js web apps | 2,935 |
| `security-mobile.md` | React Native mobile apps | 4,028 |
| `security-owasp.md` | OWASP Top 10 (any web/API) | 1,389 |
| `android.md` | Native Android (Kotlin / Compose) | ~3,800 |
| `docker.md` | Dockerized / containerized projects | ~3,500 |
| `ios.md` | Native iOS (Swift / SwiftUI) | ~3,200 |
| `python.md` | Python (uv, ruff, FastAPI) | ~4,200 |

### References (`references/`)

Lookup tables and documentation loaded on-demand by skills:

| File | Loaded By |
|------|-----------|
| `gitmoji.md` | `/commit` skill |
| `rules-guide.md` | This file (human reference) |

## Context Budget

| Project Type | Auto-Loaded | % of 200K Window |
|--------------|-------------|-------------------|
| Python API | ~7.7K tokens | 3.9% |
| Node.js API | ~7.7K tokens | 3.9% |
| Next.js Web | ~17K tokens | 8.5% |
| React Native | ~13.3K tokens | 6.7% |

## How to Add Rules

**Universal rule** (all projects):
1. Create `.md` file in `.claude/rules/`
2. Keep it concise — every token auto-loads every session

**Platform rule** (specific projects):
1. Create `.md` file in `.claude/rules-available/`
2. Add a `make enable-*` target if it fits a preset
3. Document in this file

## Rule Loading Precedence (Claude Code)

1. **Managed Policy** (organization-wide)
2. **User-Level Rules** (`~/.claude/rules/`)
3. **Project Main** (`CLAUDE.md`)
4. **Project Rules** (`.claude/rules/*.md`)
5. **Skills** (`.claude/skills/*.md` - invoked on demand)
6. **Agents** (`.claude/agents/*.md` - invoked on demand)

## See Also

- `CLAUDE.md` - Main project instructions
- `.cursorrules` - Cursor IDE rules
- `prd/02_Tech_stack.md` - Technology stack and commands
