# CI/CD Workflows

This directory contains GitHub Actions workflow templates for continuous integration and deployment.

## Setup Instructions

### 1. Copy CI Template

```bash
# Copy the example to create your CI workflow
cp .github/workflows/ci.yml.example .github/workflows/ci.yml
```

### 2. Customize for Your Tech Stack

Edit `.github/workflows/ci.yml` and replace all `{placeholders}` with your actual commands from `prd/02_Tech_stack.md`.

**Key Sections to Customize:**

#### Language Setup
```yaml
- name: Setup {language}
  # Uncomment and configure for your language:
  # Python:
  uses: actions/setup-python@v5
  with:
    python-version: '3.13'
    cache: 'uv'
  
  # Node.js:
  # uses: actions/setup-node@v4
  # with:
  #   node-version: '22'
  #   cache: 'npm'
  
  # Go:
  # uses: actions/setup-go@v5
  # with:
  #   go-version: '1.22'
```

#### Package Manager Commands
Replace `{package_manager} install` with:
- Python: `uv sync`
- Node.js: `npm ci` or `pnpm install --frozen-lockfile`
- Go: `go mod download`

#### Quality Check Commands
Replace placeholders with commands from `prd/02_Tech_stack.md`:
- `{lint_check_command}` → Your lint command
- `{format_check_command}` → Your format check command
- `{type_check_command}` → Your type check command
- `{test_unit_command}` → Your unit test command
- `{test_integration_command}` → Your integration test command
- `{test_coverage_command}` → Your coverage command
- `{coverage_threshold_check}` → Your coverage threshold check
- `{dependency_scan_command}` → Your dependency scan command
- `{security_scan_command}` → Your security scan command
- `{build_command}` → Your build command

### 3. Configure Coverage Threshold

Set your minimum coverage threshold (typically 66-100% as defined in `prd/02_Tech_stack.md`):

```yaml
# Example for Python
uv run pytest --cov=src --cov-fail-under=66

# Example for Node.js
npm run test:coverage -- --coverageThreshold='{"global":{"branches":66}}'

# Example for Go
go tool cover -func=coverage.out | grep total | awk '{if ($3+0 < 66) exit 1}'
```

### 4. Configure Database Service

If using PostgreSQL, the template includes a service. Customize if needed:

```yaml
services:
  postgres:
    image: postgres:16  # Change version if needed
    env:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: test_db
```

For other databases (MySQL, MongoDB, etc.), add appropriate service configuration.

### 5. Optional: Codecov Integration

For coverage reporting, add your Codecov token:

1. Go to https://codecov.io and sign up
2. Add your repository
3. Copy your repository token
4. Add to GitHub Secrets: `Settings → Secrets → New repository secret`
5. Name: `CODECOV_TOKEN`
6. Value: Your Codecov token

The workflow will automatically upload coverage reports.

### 6. Test the Workflow

```bash
# Commit and push your changes
git add .github/workflows/ci.yml
git commit -m "ci: add CI pipeline with quality gates"
git push

# Check Actions tab in GitHub to see the workflow run
```

## Quality Gates

The CI pipeline enforces **5 quality gates** that must all pass:

### 1. Lint & Format ✅
- Code linting
- Format checking
- **Must pass** before merge

### 2. Type Check ✅
- Static type checking
- **Must pass** before merge
- Can be disabled for languages without static typing

### 3. Test & Coverage ✅
- Unit tests
- Integration tests
- Coverage reporting
- Coverage threshold enforcement
- **Must pass** before merge

### 4. Security Scan ✅
- Dependency vulnerability scanning
- Static security analysis
- Secret scanning
- **Warnings allowed**, critical issues block merge

### 5. Build ✅
- Application build verification
- **Must pass** before merge

## Workflow Features

### Concurrency Control
- Cancels in-progress runs when new commits are pushed
- Prevents duplicate runs for the same branch

### Artifact Uploads
- Test results (on failure)
- Coverage reports (always)
- Security reports (always)
- Build artifacts (on success)

### PR Comments
- Automatic comments on PRs with quality gate results
- Security findings notifications

### Timeouts
- Each job has a timeout to prevent hanging builds
- Default: 10-15 minutes per job

## Customization Examples

### Python Project

```yaml
- name: Setup Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.13'
    cache: 'uv'

- name: Install dependencies
  run: uv sync

- name: Run linter
  run: uv run ruff check src/ tests/

- name: Check formatting
  run: uv run ruff format --check src/ tests/

- name: Run type checker
  run: uv run mypy src/

- name: Run tests with coverage
  run: uv run pytest --cov=src --cov-report=xml --cov-fail-under=66

- name: Dependency scan
  run: uv run pip-audit

- name: Security scan
  run: uv run bandit -r src/
```

### TypeScript/Node.js Project

```yaml
- name: Setup Node.js
  uses: actions/setup-node@v4
  with:
    node-version: '22'
    cache: 'npm'

- name: Install dependencies
  run: npm ci

- name: Run linter
  run: npm run lint

- name: Check formatting
  run: npm run format:check

- name: Run type checker
  run: npm run typecheck

- name: Run tests with coverage
  run: npm run test:coverage

- name: Dependency scan
  run: npm audit --audit-level=moderate

- name: Security scan
  run: npm run lint:security
```

### Go Project

```yaml
- name: Setup Go
  uses: actions/setup-go@v5
  with:
    go-version: '1.22'

- name: Install dependencies
  run: go mod download

- name: Run linter
  run: golangci-lint run

- name: Check formatting
  run: gofmt -l . | grep -q . && exit 1 || exit 0

- name: Run tests with coverage
  run: go test ./... -coverprofile=coverage.out

- name: Check coverage threshold
  run: go tool cover -func=coverage.out | grep total | awk '{if ($3+0 < 66) exit 1}'

- name: Dependency scan
  run: govulncheck ./...

- name: Security scan
  run: gosec ./...

- name: Build
  run: go build ./...
```

## Troubleshooting

### Workflow Fails on First Run

**Common Issues:**
1. **Missing commands:** Ensure all placeholder commands are replaced
2. **Wrong package manager:** Verify package manager matches your setup
3. **Database connection:** Check database service configuration
4. **Missing dependencies:** Verify all dependencies are in lock files

**Solution:**
- Check workflow logs in GitHub Actions tab
- Verify commands work locally first
- Test each job individually

### Coverage Threshold Failing

**Issue:** Coverage is below threshold

**Solution:**
1. Check current coverage: `{test_coverage_command}`
2. Either:
   - Increase test coverage
   - Lower threshold (not recommended)
   - Exclude files from coverage (if appropriate)

### Security Scan Failing

**Issue:** Security scan finds vulnerabilities

**Solution:**
1. Review security reports artifact
2. Fix critical vulnerabilities immediately
3. Plan fixes for medium/low severity
4. Use `continue-on-error: true` only for warnings, not critical issues

### Build Failing

**Issue:** Build step fails

**Solution:**
1. Test build locally: `{build_command}`
2. Check for missing dependencies
3. Verify build configuration
4. Check for platform-specific issues

## Advanced Configuration

### Matrix Testing

Test against multiple language versions:

```yaml
strategy:
  matrix:
    python-version: ['3.11', '3.12', '3.13']
  steps:
    - uses: actions/setup-python@v5
      with:
        python-version: ${{ matrix.python-version }}
```

### Conditional Jobs

Skip jobs based on conditions:

```yaml
typecheck:
  if: github.event.pull_request.draft == false
```

### Deployment Jobs

Add deployment after quality gates pass:

```yaml
deploy:
  name: Deploy
  needs: [quality-gate]
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  runs-on: ubuntu-latest
  steps:
    - name: Deploy to staging
      run: echo "Deploy to staging"
```

## Best Practices

1. **Keep workflows fast:** Use caching, parallel jobs, and appropriate timeouts
2. **Fail fast:** Run quick checks (lint, format) before slow checks (tests)
3. **Cache dependencies:** Use GitHub Actions cache for package managers
4. **Review security reports:** Don't ignore security findings
5. **Maintain coverage:** Keep test coverage above threshold
6. **Update regularly:** Keep actions and tools updated

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Quality Standards](../prd/01_Technical_standards.md)
- [Tech Stack Configuration](../prd/02_Tech_stack.md)
- [Security Standards](../prd/03_Security.md)
