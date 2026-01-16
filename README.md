# Core AI Template

A language-agnostic template for AI-assisted software development. This template provides best practices, documentation structure, and tooling patterns that work with any programming language or framework.

## Overview

This template is designed for:
- **AI-assisted development** with Claude Code, Cursor, or similar tools
- **Any programming language** (Python, TypeScript, Go, etc.)
- **Production-ready code** with proper testing, linting, and security standards

## What's Included

```
core-ai-template/
├── CLAUDE.md              # Project guidance for Claude Code
├── AGENTS.md              # Quick reference for AI agents
├── prd/
│   ├── 00_PRD_index.md    # PRD index and task tracking
│   ├── 01_Technical_standards.md  # Code quality & AI agent patterns
│   ├── 02_Tech_stack.md   # Technology stack TEMPLATE
│   ├── 03_Security.md     # Security standards (OWASP)
│   └── tasks/
│       └── TASK_TEMPLATE.md  # Task tracking template
└── .claude/
    ├── agents/
    │   └── codex-style-agent.md  # Code review agent
    └── skills/
        ├── checkpoint.md   # Save progress
        ├── db-migrate.md   # Database migrations
        ├── lint.md         # Code quality checks
        ├── new-feature.md  # Scaffold features
        ├── refactor.md     # Safe refactoring
        ├── review.md       # Code review
        ├── security-scan.md  # Security scanning
        └── test.md         # Run tests
```

## Getting Started

### 1. Copy the Template

```bash
cp -r core-ai-template my-project
cd my-project
git init
```

### 2. Fill in the Tech Stack

Edit `prd/02_Tech_stack.md` with your technology choices:
- Programming language and version
- Package manager
- API framework
- Database and ORM
- Testing framework
- Linting tools

### 3. Update CLAUDE.md

Replace placeholder commands in `CLAUDE.md` with your actual commands:
- Install dependencies
- Run tests
- Start development server
- etc.

### 4. Start Developing

Use the skills and patterns defined in the template:

```bash
/new-feature user_profile --with-db --crud
/test
/lint --fix
/checkpoint
```

## Key Concepts

### AI Agent Development Principles

From `prd/01_Technical_standards.md`:

1. **Autonomy**: Bias to action, implement with reasonable assumptions
2. **Persistence**: Complete tasks end-to-end, don't stop at plans
3. **Correctness**: Prioritize quality over speed
4. **Comprehensiveness**: Update all relevant surfaces

### Task Tracking

For long-running features, create task files in `prd/tasks/`:

1. Copy `TASK_TEMPLATE.md` to `prd/tasks/{feature}_tasks.md`
2. Update every 30-60 minutes with `/checkpoint`
3. Use for context recovery after session breaks

### Skills

| Skill | Purpose |
|-------|---------|
| `/new-feature` | Scaffold a new feature |
| `/test` | Run tests with coverage |
| `/lint` | Run code quality checks |
| `/refactor` | Safely refactor code |
| `/review` | Code review against standards |
| `/checkpoint` | Save progress to task file |
| `/security-scan` | Run security scans |
| `/db-migrate` | Manage database migrations |

## Documentation

| Document | Purpose |
|----------|---------|
| `prd/01_Technical_standards.md` | Code quality and AI agent patterns |
| `prd/02_Tech_stack.md` | Technology decisions (fill in) |
| `prd/03_Security.md` | Security standards and OWASP |
| `AGENTS.md` | Quick reference for AI agents |

## Technology Examples

The template includes example configurations for:
- **Python**: FastAPI, pytest, ruff, mypy
- **TypeScript**: NestJS/Express, Vitest/Jest, ESLint
- **Go**: Chi/Gin, go test, golangci-lint

See `prd/02_Tech_stack.md` for detailed examples.

## License

MIT
