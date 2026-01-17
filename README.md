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
- `.claude/agents/` - Specialized agent configurations

### Documentation Structure
- `prd/01_Technical_standards.md` - Code quality and agent development principles
- `prd/02_Tech_stack.md` - Technology stack template (customize per project)
- `prd/03_Security.md` - Security standards and OWASP guidelines

### Task Management
- `prd/tasks/` - Directory for feature task tracking
- `TASK_TEMPLATE.md` - Template for progress tracking and context recovery

### Skills (Slash Commands)
| Skill | Purpose |
|-------|---------|
| `/feature` | Full feature lifecycle (PRD → code → tests → PR) |
| `/test` | Run tests with coverage |
| `/lint` | Run linting, formatting, type checking |
| `/refactor` | Safely refactor code with tests |
| `/review` | Code review against standards |
| `/checkpoint` | Save progress to task file |
| `/scan` | Run security scans |
| `/migrate` | Manage database migrations |

## Workflow

1. **Start a feature** - Create a task file in `prd/tasks/` using the template
2. **Develop with AI** - Use skills and agent guidance for consistent output
3. **Track progress** - Run `/checkpoint` every 30-60 minutes
4. **Review and test** - Use `/review`, `/test`, and `/lint` before commits
5. **Recover context** - Task files enable session resumption

## Getting Started

### 1. Copy the Template

```bash
cp -r core-ai-template my-project
cd my-project
git init
```

### 2. Configure Your Tech Stack

Edit `prd/02_Tech_stack.md` with your technology choices:
- Programming language and version
- Package manager and commands
- Frameworks and libraries
- Testing and linting tools

### 3. Update Project Guidance

Customize `CLAUDE.md` with project-specific:
- Commands and scripts
- Architecture patterns
- Environment variables

### 4. Start Building

```bash
/feature my-feature --scaffold --with-db
/test
/lint --fix
/checkpoint
```

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
├── CLAUDE.md                    # AI agent project guidance
├── AGENTS.md                    # Agent quick reference
├── prd/
│   ├── 00_PRD_index.md          # PRD index
│   ├── 01_Technical_standards.md
│   ├── 02_Tech_stack.md         # Tech stack template
│   ├── 03_Security.md
│   └── tasks/
│       └── TASK_TEMPLATE.md
└── .claude/
    ├── agents/                  # Specialized agents
    └── skills/                  # Slash commands
```

## License

MIT
