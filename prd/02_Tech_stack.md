---
prd_version: "1.0"
status: "Template"
last_updated: "2026-01-15"
---

# 02 – Tech Stack

> **Instructions:** Fill in this template with your project's specific technology choices.
> Delete the instruction blocks (like this one) when you're done.
> See examples in comments for guidance.

## 1. Language & Runtime

### 1.1 Primary Language

> **Fill in:** Your primary language and minimum version.

| Property | Value |
|----------|-------|
| Language | `{language}` |
| Minimum Version | `{min_version}` |
| Recommended Version | `{recommended_version}` |
| Type System | `{type_system}` |

**Key Features to Use:**
- {modern_feature_1}
- {modern_feature_2}
- {modern_feature_3}

**REQUIRED:** All code MUST use type annotations/hints.

### 1.2 Package Manager

> **Fill in:** Your package manager and common commands.

**Package Manager:** `{package_manager}`

**CRITICAL:** ALWAYS use `{package_manager}` to install packages and run scripts.

```bash
# Install dependencies
{install_command}

# Run scripts
{run_command} {script}

# Add a dependency
{add_command} {package}

# Add a dev dependency
{add_dev_command} {package}
```

**NEVER:**
- {never_do_1}
- {never_do_2}

## 2. Database

### 2.1 Primary Database

> **Fill in:** Your database choice.

| Property | Value |
|----------|-------|
| Database | `{database}` |
| Local | `{local_setup}` |
| Cloud | `{cloud_options}` |

### 2.2 Extensions (Optional)

> **Fill in:** Any database extensions you use.

- `{extension_1}` - {purpose_1}
- `{extension_2}` - {purpose_2}

### 2.3 Cache (Optional)

> **Fill in:** If you use caching.

| Property | Value |
|----------|-------|
| Cache | `{cache_system}` |
| Strategy | `{cache_strategy}` |

## 3. ORM and Schema Management

### 3.1 ORM/Query Builder

> **Fill in:** Your ORM or database access layer.

| Property | Value |
|----------|-------|
| ORM | `{orm}` |
| Schema Location | `{schema_location}` |
| Migration Tool | `{migration_tool}` |

**Database Access Pattern:**

```{language}
// Example database access pattern
{db_access_example}
```

### 3.2 Schema Commands

```bash
# Generate client/types (after schema changes)
{generate_command}

# Create migration
{migration_create_command}

# Run migrations
{migration_run_command}

# Push schema (dev only, no migration)
{schema_push_command}
```

## 4. API Framework

### 4.1 Framework

> **Fill in:** Your API framework choice.

| Property | Value |
|----------|-------|
| Framework | `{api_framework}` |
| Validation | `{validation_library}` |
| Documentation | `{api_docs}` |

**Example Route:**

```{language}
{route_example}
```

## 5. CLI Framework (Optional)

> **Fill in:** If your project includes a CLI.

| Property | Value |
|----------|-------|
| Framework | `{cli_framework}` |
| Entry Point | `{cli_entry}` |

## 6. Environment Variables

### 6.1 Configuration Library

| Property | Value |
|----------|-------|
| Library | `{config_library}` |
| Env File | `.env` |

**REQUIRED:**
- Load environment variables at startup
- Ignore `.env` files in git
- Validate required variables at startup

### 6.2 Configuration Pattern

```{language}
{config_example}
```

### 6.3 Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | Database connection string | `{db_url_example}` |
| `LOG_LEVEL` | Logging level | `INFO` |
| `ENVIRONMENT` | Environment name | `development` |
| {additional_var_1} | {description_1} | {example_1} |

## 7. Containerization

### 7.1 Docker Setup

> **Fill in:** Your container configuration.

**Images:**
- `{db_image}` - Database
- `{cache_image}` - Cache (if applicable)
- `{app_image}` - Application

### 7.2 Local Development

```bash
# Start dependencies
{docker_start_command}

# Stop dependencies
{docker_stop_command}
```

**docker-compose.yml structure:**
```yaml
{docker_compose_example}
```

## 8. Testing

### 8.1 Test Framework

| Property | Value |
|----------|-------|
| Framework | `{test_framework}` |
| Async Support | `{async_test_support}` |
| Coverage | `{coverage_tool}` |
| API Testing | `{api_test_client}` |

### 8.2 Coverage Requirements

| Type | Minimum | Target |
|------|---------|--------|
| Overall | `{min_coverage}%` | `{target_coverage}%` |
| New Features | `{new_feature_coverage}%` | 100% |

### 8.3 Test Commands

```bash
# Run all tests
{test_all_command}

# Run unit tests
{test_unit_command}

# Run integration tests
{test_integration_command}

# Run with coverage
{test_coverage_command}

# Run specific test
{test_specific_command}

# Stop on first failure
{test_fail_fast_command}
```

### 8.4 Test Markers

> **Fill in:** Your test categorization markers.

| Marker | Description |
|--------|-------------|
| `{unit_marker}` | Unit tests (no I/O) |
| `{integration_marker}` | Integration tests |
| `{slow_marker}` | Slow tests |

## 9. Code Quality Tools

### 9.1 Tool Suite

| Tool | Purpose |
|------|---------|
| `{linter}` | Linting |
| `{formatter}` | Formatting |
| `{type_checker}` | Type checking |
| `{security_scanner}` | Security analysis |
| `{dep_scanner}` | Dependency vulnerabilities |

### 9.2 Quality Commands

```bash
# Lint check
{lint_check_command}

# Lint fix
{lint_fix_command}

# Format check
{format_check_command}

# Format fix
{format_fix_command}

# Type check
{type_check_command}

# Security scan
{security_scan_command}

# Full quality check
{full_quality_command}
```

### 9.3 Configuration

> **Fill in:** Location of tool configurations.

| Tool | Config Location |
|------|-----------------|
| Linter | `{linter_config}` |
| Type Checker | `{type_config}` |
| Formatter | `{formatter_config}` |

## 10. Project Structure

```
project-root/
├── src/
│   └── {project_name}/
│       ├── {entry_file}         # Main entry point
│       ├── {cli_file}           # CLI entry (if applicable)
│       ├── {config_file}        # Configuration
│       ├── api/                 # API routes
│       ├── models/              # Data models/schemas
│       ├── services/            # Business logic
│       ├── db/                  # Database utilities
│       └── {additional_dirs}
├── tests/
│   ├── unit/
│   ├── integration/
│   └── {test_config}
├── {schema_dir}/                # Database schema
├── {package_config}             # Package configuration
├── {docker_config}              # Docker configuration
├── .env.example
└── README.md
```

## 11. Logging

### 11.1 Logging Library

| Property | Value |
|----------|-------|
| Library | `{logging_library}` |
| Format | `{log_format}` |

### 11.2 Logging Pattern

```{language}
{logging_example}
```

### 11.3 Audit Logging

```{language}
{audit_logging_example}
```

## 12. Common Gotchas

> **Fill in:** Technology-specific gotchas for your stack.

### 12.1 Package Management
- {gotcha_package_1}
- {gotcha_package_2}

### 12.2 Database
- {gotcha_db_1}
- {gotcha_db_2}

### 12.3 Type System
- {gotcha_type_1}
- {gotcha_type_2}

### 12.4 Testing
- {gotcha_test_1}
- {gotcha_test_2}

## 13. Quick Reference Commands

```bash
# ========== Development ==========
{start_dev_server}              # Start dev server
{start_dependencies}            # Start database, cache, etc.

# ========== Database ==========
{db_generate}                   # Generate client
{db_migrate}                    # Run migrations
{db_push}                       # Push schema (dev)

# ========== Quality ==========
{lint_fix_all}                  # Lint + format
{type_check_all}                # Type check
{test_with_coverage}            # Tests + coverage

# ========== Full Pipeline ==========
{full_quality_pipeline}
```

---

## Example: Python Stack

<details>
<summary>Click to see Python example</summary>

```yaml
# 1. Language & Runtime
Language: Python 3.13+
Package Manager: uv
Type System: mypy (strict)

# 2. Database
Database: PostgreSQL + pgvector
ORM: Prisma (prisma-client-py)
Cache: Redis

# 3. API Framework
Framework: FastAPI
Validation: Pydantic
Docs: OpenAPI (auto-generated)

# 4. CLI Framework
Framework: Typer

# 5. Testing
Framework: pytest
Coverage: pytest-cov
Minimum: 66%

# 6. Quality Tools
Linter: ruff
Type Checker: mypy
Security: bandit, safety

# Commands
uv sync                              # Install
uv run pytest --cov=src              # Test
uv run ruff check --fix src/         # Lint
uv run mypy src/                     # Type check
uv run prisma generate               # DB client
```

</details>

## Example: TypeScript/Node.js Stack

<details>
<summary>Click to see TypeScript example</summary>

```yaml
# 1. Language & Runtime
Language: TypeScript 5.x
Runtime: Node.js 20+
Package Manager: pnpm

# 2. Database
Database: PostgreSQL
ORM: Prisma
Cache: Redis

# 3. API Framework
Framework: NestJS / Fastify / Express
Validation: Zod / class-validator

# 4. Testing
Framework: Vitest / Jest
Coverage: c8 / istanbul

# 6. Quality Tools
Linter: ESLint
Formatter: Prettier
Type Checker: TypeScript (tsc)
Security: npm audit, snyk

# Commands
pnpm install                         # Install
pnpm test -- --coverage              # Test
pnpm lint --fix                      # Lint
pnpm typecheck                       # Type check
pnpm prisma generate                 # DB client
```

</details>

## Example: Go Stack

<details>
<summary>Click to see Go example</summary>

```yaml
# 1. Language & Runtime
Language: Go 1.22+
Package Manager: go mod

# 2. Database
Database: PostgreSQL
ORM: sqlc / GORM / ent

# 3. API Framework
Framework: Chi / Gin / Echo

# 4. Testing
Framework: testing (stdlib)
Coverage: go test -cover

# 6. Quality Tools
Linter: golangci-lint
Formatter: gofmt / goimports
Security: gosec

# Commands
go mod download                      # Install
go test ./... -cover                 # Test
golangci-lint run                    # Lint
go vet ./...                         # Static analysis
```

</details>
