# CLAUDE.md

Project guidance for Claude Code. **For detailed agent patterns, see `AGENTS.md`.**

## Overview

**Stack:** See `prd/02_Tech_stack.md` for technology decisions.

## Commands Reference

All commands should use your project's package manager/runner. See `prd/02_Tech_stack.md` for specific commands.

```bash
# Common patterns (replace with your tech stack commands)
{package_manager} install        # Install deps
{package_manager} add {package}  # Add package
{runner} {script}                # Run scripts
{runner} test                    # Run tests
{runner} {app_entry}             # Start app
```

## Architecture

**Entry Points:**
Defined in `prd/02_Tech_stack.md`. Typically includes:
- API server entry point
- CLI entry point (if applicable)

**Key Patterns:**
- Database: Use singleton/context manager patterns (defined in tech stack)
- Config: Use environment-based configuration (pydantic-settings, dotenv, etc.)
- Logging: Use structured logging with separate audit logging for security
- Metrics: Expose metrics endpoint for monitoring

**Directory Structure:**
```
project-root/
├── src/{project_name}/          # Source code
│   ├── api/                     # Routes (delegate to services)
│   ├── services/                # Business logic
│   ├── models/                  # Request/response schemas
│   ├── db/                      # Database utilities
│   └── logging/                 # Logging configuration
├── tests/
│   ├── unit/                    # Fast, no I/O
│   └── integration/             # Real database
├── prd/                         # Product requirements
│   └── tasks/                   # Task tracking files
└── {config_files}               # See tech stack for specifics
```

## Essential Commands

See `prd/02_Tech_stack.md` for technology-specific commands.

**Common patterns:**
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
{test_stop_first}                # Stop on first failure
```

## Code Standards

1. **Type hints/annotations** on all functions/attributes/returns
2. **Docstrings** on public functions/classes (Google-style, JSDoc, etc.)
3. **Coverage minimum** defined in tech stack (typically 66-100%)
4. **Modern syntax** for your language version
5. **DRY:** Search for existing implementations first

## Database Patterns

```
# See prd/02_Tech_stack.md for ORM/database access patterns
# General principles:
- Use singleton pattern for database client
- Use context managers/transactions for database operations
- Handle JSON fields according to ORM requirements
```

## Testing

- **Unit** (`tests/unit/`): No I/O, mock externals, fast
- **Integration** (`tests/integration/`): Real DB, use fixtures
- **Markers**: Use test framework markers for categorization

## Common Gotchas

See `prd/02_Tech_stack.md` for technology-specific gotchas.

**Universal gotchas:**
1. **Generate clients** after schema changes (ORM-specific)
2. **Database is singleton** - use provided helpers, not new instances
3. **Logging configured first** - configure at app entry point
4. **Test markers required** - mark integration tests appropriately

## PRDs & Documentation

| Document | Purpose |
|----------|---------|
| `prd/01_Technical_standards.md` | Code quality, AI agent patterns |
| `prd/02_Tech_stack.md` | Technology decisions and commands |
| `prd/03_Security.md` | OWASP, secrets, audit logging |
| `AGENTS.md` | Agent quick reference |
| `.claude/rules/` | Modular rules (automatically loaded) |
| `.claude/skills/` | Slash commands |

## Rules Directory

This project uses Claude Code's modular rules system (`.claude/rules/`). All rule files are automatically loaded.

**Available Rules:**
- `code-quality.md` - Code quality standards
- `testing.md` - Testing requirements
- `ai-agent-patterns.md` - AI agent development principles
- `error-handling.md` - Error handling patterns
- `git-workflow.md` - Git workflow standards
- `security.md` - Security standards
- `quality-checks.md` - Quality check requirements
- `task-management.md` - Task tracking workflow

See `.claude/rules/README.md` for details.

## Audit Logging (Security Events)

```
# See prd/02_Tech_stack.md for implementation details
# General pattern:
audit_logger.log(action="AUTH_SUCCESS", user_id="123", ip_address="1.2.3.4")
audit_logger.log(action="DATA_READ", user_id="123", resource_type="user")
```

## Environment

Required environment variables (see `.env.example`):
- `DATABASE_URL` - Database connection string
- `LOG_LEVEL` - DEBUG, INFO, WARNING, ERROR, CRITICAL
- `ENVIRONMENT` - development, staging, production

Additional variables defined in `prd/02_Tech_stack.md`.

## Renaming Template

When using this template for a new project:
1. Replace `{project_name}` in all files
2. Update technology-specific config files
3. Run package manager sync/install
