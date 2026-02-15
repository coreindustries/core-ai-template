---
prd_version: "1.0"
status: "Template"
last_updated: "2026-01-15"
---

# Tech Stack

> **Setup:** Fill in placeholders below with your project's choices, then delete instruction blocks like this one. This file is referenced by `CLAUDE.md`, `Makefile`, and `.claude/rules/` — keep it concise.

## 1. Core Stack

| Component | Choice |
|-----------|--------|
| **Language** | `{language}` (`{min_version}+`) |
| **Runtime** | `{runtime}` (if different from language) |
| **Package Manager** | `{package_manager}` |
| **API Framework** | `{api_framework}` |
| **Validation** | `{validation_library}` |
| **CLI Framework** | `{cli_framework}` (if applicable) |

## 2. Data Layer

| Component | Choice |
|-----------|--------|
| **Database** | `{database}` |
| **ORM / Query Builder** | `{orm}` |
| **Schema Location** | `{schema_location}` |
| **Migration Tool** | `{migration_tool}` |
| **Cache** | `{cache_system}` (if applicable) |
| **Extensions** | `{extensions}` (if applicable) |

### Database Access Pattern

```{language}
{db_access_example}
```

## 3. Quality Tooling

| Tool | Purpose | Config Location |
|------|---------|-----------------|
| `{linter}` | Lint + format | `{linter_config}` |
| `{type_checker}` | Type checking | `{type_config}` |
| `{test_framework}` | Testing | `{test_config}` |
| `{coverage_tool}` | Coverage | — |
| `{security_scanner}` | Security analysis | — |
| `{dep_scanner}` | Dependency audit | — |
| `gitleaks` | Secret & PII scanning | `.gitleaks.toml` |

### Coverage Requirements

| Scope | Minimum | Target |
|-------|---------|--------|
| Overall | `{min_coverage}%` | `{target_coverage}%` |
| New features | `{new_feature_coverage}%` | 100% |

### Test Markers

| Marker | Description |
|--------|-------------|
| `{unit_marker}` | Unit tests (no I/O) |
| `{integration_marker}` | Integration tests |
| `{slow_marker}` | Slow tests |

## 4. Infrastructure

### Containerization

| Component | Image |
|-----------|-------|
| Database | `{db_image}` |
| Cache | `{cache_image}` |
| Application | `{app_image}` |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Database connection string | — |
| `LOG_LEVEL` | Logging level | `INFO` |
| `ENVIRONMENT` | Environment name | `development` |
| `{additional_var}` | `{description}` | `{default}` |

### Logging

| Property | Value |
|----------|-------|
| Library | `{logging_library}` |
| Format | `{log_format}` (structured JSON recommended) |

## 5. Commands

> **Single source of truth for all project commands.** `Makefile` and `CLAUDE.md` reference these.

### Development

```bash
{install_command}                    # Install dependencies
{start_dev_server}                   # Start dev server with hot reload
{start_dependencies}                 # Start database, cache, etc.
{docker_stop_command}                # Stop dependencies
```

### Database

```bash
{generate_command}                   # Generate client/types after schema changes
{migration_create_command}           # Create migration
{migration_run_command}              # Run migrations
{schema_push_command}                # Push schema (dev only, no migration)
```

### Testing

```bash
{test_all_command}                   # Run all tests
{test_unit_command}                  # Unit tests only
{test_integration_command}           # Integration tests only
{test_coverage_command}              # Tests with coverage report
{test_specific_command}              # Run specific test file
{test_fail_fast_command}             # Stop on first failure
```

### Code Quality

```bash
{lint_check_command}                 # Lint check
{lint_fix_command}                   # Lint fix
{format_check_command}               # Format check
{format_fix_command}                 # Format fix
{type_check_command}                 # Type check
{security_scan_command}              # Security scan
scripts/scan-secrets.sh --all        # Secret & PII scan
```

### Full Quality Pipeline

```bash
{lint_fix_command} && {type_check_command} && {security_scan_command} && {test_coverage_command}
```

## 6. Project Structure

```
project-root/
├── src/{project_name}/
│   ├── {entry_file}                 # Main entry point
│   ├── api/                         # Route handlers (thin — delegate to services)
│   ├── services/                    # Business logic
│   ├── models/                      # Data models / schemas
│   ├── db/                          # Database singleton + utilities
│   ├── config/                      # Configuration
│   └── logging/                     # Structured + audit logging
├── tests/
│   ├── unit/                        # No I/O, mock externals
│   └── integration/                 # Real database, use fixtures
├── {schema_dir}/                    # Database schema
├── {package_config}                 # Package configuration
├── {docker_config}                  # Docker / Compose
├── .env.example
└── README.md
```

## 7. Stack-Specific Gotchas

> **Fill in:** Things that trip up developers (and AI agents) on this specific stack.

**Package management:**
- {gotcha_1}

**Database:**
- {gotcha_1}

**Type system:**
- {gotcha_1}

**Testing:**
- {gotcha_1}
