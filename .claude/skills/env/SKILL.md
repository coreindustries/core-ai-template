---
name: env
description: "Set up, validate, and manage environment variables."
---

# /env

Set up, validate, and manage environment variables.

## Usage

```
/env [action] [--check] [--generate] [--sync]
```

## Arguments

- `action`: `check`, `generate`, `sync`, `add`, `remove` (default: `check`)
- `--check`: Validate all required vars are set
- `--generate`: Create `.env` from `.env.example`
- `--sync`: Sync `.env.example` with actual usage in code

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete environment setup end-to-end
- Detect missing variables before runtime failures
- Never expose secret values in output

**Safety:**
- Never commit `.env` files
- Never log or display secret values
- Always use placeholder values in `.env.example`

### Actions

#### Check (`/env check`)

Validate environment is properly configured:

1. **Read `.env.example`** to get required variables
2. **Check `.env` exists** — if not, offer to generate
3. **Verify each variable** is set:
   ```bash
   # Check for missing vars
   diff <(grep -oP '^[A-Z_]+' .env.example | sort) <(grep -oP '^[A-Z_]+' .env | sort)
   ```
4. **Validate formats** where possible:
   - URLs: valid format, reachable
   - Ports: numeric, valid range
   - API keys: correct prefix/length patterns
5. **Report results**

#### Generate (`/env generate`)

Create `.env` from template:

1. **Copy `.env.example` to `.env`**:
   ```bash
   cp .env.example .env
   ```
2. **Prompt for values** that need customization
3. **Verify `.env` is in `.gitignore`**:
   ```bash
   grep -q "^\.env$" .gitignore || echo ".env" >> .gitignore
   ```

#### Sync (`/env sync`)

Ensure `.env.example` matches actual usage:

1. **Scan codebase** for environment variable references:
   ```bash
   # Find all env var usage patterns
   grep -rn "process\.env\.\|os\.environ\|os\.getenv\|env\(" src/ --include="*.{ts,tsx,py,go}"
   ```
2. **Compare against `.env.example`**
3. **Report discrepancies**:
   - Variables used in code but missing from `.env.example`
   - Variables in `.env.example` but unused in code
4. **Update `.env.example`** with missing entries (placeholder values only)

#### Add (`/env add <VAR_NAME>`)

Add a new environment variable:

1. **Add to `.env.example`** with placeholder and comment
2. **Add to `.env`** (prompt for actual value)
3. **Add validation** in config module if one exists
4. **Update `prd/00_technology.md`** environment variables table

#### Remove (`/env remove <VAR_NAME>`)

Remove an environment variable:

1. **Check for usage** in codebase
2. **Warn if still referenced**
3. **Remove from `.env.example`**
4. **Remove from config validation** if applicable

### Environment Report Format

```markdown
## Environment Check Report

**Status:** PASS / FAIL
**File:** .env (exists / missing)
**Gitignored:** Yes / No

### Variables

| Variable | Status | Format |
|----------|--------|--------|
| DATABASE_URL | Set | Valid URL |
| API_KEY | Set | Valid prefix |
| LOG_LEVEL | Missing | — |
| PORT | Set | Valid (3000) |

### Issues

- LOG_LEVEL: Not set (default: INFO)
- SECRET_KEY: In .env.example but not used in code

### Recommendations

1. Set LOG_LEVEL in .env
2. Remove unused SECRET_KEY from .env.example
```

## Example Output

```
$ /env check

Checking environment configuration...

.env file: Found
.gitignore: .env is excluded

Variable Check:
  DATABASE_URL ......... Set (valid PostgreSQL URL)
  LOG_LEVEL ............ Set (INFO)
  ENVIRONMENT .......... Set (development)
  API_KEY .............. MISSING
  JWT_SECRET ........... Set (32 chars)

Issues Found:
  API_KEY is required but not set in .env
  Copy from your provider dashboard and add to .env

Status: 1 issue found — fix before running the app.
```
