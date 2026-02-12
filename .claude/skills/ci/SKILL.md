---
name: ci
description: "Generate or update CI/CD pipeline configuration for the current stack."
---

# /ci

Generate or update CI/CD pipeline configuration for the current stack.

## Usage

```
/ci [action] [--platform <platform>] [--fix]
```

## Arguments

- `action`: `generate`, `update`, `fix`, `status` (default: `generate`)
- `--platform`: CI platform — `github` (default), `gitlab`, `bitbucket`
- `--fix`: Diagnose and fix a failing CI pipeline

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Read the tech stack and generate a complete, working pipeline
- Replace all placeholders with actual commands
- Validate the pipeline configuration

**Safety:**
- Never overwrite existing CI config without showing diff
- Preserve custom jobs the user has added
- Use environment secrets for sensitive values

### Actions

#### Generate (`/ci generate`)

Create CI/CD pipeline from scratch:

1. **Read `prd/00_technology.md`** for commands and tools
2. **Read `.github/workflows/README.md`** for pipeline documentation
3. **Read `ci.yml.example`** as the base template
4. **Replace all `{placeholders}`** with actual commands
5. **Write `.github/workflows/ci.yml`**
6. **Validate YAML syntax**

**Pipeline stages (required):**

```yaml
jobs:
  lint:        # Lint + format check
  typecheck:   # Static type checking
  test:        # Tests with coverage (fail if below minimum)
  security:    # Dependency + code security scan
  build:       # Build application / container
```

**Pipeline stages (optional, add if applicable):**

```yaml
  deploy-staging:   # Deploy to staging (on push to main)
  deploy-production: # Deploy to production (on release tag)
  e2e:              # End-to-end tests (after staging deploy)
```

#### Update (`/ci update`)

Update existing pipeline:

1. **Read current `.github/workflows/ci.yml`**
2. **Compare against `prd/00_technology.md`** for any command changes
3. **Identify stale placeholders** or outdated commands
4. **Apply updates** while preserving custom jobs
5. **Show diff** before writing

#### Fix (`/ci fix`)

Diagnose and fix failing CI:

1. **Check recent CI runs**:
   ```bash
   gh run list --limit 5
   ```
2. **Get failure details**:
   ```bash
   gh run view {run_id} --log-failed
   ```
3. **Diagnose the failure**:
   - Missing dependencies
   - Environment variable not set
   - Test failures
   - Version mismatches
4. **Apply fix** and push

#### Status (`/ci status`)

Show current CI pipeline health:

```bash
gh run list --limit 10
gh workflow list
```

### Platform-Specific Configuration

#### GitHub Actions (default)

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: {setup_action}  # e.g., actions/setup-node@v4
      - run: {install_command}
      - run: {lint_check_command}
      - run: {format_check_command}
```

#### Mobile-Specific Jobs

**iOS (Fastlane):**
```yaml
  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: bundle install
      - run: bundle exec fastlane test
      - run: bundle exec fastlane build
```

**Android (Gradle):**
```yaml
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - run: ./gradlew test
      - run: ./gradlew assembleRelease
```

#### Docker Build

```yaml
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          tags: app:test
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### CI Config Checklist

- [ ] All placeholder commands replaced
- [ ] Coverage threshold set correctly
- [ ] Secrets referenced (not hardcoded)
- [ ] Caching configured for dependencies
- [ ] Matrix strategy for multiple versions (if needed)
- [ ] Branch protection rules documented

## Example Output

```
$ /ci generate --platform github

Reading tech stack...
  Language: Python 3.13
  Package Manager: uv
  Test: pytest
  Lint: ruff
  Type Check: mypy

Generating .github/workflows/ci.yml...

Pipeline:
  1. lint        → uv run ruff check src/ tests/
  2. typecheck   → uv run mypy src/
  3. test        → uv run pytest --cov=src --cov-fail-under=66
  4. security    → uv run pip-audit && uv run bandit -r src/
  5. build       → docker build -t app:test .

Created .github/workflows/ci.yml
Validated YAML syntax: OK

Next steps:
1. Review the generated pipeline
2. Add repository secrets (if needed): Settings → Secrets
3. Push to trigger first run
```
