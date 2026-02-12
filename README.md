# Core AI Template

A template for starting agentic-based software projects. Provides structure, documentation patterns, and workflows optimized for AI-assisted development with tools like Claude Code, Cursor, and similar AI coding assistants.

## Purpose

This template establishes a foundation for projects where AI agents are primary contributors to the codebase. It includes:

- **Structured guidance** for AI agents via `CLAUDE.md`
- **Product requirements documentation** (PRD) for maintaining project context
- **Task tracking** for long-running features and session recovery
- **Reusable skills** (slash commands) for common development workflows
- **Compound engineering** practices adapted from [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) — knowledge capture, requirements discovery, and multi-perspective code review

## Features

### Context-Optimized Rules System
- `.claude/rules/` - 8 universal rules, auto-loaded (~6K tokens)
- `.claude/rules-available/` - 8 platform rules, opt-in via `make enable-*`
- `.claude/references/` - On-demand lookups, loaded by skills when needed
- Only loads what your project needs — **65-70% less context waste** vs loading everything

### AI Agent Guidance
- `CLAUDE.md` - Project-level instructions and coding standards
- `.claude/agents/` - 8 specialized agents (code review, architecture, testing, performance, security, simplicity, data integrity, codebase research)
- `.claude/skills/` - 26 slash commands for common workflows
- `.claude/mcp.json` - MCP server configuration template

### Documentation & Standards
- `.claude/rules/` + `.claude/rules-available/` - Source of truth for all standards
- `prd/00_technology.md` - Technology stack template (customize per project)
- `CONTRIBUTING.md` - Contributor guide with workflow, standards, and AI skill usage

### Task Management
- `prd/tasks/` - Directory for feature task tracking
- `_task_template.md` - Template for progress tracking and context recovery
- `/resume` skill - Automated session recovery after context compression

### Developer Experience
- `Makefile` - One-command setup, dev, test, quality checks
- `.editorconfig` - Cross-IDE formatting consistency
- `.vscode/` - VS Code settings, extensions, debug configurations
- `.devcontainer/` - Reproducible dev environments (Codespaces-ready)
- `.husky/` - Pre-commit hooks (lint-staged + commitlint)
- `.github/dependabot.yml` - Automated dependency updates

### Skills (Slash Commands)

**Development**
| Skill | Purpose |
|-------|---------|
| `/feature` | Full feature lifecycle (PRD → code → tests → PR) |
| `/test` | Run tests with coverage |
| `/lint` | Run linting, formatting, type checking |
| `/refactor` | Safely refactor code with tests |
| `/review` | Code review against standards |
| `/debug` | Systematic debugging workflow |
| `/api` | Design REST/GraphQL endpoints |

**Git & Workflow**
| Skill | Purpose |
|-------|---------|
| `/commit` | Create conventional commits |
| `/pr` | Create pull requests with descriptions |
| `/hotfix` | Quick patch for production issues |
| `/checkpoint` | Save progress to task file |

**Project & Infrastructure**
| Skill | Purpose |
|-------|---------|
| `/init` | Initialize new project with boilerplate |
| `/scaffold` | Generate new module/component/screen with tests |
| `/deps` | Audit and manage dependencies |
| `/env` | Validate, generate, and sync environment variables |
| `/scan` | Run security scans |
| `/migrate` | Manage database migrations |
| `/ci` | Generate or update CI/CD pipeline configuration |
| `/release` | Tag version, generate changelog, create GitHub release |
| `/deploy` | Deploy to staging or production |
| `/perf` | Profile, benchmark, and optimize performance |
| `/docs` | Generate documentation |
| `/onboard` | Guided walkthrough for new contributors |
| `/resume` | Recover context and resume work after session break |

**Knowledge & Discovery**
| Skill | Purpose |
|-------|---------|
| `/compound` | Capture knowledge from solved problems to docs/solutions/ |
| `/brainstorm` | Explore requirements (WHAT) before implementation (HOW) |

### Compound Engineering

Adapted from [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin), this template implements key compound engineering practices that make AI agents more effective over time. The core idea: **knowledge should compound, not evaporate between sessions.**

#### `/brainstorm` — Requirements Before Code

Separates WHAT from HOW. Before writing any code, explore what the user actually needs.

```bash
# Explore requirements for a new feature
/brainstorm user-notifications

# Use with /feature for the full lifecycle
/feature user-notifications --brainstorm
```

**How it works:**
1. Asks up to 5 probing questions (one at a time) to understand the real need
2. Explores: core requirements, UX expectations, edge cases, boundaries
3. Produces a focused ~200-300 word requirements doc (Must Have / Should Have / Out of Scope / Success Criteria)
4. Hands off cleanly to `/feature` when ready

**When to use:** Before any feature where requirements are ambiguous. Skip it for straightforward CRUD or well-specified tasks.

#### `/compound` — Knowledge Capture

After solving a non-trivial problem, capture the knowledge so it's never lost. Creates searchable solution documents in `docs/solutions/`.

```bash
# Capture knowledge from the current debug session
/compound

# Specify category explicitly
/compound --category database

# Extract from a specific commit
/compound --from-commit abc1234

# Use with /feature to auto-capture after PR
/feature payment-processing --compound
```

**How it works:**
1. Gathers problem context from the current session (error, root cause, failed attempts, working solution)
2. Checks `docs/solutions/` for duplicates before writing
3. Creates a solution document with YAML frontmatter (title, category, date, tags, severity)
4. Files are organized by category: `docs/solutions/{category}/{date}-{slug}.md`

**Categories:** `build-errors`, `test-failures`, `runtime-errors`, `performance`, `database`, `security`, `integration`, `deployment`, `logic-errors`

**When to use:** After any fix that took > 15 minutes, required a non-obvious workaround, or involved reading external docs. The `/debug` skill will suggest it automatically after non-trivial fixes.

#### Multi-Perspective `/review`

Code review now evaluates from 6 specialist perspectives with P1/P2/P3 severity classification:

```bash
/review --pr feat/user-auth
```

| Perspective | What It Checks | Agent |
|-------------|---------------|-------|
| Code Quality | Types, docs, DRY, error handling, completeness | Inline (rules) |
| Security | Secrets, injection, auth, audit logging | `security-reviewer` |
| Performance | N+1 queries, indexing, caching, pagination | `perf-auditor` |
| Architecture | Project patterns, separation of concerns | Inline (rules) |
| Simplicity | Over-engineering, unnecessary abstractions | `simplicity-reviewer` |
| Data Integrity | Validation, DB constraints, migration safety | `data-integrity-reviewer` |

Output includes a summary table showing findings per perspective and all issues classified as P1 (must fix), P2 (should fix), or P3 (suggestion).

#### New Agents

Three new specialized agents support compound engineering:

| Agent | Purpose |
|-------|---------|
| `simplicity-reviewer` | Detects unnecessary abstractions, over-engineering, and right-sizing violations |
| `data-integrity-reviewer` | Catches validation gaps, migration risks, and state transition bugs |
| `codebase-researcher` | Deep codebase analysis before implementing — finds patterns, prior art, and reusable code |

These agents are on-demand only (0 auto-loaded token cost). They're invoked by `/review` or can be used directly.

## Workflow

1. **Start a feature** - Create a task file in `prd/tasks/` using the template
2. **Develop with AI** - Use skills and agent guidance for consistent output
3. **Track progress** - Run `/checkpoint` every 30-60 minutes
4. **Review and test** - Use `/review`, `/test`, and `/lint` before commits
5. **Recover context** - Task files enable session resumption

## Getting Started

### Step 1: Copy Template (1 minute)

```bash
cp -r core-ai-template my-project
cd my-project
git init
git add .
git commit -m "chore: initial project setup"
```

### Step 2: Configure Tech Stack (3 minutes)

Edit `prd/00_technology.md` with your technology choices. See examples below (Python, TypeScript, Go).

**Minimum Required Sections:**
- Language & Runtime (Section 1)
- Package Manager (Section 1.2)
- Database (Section 2)
- ORM (Section 3)
- API Framework (Section 4)
- Testing (Section 8)
- Code Quality Tools (Section 9)

### Step 3: Update Project Commands (2 minutes)

Edit `CLAUDE.md` and replace placeholders:
- `{package_manager}` → `uv` / `bun` / `pnpm` / etc.
- `{runner}` → `uv run` / `bun` / `pnpm exec` / etc.
- `{start_dev_server}` → your dev server command

### Step 4: Enable Platform Rules (1 minute)

```bash
# Pick one (or combine) based on your project type:
make enable-web      # Next.js / React web app
make enable-python   # Python (uv, ruff, FastAPI)
make enable-api      # Backend API (any stack, minimal)
make enable-ios      # Native iOS (Swift / SwiftUI)
make enable-android  # Native Android (Kotlin / Compose)
make enable-mobile   # React Native mobile app
make enable-docker   # Dockerized / containerized project
```

This symlinks platform-specific rules into `.claude/rules/` so they auto-load. See `.claude/references/rules-guide.md` for details.

### Step 5: Run Setup (1 minute)

```bash
make setup
# This copies .env, installs dependencies, generates DB client, configures git
```

### Step 6: Set Up CI/CD (2 minutes)

```bash
cp .github/workflows/ci.yml.example .github/workflows/ci.yml
# Edit ci.yml and replace {placeholders} with your commands
# Uncomment your stack in .github/dependabot.yml
```

See [`.github/workflows/README.md`](.github/workflows/README.md) for detailed setup.

### Step 7: Start Building (5 minutes)

```bash
# Create task file for your first feature
cp prd/_task_template.md prd/tasks/my-feature_tasks.md

# Create feature branch
git checkout -b feat/my-feature

# Scaffold feature (in AI coding assistant)
/feature my-feature --scaffold --with-api --with-tests

# Run quality checks
/lint --fix
/test --coverage

# Save progress
/checkpoint
```

**Total Setup Time:** ~15 minutes

## Tech Stack Examples

Copy one of these configurations into `prd/00_technology.md` as a starting point.

### Python

| Component | Choice |
|-----------|--------|
| Language | Python 3.13+ |
| Package Manager | uv |
| Framework | FastAPI |
| ORM | Prisma |
| Database | PostgreSQL (Docker) |

| Category | Tools |
|----------|-------|
| Testing | pytest, pytest-cov, pytest-asyncio |
| Linting | ruff (linting + formatting) |
| Type Checking | mypy |
| Security | bandit, safety, pip-audit |

**Common Commands:**
```bash
# Package management
uv sync                          # Install dependencies
uv add <package>                 # Add package

# Database
uv run prisma generate           # Generate Prisma client
uv run prisma migrate dev        # Run migrations
docker compose up -d             # Start PostgreSQL

# Testing
uv run pytest                    # Run tests
uv run pytest --cov=src          # Run with coverage
uv run pytest -x                 # Stop on first failure

# Linting & formatting
uv run ruff check --fix .        # Lint and fix
uv run ruff format .             # Format code
uv run mypy .                    # Type check

# Security scanning
uv run bandit -r src/            # Static security analysis
uv run pip-audit                 # Dependency vulnerabilities
uv run safety check              # Known vulnerability check
```

### Node.js / TypeScript

| Component | Choice |
|-----------|--------|
| Language | TypeScript 5.x |
| Runtime | Node.js 22+ or Bun |
| Package Manager | Bun |
| Framework | Hono or Express |
| ORM | Drizzle |
| Database | PostgreSQL (Docker) |

| Category | Tools |
|----------|-------|
| Testing | Vitest, @testing-library, supertest |
| Linting | ESLint, Prettier, typescript-eslint |
| Type Checking | tsc (TypeScript compiler) |
| Security | npm-audit, snyk, eslint-plugin-security |

**Common Commands:**
```bash
# Package management
bun install                      # Install dependencies
bun add <package>                # Add package

# Database
bun run drizzle-kit generate     # Generate migrations
bun run drizzle-kit migrate      # Run migrations
docker compose up -d             # Start PostgreSQL

# Testing
bun test                         # Run tests
bun test --coverage              # Run with coverage
bun test --bail                  # Stop on first failure

# Linting & formatting
bun run lint --fix               # Lint and fix
bun run format                   # Format with Prettier
bun run typecheck                # Type check (tsc --noEmit)

# Security scanning
bun audit                        # Dependency vulnerabilities
bunx snyk test                   # Snyk security scan
bun run lint:security            # ESLint security rules
```

### Docker Compose (Shared)

Both stacks can use a common `docker-compose.yml` for local development:

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: app
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Directory Structure

```
core-ai-template/
├── README.md                    # This file - project overview
├── CLAUDE.md                    # AI agent project guidance
├── CONTRIBUTING.md              # Contributor guide and workflow
├── Makefile                     # One-command setup, dev, test, quality
├── .editorconfig                # Cross-IDE formatting consistency
├── .env.example                 # Environment variable template
├── .gitmessage                  # Git commit message template
├── .cursorrules                 # Cursor IDE rules
├── .commitlintrc.json           # Commit message linting config
├── .lintstagedrc.json           # Pre-commit lint-staged config
├── .github/
│   ├── dependabot.yml           # Automated dependency updates
│   └── workflows/
│       ├── ci.yml.example       # CI/CD pipeline template
│       └── README.md            # CI/CD setup instructions
├── .husky/
│   ├── pre-commit               # Lint-staged pre-commit hook
│   └── commit-msg               # Commitlint message hook
├── .vscode/
│   ├── settings.json            # Workspace settings
│   ├── extensions.json          # Recommended extensions
│   └── launch.json              # Debug configurations
├── .devcontainer/
│   ├── devcontainer.json        # Dev container config (Codespaces)
│   └── docker-compose.yml       # Dev container services
├── prd/
│   ├── 00_index.md              # Feature tracking index
│   ├── 00_technology.md         # Tech stack template (customize)
│   ├── _prd_template.md         # PRD template
│   ├── _task_template.md        # Task tracking template
│   ├── _changelog_template.md   # Changelog with breaking change policy
│   └── tasks/                   # Long-running feature task files
└── .claude/
    ├── mcp.json                 # MCP server configuration template
    ├── rules/                   # Auto-loaded rules (~6K tokens)
    │   ├── code-quality.md      # Code quality standards
    │   ├── testing.md           # Testing requirements
    │   ├── ai-agent-patterns.md # AI agent principles
    │   ├── error-handling.md    # Error handling patterns
    │   ├── git-workflow.md      # Git workflow standards
    │   ├── quality-checks.md    # Quality check requirements
    │   ├── task-management.md   # Task tracking workflow
    │   └── security-core.md     # Core security (always applies)
    ├── rules-available/         # Opt-in rules (symlink into rules/)
    │   ├── android.md           # Android (Kotlin / Compose)
    │   ├── docker.md            # Docker & container best practices
    │   ├── ios.md               # iOS (Swift / SwiftUI)
    │   ├── nextjs.md            # Next.js development patterns
    │   ├── python.md            # Python (uv, ruff, FastAPI)
    │   ├── security-web.md      # Web security (React, Next.js)
    │   ├── security-mobile.md   # Mobile security (React Native)
    │   └── security-owasp.md    # OWASP Top 10 standards
    ├── references/              # On-demand (loaded by skills)
    │   ├── gitmoji.md           # Gitmoji reference (/commit)
    │   └── rules-guide.md       # How the rules system works
    ├── agents/                  # Specialized agents (8)
    │   ├── codex-style-agent.md # Autonomous code generation
    │   ├── architect.md         # Architecture & design review
    │   ├── test-writer.md       # Test generation
    │   ├── perf-auditor.md      # Performance auditing
    │   ├── security-reviewer.md # Security review (STRIDE)
    │   ├── simplicity-reviewer.md # Over-engineering detection
    │   ├── data-integrity-reviewer.md # Data consistency & validation
    │   └── codebase-researcher.md # Deep codebase analysis
    └── skills/                  # Slash commands (26 skills)
        ├── feature.md           # Full feature lifecycle
        ├── commit.md            # Conventional commits
        ├── pr.md                # Pull request creation
        ├── test.md              # Test runner with coverage
        ├── lint.md              # Linting & formatting
        ├── refactor.md          # Safe refactoring
        ├── review.md            # Code review
        ├── debug.md             # Systematic debugging
        ├── checkpoint.md        # Progress tracking
        ├── hotfix.md            # Production patches
        ├── init.md              # Project initialization
        ├── deps.md              # Dependency management
        ├── scan.md              # Security scanning
        ├── migrate.md           # Database migrations
        ├── api.md               # API endpoint design
        ├── docs.md              # Documentation generation
        ├── onboard.md           # New contributor walkthrough
        ├── resume.md            # Session recovery
        ├── env.md               # Environment variable management
        ├── release.md           # Version tagging and releases
        ├── perf.md              # Performance profiling
        ├── ci.md                # CI/CD pipeline generation
        ├── scaffold.md          # Module/component scaffolding
        ├── deploy.md            # Deployment to staging/production
        ├── compound.md          # Knowledge capture from solved problems
        └── brainstorm.md        # Requirements exploration
```

## Git Commit Template

The template includes a `.gitmessage` file for consistent commit messages following [Conventional Commits](https://www.conventionalcommits.org/).

**Setup:**
```bash
# Configure git to use the commit template
git config commit.template .gitmessage

# Or set globally for all repositories
git config --global commit.template ~/.gitmessage
cp .gitmessage ~/.gitmessage
```

When you run `git commit` (without `-m`), the template will appear in your editor with guidance on:
- Commit types (feat, fix, docs, etc.)
- Scope usage
- Body and footer formatting
- Gitmoji emoji prefixes (optional)
- Examples

**Gitmoji Support:**
- See `.claude/references/gitmoji.md` for Gitmoji reference
- Gitmoji provides visual commit identification with emoji prefixes

You can also use the `/commit` skill for AI-assisted commit message generation.

## CI/CD Pipeline

The template includes a GitHub Actions CI/CD pipeline with **5 quality gates**:

1. **Lint & Format** - Code quality and formatting checks
2. **Type Check** - Static type checking
3. **Test & Coverage** - Unit/integration tests with coverage threshold
4. **Security Scan** - Dependency and code security scanning
5. **Build** - Application build verification

**Setup:**
```bash
cp .github/workflows/ci.yml.example .github/workflows/ci.yml
# Edit ci.yml and customize for your tech stack
```

See [`.github/workflows/README.md`](.github/workflows/README.md) for detailed setup instructions.

## Context Management

AI agents have limited context windows. This template is designed to minimize wasted tokens by only loading rules relevant to your project.

### Three-Tier Rule System

```
.claude/rules/              Always loaded — universal standards (~6K tokens)
.claude/rules-available/    Opt-in — symlink to enable per project
.claude/references/         On-demand — loaded by skills when needed
```

| Tier | When Loaded | Contains |
|------|-------------|----------|
| **`rules/`** | Every session, automatically | Code quality, testing, error handling, git workflow, security basics, AI patterns, task management |
| **`rules-available/`** | Only when symlinked into `rules/` | Next.js, iOS, Android, Docker, web/mobile security, OWASP |
| **`references/`** | Only when a skill reads it | Gitmoji lookup table, rules system documentation |

### Enabling Platform Rules

```bash
# Web app (Next.js / React)
make enable-web      # → nextjs, security-web, security-owasp

# Python backend
make enable-python   # → python, security-owasp

# Backend API (any stack, minimal)
make enable-api      # → security-owasp

# Native iOS (Swift / SwiftUI)
make enable-ios      # → ios, security-owasp

# Native Android (Kotlin / Compose)
make enable-android  # → android, security-owasp

# Mobile app (React Native)
make enable-mobile   # → security-mobile, security-web, security-owasp

# Containerized project
make enable-docker   # → docker, security-owasp

# See all available rules
make enable-rules
```

Each command creates symlinks from `rules-available/` into `rules/`. You can also enable individual rules manually:

```bash
ln -s ../rules-available/nextjs.md .claude/rules/nextjs.md
```

### Context Budget by Project Type

| Project Type | Auto-Loaded | % of 200K Context |
|--------------|-------------|-------------------|
| Python / Go API | ~8K tokens | ~4% |
| Node.js API | ~8K tokens | ~4% |
| Next.js Web App | ~19K tokens | ~10% |
| React Native | ~15K tokens | ~8% |

### Adding Custom Rules

**Universal rule** (every project needs this):
```bash
# Create in rules/ — it auto-loads every session
echo "# My Rule" > .claude/rules/my-rule.md
```

**Platform rule** (only some projects need this):
```bash
# Create in rules-available/ — explicitly opt in
echo "# My Platform Rule" > .claude/rules-available/my-platform-rule.md
ln -s ../rules-available/my-platform-rule.md .claude/rules/my-platform-rule.md
```

See `.claude/references/rules-guide.md` for the full guide.

## Documentation Reference

| Document | Purpose | When to Read |
|----------|---------|--------------|
| `README.md` | Project overview and setup | Start here |
| `CLAUDE.md` | AI agent project guidance | Customize for your project |
| `CONTRIBUTING.md` | Contributor workflow and standards | Before contributing |
| `.claude/rules/` | Universal standards (auto-loaded) | Source of truth |
| `.claude/rules-available/` | Platform rules (opt-in) | Enable for your stack |
| `.claude/references/rules-guide.md` | How the rules system works | Understanding context management |
| `prd/00_technology.md` | Tech stack template | Configure your stack |
| `Makefile` | Available make targets | Running commands |
| `.github/workflows/README.md` | CI/CD setup guide | Setting up pipelines |

## License

MIT
