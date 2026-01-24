# Core AI Template

A template for starting agentic-based software projects. Provides structure, documentation patterns, and workflows optimized for AI-assisted development with tools like Claude Code, Cursor, and similar AI coding assistants.

## Purpose

This template establishes a foundation for projects where AI agents are primary contributors to the codebase. It includes:

- **Structured guidance** for AI agents via `CLAUDE.md` and `AGENTS.md`
- **Product requirements documentation** (PRD) for maintaining project context
- **Task tracking** for long-running features and session recovery
- **Reusable skills** (slash commands) for common development workflows

## Features

### AI Agent Guidance
- `CLAUDE.md` - Project-level instructions and coding standards
- `AGENTS.md` - Quick reference for agent behavior patterns
- `.claude/rules/` - Modular rules (automatically loaded by Claude Code)
- `.claude/agents/` - Specialized agent configurations

### Documentation Structure
- `prd/01_Technical_standards.md` - Code quality and agent development principles
- `prd/02_Tech_stack.md` - Technology stack template (customize per project)
- `prd/03_Security.md` - Security standards and OWASP guidelines

### Task Management
- `prd/tasks/` - Directory for feature task tracking
- `TASK_TEMPLATE.md` - Template for progress tracking and context recovery

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
| `/deps` | Audit and manage dependencies |
| `/scan` | Run security scans |
| `/migrate` | Manage database migrations |
| `/docs` | Generate documentation |

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

Edit `prd/02_Tech_stack.md` with your technology choices. See examples below (Python, TypeScript, Go).

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

### Step 4: Set Up Environment (1 minute)

```bash
# Copy environment template (if .env.example exists)
cp .env.example .env

# Configure git commit template
git config commit.template .gitmessage

# Install dependencies
{package_manager} install
```

### Step 5: Set Up CI/CD (2 minutes)

```bash
cp .github/workflows/ci.yml.example .github/workflows/ci.yml
# Edit ci.yml and replace {placeholders} with your commands
```

See [`.github/workflows/README.md`](.github/workflows/README.md) for detailed setup.

### Step 6: Start Building (5 minutes)

```bash
# Create task file for your first feature
cp prd/tasks/TASK_TEMPLATE.md prd/tasks/my-feature_tasks.md

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

For detailed walkthrough, see [QUICKSTART.md](QUICKSTART.md).

## Tech Stack Examples

Copy one of these configurations into `prd/02_Tech_stack.md` as a starting point.

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
├── QUICKSTART.md                # Detailed 15-minute setup guide
├── CLAUDE.md                    # AI agent project guidance
├── AGENTS.md                    # Agent quick reference
├── TDD.md                       # Technical Design Document template
├── .gitmessage                  # Git commit message template
├── .cursorrules                 # Cursor IDE rules
├── marketplace.json             # Plugin marketplace manifest
├── .github/
│   └── workflows/
│       ├── ci.yml.example       # CI/CD pipeline template
│       └── README.md            # CI/CD setup instructions
├── prd/
│   ├── 00_PRD_index.md          # PRD index
│   ├── 01_Technical_standards.md # Code quality standards
│   ├── 02_Tech_stack.md         # Tech stack template (customize)
│   ├── 03_Security.md           # Security standards
│   └── tasks/
│       └── TASK_TEMPLATE.md     # Task tracking template
└── .claude/
    ├── rules/                   # Modular rules (auto-loaded)
    │   ├── README.md            # Rules directory documentation
    │   ├── code-quality.md      # Code quality standards
    │   ├── testing.md           # Testing requirements
    │   ├── ai-agent-patterns.md # AI agent principles
    │   ├── error-handling.md    # Error handling patterns
    │   ├── git-workflow.md      # Git workflow standards
    │   ├── gitmoji.md           # Gitmoji emoji prefixes
    │   ├── nextjs.md            # Next.js development patterns
    │   ├── security-core.md      # Core security (always applies)
    │   ├── security-mobile.md    # Mobile security (React Native)
    │   ├── security-web.md       # Web security (React, Next.js)
    │   ├── security.md           # Security standards
    │   ├── quality-checks.md     # Quality check requirements
    │   └── task-management.md   # Task tracking workflow
    ├── agents/                  # Specialized agents
    │   └── codex-style-agent.md
    └── skills/                  # Slash commands (16 skills)
└── .cursor/
    └── rules/                   # Cursor IDE workspace rules
        ├── gitmoji.mdc          # Gitmoji rule (.mdc format)
        ├── nextjs.mdc           # Next.js development rule (.mdc format)
        ├── security-core.mdc    # Core security rule (.mdc format, always applies)
        ├── security-mobile.mdc  # Mobile security rule (.mdc format, always applies)
        └── security-web.mdc     # Web security rule (.mdc format, always applies)
```

## Plugin Marketplace

This template includes a `marketplace.json` manifest for the [Anthropic Agent Skills](https://github.com/anthropics/skills) ecosystem.

### Installing Skills

Users can install skills from this template using Claude Code:

```bash
# Add the marketplace
claude plugin add https://github.com/your-org/your-project

# Install individual skills
claude plugin install feature
claude plugin install test
claude plugin install scan
```

### Available Skills

| Skill | Category | Description |
|-------|----------|-------------|
| `feature` | development | Full feature lifecycle (PRD → code → PR) |
| `test` | development | Run tests with coverage |
| `lint` | development | Linting, formatting, type checking |
| `refactor` | development | Safe code refactoring |
| `review` | development | Code review against standards |
| `debug` | development | Systematic debugging workflow |
| `api` | design | Design REST/GraphQL endpoints |
| `commit` | git | Create conventional commits |
| `pr` | git | Create pull requests |
| `hotfix` | git | Quick patch for production |
| `checkpoint` | productivity | Task tracking and context preservation |
| `init` | project | Initialize new project |
| `deps` | dependencies | Audit and manage dependencies |
| `docs` | documentation | Generate documentation |
| `scan` | security | Security scans (deps, code, secrets) |
| `migrate` | database | Database schema migrations |

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
- See `.claude/rules/gitmoji.md` for Gitmoji reference
- See `.cursor/rules/gitmoji.mdc` for Cursor IDE workspace rule
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

## Documentation Reference

| Document | Purpose | When to Read |
|----------|---------|--------------|
| `README.md` | Project overview and quick setup | Start here |
| `QUICKSTART.md` | Detailed 15-minute setup walkthrough | First time setup |
| `CLAUDE.md` | Project-level instructions for Claude Code | Customize for your project |
| `AGENTS.md` | AI agent quick reference | Daily development |
| `.claude/rules/` | Modular rules (auto-loaded) | Reference as needed |
| `prd/01_Technical_standards.md` | Full technical standards | Deep dive into standards |
| `prd/02_Tech_stack.md` | Tech stack template | Configure your stack |
| `prd/03_Security.md` | Security standards | Security implementation |
| `.github/workflows/README.md` | CI/CD setup guide | Setting up pipelines |

## License

MIT
