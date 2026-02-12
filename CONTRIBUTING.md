# Contributing

Thank you for contributing! This guide covers the workflow, standards, and tools used in this project.

## Prerequisites

- Read `CLAUDE.md` for project overview and commands
- Read `prd/00_technology.md` for technology choices
- Run `make setup` to configure your environment

## Development Workflow

### 1. Pick a Task

- Check `prd/00_index.md` for "In Progress" features
- Look at open issues for unassigned work
- Create a task file: `cp prd/_task_template.md prd/tasks/{feature}_tasks.md`

### 2. Create a Branch

```bash
git checkout -b {type}/{description}
```

**Branch naming:**

| Type | Use For | Example |
|------|---------|---------|
| `feat/` | New features | `feat/user-auth` |
| `fix/` | Bug fixes | `fix/login-redirect` |
| `refactor/` | Code refactoring | `refactor/service-layer` |
| `docs/` | Documentation | `docs/api-reference` |
| `chore/` | Maintenance | `chore/update-deps` |

### 3. Develop

```bash
make dev         # Start dev server
make test        # Run tests as you go
make lint-fix    # Fix linting issues
```

**Quality checks** (run frequently, not just before commits):
```bash
make quality     # Full suite: lint + typecheck + security + tests
```

### 4. Commit

Follow [Conventional Commits](https://www.conventionalcommits.org/) with optional [Gitmoji](https://gitmoji.dev/):

```
feat: add user authentication
fix: resolve login redirect loop
docs: update API documentation
```

With Gitmoji (see `.claude/references/gitmoji.md`):
```
✨ feat: add user authentication
🐛 fix: resolve login redirect loop
```

Pre-commit hooks will automatically:
- Lint and format staged files
- Validate commit message format

### 5. Create Pull Request

```bash
make quality     # Ensure all checks pass
git push -u origin HEAD
gh pr create     # Or use /pr skill
```

**PR requirements:**
- [ ] All CI checks pass
- [ ] Test coverage maintained or improved
- [ ] Description explains the "why", not just the "what"
- [ ] Screenshots for UI changes

## Using AI Skills

This project includes 16+ slash commands for AI-assisted development. Use them to maintain consistency:

| Skill | When to Use |
|-------|-------------|
| `/feature` | Starting a new feature (full lifecycle) |
| `/test` | Need comprehensive tests |
| `/lint` | Before committing |
| `/review` | Before creating a PR |
| `/commit` | Creating a commit message |
| `/pr` | Creating a pull request |
| `/debug` | Investigating a bug |
| `/refactor` | Restructuring code safely |

## Code Standards

Standards are enforced via `.claude/rules/` (auto-loaded by Claude Code) and `.cursorrules` (loaded by Cursor IDE). Key requirements:

- **Type annotations** on all functions, attributes, and returns
- **Docstrings** on all public functions and classes
- **DRY principle** - search for existing implementations before creating new code
- **Tests** for all new code (unit + integration where applicable)
- **Error handling** with specific exception types (no silent catches)

## Project Structure

```
src/{project_name}/
├── api/          # Route handlers (thin - delegate to services)
├── services/     # Business logic
├── models/       # Request/response schemas
├── db/           # Database singleton + utilities
└── logging/      # Structured + audit logging
tests/
├── unit/         # No I/O, mock externals
└── integration/  # Real database, use fixtures
```

## Getting Help

- Run `make help` for available commands
- Read `.claude/rules/` for specific standards
- Check `prd/00_technology.md` for technology-specific guidance
- Use the `/debug` skill for systematic problem solving
