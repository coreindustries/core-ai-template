# Core AI Template

A template for starting agentic-based software projects. Provides structure, documentation patterns, and workflows optimized for AI-assisted development with tools like Claude Code, Cursor, and similar AI coding assistants.

## Purpose

This template establishes a foundation for projects where AI agents are primary contributors to the codebase. It includes:

- **Structured guidance** for AI agents via `CLAUDE.md` and auto-loaded rules
- **Agent safety** — guardrails rule, authority bounds on all agents, failure mode recovery
- **Architecture Decision Records** (ADRs) with agent-specific fields to prevent undoing intentional choices
- **Product requirements documentation** (PRD) for maintaining project context
- **Task tracking** for long-running features and session recovery
- **30 reusable skills** (slash commands) for common development workflows
- **Compound engineering** practices adapted from [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) — knowledge capture, requirements discovery, and multi-perspective code review

## Features

### Context-Optimized Rules System
- `.claude/rules/` - 9 universal rules, auto-loaded (~7K tokens)
- `.claude/rules-available/` - 8 platform rules, opt-in via `make enable-*`
- `.claude/references/` - On-demand lookups, loaded by skills when needed
- Only loads what your project needs — **65-70% less context waste** vs loading everything

### AI Agent Guidance
- `CLAUDE.md` - Project-level instructions and coding standards
- `.claude/agents/` - 8 specialized agents with authority bounds + standardized template
- `.claude/skills/` - 30 slash commands for common workflows
- `.claude/references/` - 7 on-demand references (orchestration patterns, checklists, gitmoji)
- `.claude/mcp.json` - MCP server configuration template
- `docs/decisions/` - Architecture Decision Records with agent-guidance fields

### Documentation & Standards
- `.claude/rules/` + `.claude/rules-available/` - Source of truth for all standards
- `prd/00_technology.md` - Technology stack template (customize per project)
- `CONTRIBUTING.md` - Contributor guide with workflow, standards, and AI skill usage

### Task Management
- `prd/tasks/` - Directory for feature task tracking
- `_task_template.md` - Template for progress tracking and context recovery
- `/resume` skill - Automated session recovery after context compression

### PR / Issue Labels
- `.github/labels.yml` - Canonical label set (type, area, priority, status, process)
- `.github/labeler.yml` - Path-based auto-labeling rules (e.g. `*.py` → `area/python`)
- `.github/workflows/labeler.yml` - Auto-applies `area/*` labels on PR open / sync
- `.github/workflows/labels-sync.yml` - Reconciles repo labels with `labels.yml` on push to main
- PR template includes a labels checklist (type + priority + `codex` opt-in)

### Cross-Repo Coordination
- `docs/coordination/` - Track work that crosses a repository boundary (schema changes, ops handoffs, contract negotiations between services)
- `docs/coordination/README.md` - Lifecycle, frontmatter schema, when to open one
- `docs/coordination/_template.md` - Blank template with `direction: incoming|outgoing`

### Autonomous Dev Workflow

Reduces human-in-the-loop overhead by automating the three most common interruptions: CI failures that agents can fix, safe PRs that don't need manual merging, and post-deploy health checks that require a human to run.

- **`/handoff` skill** — writes structured session context to `CONTEXT.md`, the feature task file, and `CLAUDE.md → ## Current State` at session end. Gives the next agent a single-file starting point instead of re-reading git log.
- **`auto-fix.yml`** — `workflow_run`-triggered CI self-healing. Classifies failures (`lint | types | test | flaky | build`); fixes lint and type errors autonomously via Claude Code, routes the rest to the CTO agent.
- **`auto-merge.yml`** — tier-based merge policy: `chore/docs/style` PRs merge immediately after CI; `fix` PRs after a 30-minute window; `feat` and sensitive scopes require human review.
- **`post-deploy-health.sh`** — hits configurable health endpoints after deploy (3 retries, 5s backoff) and posts a green/red Slack summary.
- **`cto.md` agent** — receives classified CI/CD failure alerts and routes them: analyze test failures, investigate flakiness, escalate unknowns to emergency channel.

See `REPO_SETUP.md` for one-time GitHub configuration (auto-merge setting, branch protection, secrets).

### Adopt Into Any Existing Repo
- `docs/adopt-best-practices.md` - **Self-contained** markdown file you can hand to any Claude Code (or compatible) agent in another repo to land this template's tooling discipline (secret scanning, Conventional Commits, PR template, ADR/PRD/coordination workflows) in a single PR
- See "Adopting Into An Existing Repo" below for usage

### Developer Experience
- `Makefile` - One-command setup, dev, test, quality checks
- `.editorconfig` - Cross-IDE formatting consistency
- `.vscode/` - VS Code settings, extensions, debug configurations
- `.devcontainer/` - Reproducible dev environments (Codespaces-ready)
- `.husky/` - Pre-commit hooks (lint-staged + commitlint)
- `.github/dependabot.yml` - Automated dependency updates
- `scripts/statusline/` - Multi-line Claude Code statusline (directory, branch/worktree, context %, model, effort level, cost, token burn rate). See `scripts/statusline/README.md` for install.

### Skills (Slash Commands)

**Development**
| Skill | Purpose |
|-------|---------|
| `/feature` | Full feature lifecycle (PRD → code → tests → PR) |
| `/test` | Run tests with coverage |
| `/lint` | Run linting, formatting, type checking |
| `/refactor` | Safely refactor code with tests |
| `/review` | Code review against standards |
| `/code-review-expert` | Senior engineer lens review (SOLID, security, perf) |
| `/debug` | Systematic debugging workflow |
| `/api` | Design REST/GraphQL endpoints |

**Git & Workflow**
| Skill | Purpose |
|-------|---------|
| `/commit` | Create conventional commits |
| `/pr` | Create pull requests with descriptions |
| `/hotfix` | Quick patch for production issues |
| `/checkpoint` | Save progress to task file |
| `/handoff` | Write structured session handoff for context recovery |
| `/compact` | Create token-efficient state snapshot |

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
| `/context` | Audit auto-loaded context budget and recommend optimizations |
| `/adr` | Create Architecture Decision Records with agent guidance |

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

#### Specialized Agents

Three specialized agents support compound engineering:

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

## Adopting Into An Existing Repo

`docs/adopt-best-practices.md` is a self-contained playbook for landing
this template's tooling discipline (secret scanning, Conventional
Commits enforcement, PR template, AGENTS.md, decision/product/
coordination workflows, optional cross-model PR review) into any
existing repository.

### How to use it

Hand the file to a Claude Code (or compatible) agent running inside
the target repo:

```
Read docs/adopt-best-practices.md from <this repo or a vendored copy>
and apply it to the current repo. Open a PR titled
"chore: adopt security/commit/review best-practices kit".
```

The agent will:

1. Confirm the target repo and create a feature branch.
2. Inventory existing tooling (so it doesn't overwrite project-specific
   hooks).
3. Drop in hook scripts, gitleaks config, commit-msg hook,
   `.gitmessage`, PR template, `AGENTS.md`, optional Codex review
   workflow, optional ADR/PRD/coordination scaffolding.
4. Verify each layer (commit-msg accepts/rejects, secret backstop
   blocks, workflow YAML parses).
5. Open a PR with the kit, leaving GitHub-side follow-ups (label
   creation, environment secrets, branch protection) as checklist
   items.

The doc inlines every script and config — no fetches, no external
dependencies beyond `git`, `bash`, and (optionally) `gitleaks` and
`gh`. It works for Node, Python, Go, Rust, polyglot, or scriptless
repos.

## Claude Code Statusline

A multi-line statusline that surfaces directory, git branch / worktree, context %, 5-hour and 7-day rate-limit usage (with reset times), model, output style, effort level, session cost, and token burn rate.

```
📁 ~/projects/foo
🌿 branch: main
🧠 context: 87% [========--]  ⏱  5h: 24% [==--------] → 14:30  📅 7d: 41% [====------] → 05/13
🤖 Opus 4.7  📟 v2.0.18  🎨 default  ⚡ auto  💰 $0.4231 ($14.30/h)  📊 142,533 tok (8,932 tpm)
```

The script lives at [`scripts/statusline/statusline.sh`](scripts/statusline/statusline.sh).

### Quick install via Claude Code

Paste this prompt into a fresh Claude Code session in any repo. The agent will fetch the script, wire it into `~/.claude/settings.json` (preserving other keys), and run the smoke test before reporting done.

```
Set up the multi-line Claude Code statusline from
coreindustries/core-ai-template (effort level + 5h/7d rate-limit
bars + cost + context).

Source files:
- https://raw.githubusercontent.com/coreindustries/core-ai-template/main/scripts/statusline/statusline.sh
- https://raw.githubusercontent.com/coreindustries/core-ai-template/main/scripts/statusline/README.md  (reference)

Steps:

1. If ~/.claude/statusline.sh exists, back it up to
   ~/.claude/statusline.sh.bak before overwriting.

2. Download statusline.sh to ~/.claude/statusline.sh:
     mkdir -p ~/.claude
     curl -fsSL "<RAW URL above>" -o ~/.claude/statusline.sh
     chmod +x ~/.claude/statusline.sh

3. Update ~/.claude/settings.json to add (or merge) this top-level
   block. Preserve every other key. If a different statusLine config
   already exists, show me the diff and ask before replacing.

     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh",
       "padding": 0
     }

   Use jq for the merge: read the existing JSON, set the statusLine
   key, write it back atomically. Do NOT pretty-print in a way that
   reorders other keys unnecessarily.

4. Smoke test:
     printf '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"effort":{"level":"auto"}}' \
       | bash ~/.claude/statusline.sh

   Expected: three lines — directory, "context: TBD", model + effort.

5. Tell me to restart Claude Code (or send a message) so the new
   statusline takes effect on the next turn.

Hard rules:
- Never paste the contents of ~/.claude/settings.json or any other
  settings file into chat.
- Do not modify anything else under ~/.claude/.
- If curl is missing, use wget; if both missing, fall back to
  `gh api repos/coreindustries/core-ai-template/contents/scripts/statusline/statusline.sh -H "Accept: application/vnd.github.raw" > ~/.claude/statusline.sh`.
```

For manual install, color customization, and the full feature list, see [`scripts/statusline/README.md`](scripts/statusline/README.md).

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
├── REPO_SETUP.md                # GitHub repo configuration for autonomous workflow
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
│       ├── auto-fix.yml         # Self-healing CI (lint/type failures)
│       ├── auto-merge.yml       # Tier-based PR auto-merge policy
│       └── README.md            # CI/CD setup instructions
├── .gitleaks.toml               # Secret & PII scanning config (gitleaks)
├── .husky/
│   ├── pre-commit               # Secret scan + lint-staged pre-commit hook
│   └── commit-msg               # Commitlint message hook
├── .vscode/
│   ├── settings.json            # Workspace settings
│   ├── extensions.json          # Recommended extensions
│   └── launch.json              # Debug configurations
├── .devcontainer/
│   ├── devcontainer.json        # Dev container config (Codespaces)
│   └── docker-compose.yml       # Dev container services
├── scripts/
│   ├── scan-secrets.sh          # Secret & PII scanner wrapper (gitleaks)
│   ├── classify-ci-failure.sh   # CI failure classifier (lint/types/test/flaky/build)
│   └── post-deploy-health.sh    # Post-deploy health check with Slack notification
├── tools/
│   └── comms/
│       └── send-hook.js         # Zero-dependency Slack webhook router (Node.js built-ins)
├── prd/
│   ├── 00_index.md              # Feature tracking index
│   ├── 00_technology.md         # Tech stack template (customize)
│   ├── _prd_template.md         # PRD template
│   ├── _task_template.md        # Task tracking template
│   ├── _changelog_template.md   # Changelog with breaking change policy
│   └── tasks/                   # Long-running feature task files
├── docs/
│   └── decisions/               # Architecture Decision Records (ADRs)
│       ├── index.md             # ADR index and status tracking
│       └── adr-template.md      # Template for new ADRs
└── .claude/
    ├── mcp.json                 # MCP server configuration template
    ├── rules/                   # Auto-loaded rules (~7K tokens)
    │   ├── code-quality.md      # Code quality standards
    │   ├── testing.md           # Testing requirements
    │   ├── ai-agent-patterns.md # AI agent principles + failure modes
    │   ├── error-handling.md    # Error handling patterns
    │   ├── git-workflow.md      # Git workflow standards
    │   ├── guardrails.md        # Agent safety boundaries
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
    ├── references/              # On-demand (loaded by skills, 7 files)
    │   ├── code-quality-checklist.md # Code review quality checklist
    │   ├── gitmoji.md           # Gitmoji reference (/commit)
    │   ├── orchestration-patterns.md # Multi-agent coordination patterns
    │   ├── removal-plan.md      # Deprecation and removal guidance
    │   ├── rules-guide.md       # How the rules system works
    │   ├── security-checklist.md # Security review checklist
    │   └── solid-checklist.md   # SOLID principles checklist
    ├── agents/                  # Specialized agents (9 + template)
    │   ├── _template.md         # Standard 5-block agent structure
    │   ├── codex-style-agent.md # Autonomous code generation
    │   ├── architect.md         # Architecture & design review
    │   ├── test-writer.md       # Test generation
    │   ├── perf-auditor.md      # Performance auditing
    │   ├── security-reviewer.md # Security review (STRIDE)
    │   ├── simplicity-reviewer.md # Over-engineering detection
    │   ├── data-integrity-reviewer.md # Data consistency & validation
    │   ├── codebase-researcher.md # Deep codebase analysis
    │   └── cto.md               # CI/CD failure triage and escalation routing
    └── skills/                  # Slash commands (31 skills, each <name>/SKILL.md)
        ├── adr/                 # Architecture Decision Records
        ├── compact/             # Context state snapshots
        ├── feature/             # Full feature lifecycle
        ├── commit/              # Conventional commits
        ├── pr/                  # Pull request creation
        ├── test/                # Test runner with coverage
        ├── lint/                # Linting & formatting
        ├── refactor/            # Safe refactoring
        ├── review/              # Code review
        ├── debug/               # Systematic debugging
        ├── checkpoint/          # Progress tracking
        ├── hotfix/              # Production patches
        ├── init/                # Project initialization
        ├── deps/                # Dependency management
        ├── scan/                # Security scanning
        ├── migrate/             # Database migrations
        ├── api/                 # API endpoint design
        ├── docs/                # Documentation generation
        ├── onboard/             # New contributor walkthrough
        ├── resume/              # Session recovery
        ├── env/                 # Environment variable management
        ├── release/             # Version tagging and releases
        ├── perf/                # Performance profiling
        ├── ci/                  # CI/CD pipeline generation
        ├── scaffold/            # Module/component scaffolding
        ├── deploy/              # Deployment to staging/production
        ├── code-review-expert/   # Senior engineer code review
        ├── compound/            # Knowledge capture from solved problems
        ├── brainstorm/          # Requirements exploration
        ├── context/             # Context budget audit and optimization
        └── handoff/             # Session-end handoff for context recovery
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
.claude/rules/              Always loaded — universal standards (~7K tokens)
.claude/rules-available/    Opt-in — symlink to enable per project
.claude/references/         On-demand — loaded by skills when needed
```

| Tier | When Loaded | Contains |
|------|-------------|----------|
| **`rules/`** | Every session, automatically | Code quality, testing, error handling, git workflow, security basics, AI patterns, task management, guardrails |
| **`rules-available/`** | Only when symlinked into `rules/` | Next.js, iOS, Android, Docker, web/mobile security, OWASP |
| **`references/`** | Only when a skill reads it | Gitmoji, orchestration patterns, quality/security/SOLID checklists, rules guide |

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
