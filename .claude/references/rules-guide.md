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

Every `.md` file in `.claude/rules/` without `paths:` frontmatter is loaded into Claude Code's context every session. These are kept lean to preserve context window for actual work.

| File | Purpose | ~Tokens |
|------|---------|---------|
| `ai-agent-patterns.md` | Autonomy, scope, delegation, failure recovery | 1,103 |
| `code-quality.md` | Simplest complete solution, DRY, naming | 1,119 |
| `delivery-contract.md` | Invariant, risk class, real proof | 1,594 |
| `error-handling.md` | Specific exceptions, no silent failures | 299 |
| `git-workflow.md` | Commit standards, dirty worktrees | 726 |
| `guardrails.md` | Agent safety boundaries | 880 |
| `quality-checks.md` | Pre-commit and CI expectations | 308 |
| `secrets-hygiene.md` | Never read, print or commit secrets | 792 |
| `security-core.md` | Secrets, database safety, dependencies | 687 |
| `task-management.md` | Task tracking, PRD workflow | 609 |

Path-scoped (`paths:` frontmatter) — loaded only when a matching file is read or edited:

| File | Purpose | ~Tokens |
|------|---------|---------|
| `claude-api.md` | Claude API defaults | 284 |
| `database-migrations.md` | Migration safety | 2,608 |
| `dependency-security.md` | Pinning, audits, lockfiles | 2,336 |
| `node-error-handling.md` | Process-level Node handlers, timers | 539 |
| `runtime-confirmation.md` | Prove the feature fires in the running system | 435 |
| `testing.md` | Tests that prove something | 1,812 |
| `ui-qa-gate.md` | User-visible output reaches the user | 379 |

Rationale, long examples and incident detail for a rule live in `.claude/references/<rule>-detail.md`, read on demand.

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
| Node.js API (`enable-api`) | ~9.5K tokens | 4.8% |
| Python API (`enable-python`) | ~13K tokens | 6.6% |
| React Native (`enable-mobile`) | ~16.5K tokens | 8.3% |
| Next.js Web (`enable-web`) | ~20K tokens | 10.1% |

Always-loaded universal rules only (path-scoped rules and CLAUDE.md excluded), ~4 chars/token.

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
- `prd/00_technology.md` - Technology stack and commands
