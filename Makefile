# =============================================================================
# Project Makefile
# =============================================================================
# Replace {placeholders} with your stack's commands from prd/00_technology.md
#
# Usage:
#   make setup     # First-time project setup
#   make dev       # Start development
#   make test      # Run tests
#   make quality   # Full quality check
#   make help      # Show all targets
# =============================================================================

.PHONY: help setup dev test start _start-inner test-hermetic doctor lint format typecheck security scan-secrets deps-audit quality db-start db-stop db-new db-reset db-types db-test db-push db-diff check-migrations wt wt-list wt-remove clean enable-rules

# =============================================================================
# Secret Injection (see .claude/rules/secrets-hygiene.md)
# =============================================================================
# All runtime commands flow through the wrapper. Plaintext secrets never
# touch disk — they are fetched from AWS SSM / Secrets Manager into the
# child process's memory by `chamber`, using short-lived AWS credentials
# obtained by `aws-vault` from the OS keychain (not ~/.aws/credentials).
#
# Override per project:
#   AWS_PROFILE:   your SSO profile name (default: core-dev)
#   SERVICE_NAME:  chamber service prefix (default: current directory name)
#   RUNNER:        your project's run command (e.g. npm run, uv run, go run)
#   WRAPPER:       fully override the wrapper chain if needed
# =============================================================================

AWS_PROFILE  ?= core-dev
SERVICE_NAME ?= $(shell basename $(CURDIR))
WRAPPER      ?= aws-vault exec $(AWS_PROFILE) -- chamber exec $(SERVICE_NAME) --
RUNNER       ?= {runner_command}

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# Setup
# =============================================================================

setup: ## First-time project setup (run once)
	@echo "Setting up project..."
	@echo ""
	@echo "NOTE: This project does not use a plaintext .env file."
	@echo "Secrets are injected at runtime by: $(WRAPPER)"
	@echo "See .claude/rules/secrets-hygiene.md"
	@echo ""
	@echo "First-time setup:"
	@echo "  1. Install wrapper tools:"
	@echo "       brew install aws-vault chamber gitleaks supabase/tap/supabase"
	@echo "  2. Configure SSO:"
	@echo "       aws configure sso --profile $(AWS_PROFILE)"
	@echo "  3. Populate SSM with your team's secrets (one-time, by an admin):"
	@echo "       aws-vault exec $(AWS_PROFILE) -- chamber write $(SERVICE_NAME) database_url '<value>'"
	@echo "  4. Fill in prd/00_technology.md, then run:"
	@echo "       make install"
	@echo "       make db-start     # start local Supabase"
	@echo "       make db-reset     # apply migrations"
	@echo "  5. Run: make doctor"
	@echo "  6. Run: make dev"
	@echo ""
	@echo "Configuring git commit template..."
	@test -f .gitmessage && git config commit.template .gitmessage || echo "  (skipped — no .gitmessage)"
	@echo ""
	@echo "Setup guidance printed. Run the commands above in order."

install: ## Install dependencies
	{install_command}

# =============================================================================
# Development
# =============================================================================

dev:  ## Start dev server with secrets injected from AWS
	$(WRAPPER) $(RUNNER) dev

start:  ## Start production server locally (requires prod SSO profile)
	@$(MAKE) AWS_PROFILE=core-prod _start-inner

_start-inner:
	$(WRAPPER) $(RUNNER) start

deps: ## Start external dependencies (database, cache, etc.)
	{start_dependencies}

deps-stop: ## Stop external dependencies
	{docker_stop_command}

# =============================================================================
# Database (Supabase default — see .claude/rules/database-migrations.md)
# =============================================================================

db-start: ## Start local Supabase stack (Postgres + PostgREST + ...)
	supabase start

db-stop: ## Stop local Supabase stack
	supabase stop

db-new: ## Create a new migration file (usage: make db-new name=add_users_table)
	@test -n "$(name)" || (echo "usage: make db-new name=<imperative_snake_case>" && exit 1)
	supabase migration new $(name)

db-reset: ## Reset local DB and apply all migrations from scratch (destructive — local only)
	supabase db reset

db-types: ## Regenerate types from current local schema
	supabase gen types typescript --local > src/types/supabase.ts

db-test: ## Run pgTAP tests against local Supabase
	supabase test db

db-push: ## Push migrations to a remote DB (use with chamber; e.g. make db-push ENV=staging)
	@test -n "$(DATABASE_URL)" || (echo "DATABASE_URL not set — run via: chamber exec <service> -- make db-push" && exit 1)
	supabase db push --db-url "$(DATABASE_URL)"

db-diff: ## Show schema drift between local migrations and a linked remote
	supabase db diff --linked

check-migrations: ## Verify migration conventions
	@scripts/assert-migration-conventions.sh

# =============================================================================
# Testing
# =============================================================================

test:  ## Run tests with secrets injected from AWS
	$(WRAPPER) $(RUNNER) test

test-hermetic:  ## Run unit tests with NO secrets loaded (catches "hit prod by accident" bugs)
	@scripts/assert-no-secrets.sh
	$(RUNNER) test

test-unit: ## Run unit tests only
	{test_unit_command}

test-integration: ## Run integration tests only
	{test_integration_command}

test-coverage: ## Run tests with coverage report
	{test_coverage_command}

test-watch: ## Run tests in watch mode
	{test_watch_command}

test-fast: ## Run tests, stop on first failure
	{test_stop_first_command}

# =============================================================================
# Code Quality
# =============================================================================

lint: ## Run linter
	{lint_check_command}

lint-fix: ## Run linter with auto-fix
	{lint_fix_command}

format: ## Check formatting
	{format_check_command}

format-fix: ## Fix formatting
	{format_fix_command}

typecheck: ## Run type checker
	{type_check_command}

security: ## Run security scanner
	{security_scan_command}

scan-secrets: ## Scan for secrets and PII (gitleaks)
	@scripts/scan-secrets.sh --all

deps-audit: ## Enforce dependency pinning + 24h cooldown (see dependency-security.md)
	@echo "Checking dependency age (≥ 24h cooldown)..."
	@scripts/assert-dependency-age.sh
	@echo ""
	@echo "Checking manifests for floating ranges..."
	@if [ -f package.json ]; then \
	  node -e "const p=require('./package.json');const bad=[];for(const s of ['dependencies','devDependencies','peerDependencies']){for(const[k,v]of Object.entries(p[s]||{})){if(/^[\^~*]|^latest$|^>/.test(v))bad.push(\`\${s}.\${k}=\${v}\`);}}if(bad.length){console.error('Unpinned deps:');bad.forEach(b=>console.error(' '+b));process.exit(1);}" ; \
	fi
	@if [ -f pyproject.toml ]; then \
	  if grep -E '^[a-zA-Z0-9_-]+\s*=\s*"[\^~>]' pyproject.toml | grep -v '^\s*#'; then \
	    echo "Unpinned deps in pyproject.toml (use exact versions: ==x.y.z)" && exit 1; \
	  fi ; \
	fi
	@echo "  ✓ deps pinned + aged"

doctor:  ## Audit the project for secret-hygiene + dep compliance
	@echo "Checking for plaintext .env files..."
	@scripts/assert-no-plaintext-env.sh && echo "  ✓ no plaintext .env files" || exit 1
	@echo "Checking aws-vault is installed..."
	@command -v aws-vault >/dev/null 2>&1 && echo "  ✓ aws-vault installed" || (echo "  ✗ aws-vault missing. brew install aws-vault" && exit 1)
	@echo "Checking chamber is installed..."
	@command -v chamber >/dev/null 2>&1 && echo "  ✓ chamber installed" || (echo "  ✗ chamber missing. brew install chamber" && exit 1)
	@echo "Checking gitleaks is installed..."
	@command -v gitleaks >/dev/null 2>&1 && echo "  ✓ gitleaks installed" || (echo "  ✗ gitleaks missing. brew install gitleaks" && exit 1)
	@echo "Checking SSO profile is configured..."
	@aws configure list-profiles | grep -q "^$(AWS_PROFILE)$$" && echo "  ✓ profile $(AWS_PROFILE) configured" || (echo "  ✗ AWS profile $(AWS_PROFILE) not configured. Run: aws configure sso --profile $(AWS_PROFILE)" && exit 1)
	@echo "Checking supabase CLI is installed..."
	@command -v supabase >/dev/null 2>&1 && echo "  ✓ supabase installed" || echo "  ⚠ supabase CLI missing (brew install supabase/tap/supabase) — skip if project doesn't use Supabase"
	@echo "Running gitleaks on working tree..."
	@gitleaks detect --config .gitleaks.toml --no-banner --redact && echo "  ✓ no secrets detected" || exit 1
	@echo "Verifying migration conventions..."
	@scripts/assert-migration-conventions.sh
	@echo ""
	@echo "✅ Secrets hygiene + migration conventions passed."

quality: ## Run full quality suite (lint + format + typecheck + security + test)
	@echo "Running full quality check..."
	@echo ""
	@echo "=== Lint ==="
	{lint_fix_command}
	@echo ""
	@echo "=== Type Check ==="
	{type_check_command}
	@echo ""
	@echo "=== Security ==="
	{security_scan_command}
	@echo ""
	@echo "=== Secrets & PII ==="
	@scripts/scan-secrets.sh --all
	@echo ""
	@echo "=== Tests ==="
	{test_coverage_command}
	@echo ""
	@echo "All quality checks passed!"

# =============================================================================
# Utilities
# =============================================================================

clean: ## Remove build artifacts and caches
	@echo "Cleaning build artifacts..."
	rm -rf dist/ build/ .cache/ coverage/ htmlcov/ .pytest_cache/ .mypy_cache/ .ruff_cache/
	rm -rf node_modules/.cache/ .next/ .turbo/
	@echo "Clean complete."

check-env: ## Verify environment setup (no plaintext .env expected)
	@echo "Checking environment..."
	@test -f .env.tpl && echo "  ✓ .env.tpl present (reference file)" || echo "  ⚠ .env.tpl missing"
	@test -f .env && echo "  ✗ .env present — FORBIDDEN (see .claude/rules/secrets-hygiene.md)" || echo "  ✓ no plaintext .env"
	@command -v aws-vault >/dev/null 2>&1 && echo "  ✓ aws-vault installed" || echo "  ✗ aws-vault missing"
	@command -v chamber >/dev/null 2>&1 && echo "  ✓ chamber installed" || echo "  ✗ chamber missing"
	@command -v {package_manager} >/dev/null 2>&1 && echo "  ✓ {package_manager} installed" || echo "  ⚠ {package_manager} not found"
	@echo "  Git branch: $$(git branch --show-current)"
	@echo "  Git status: $$(git status --porcelain | wc -l | tr -d ' ') uncommitted changes"
	@echo "  Auto-loaded rules:"
	@ls -1 .claude/rules/*.md 2>/dev/null | sed 's/.*\//    /' || echo "    (none)"

# =============================================================================
# Worktrees — parallel agent isolation (see docs/runbooks/multi-agent-worktrees.md)
# =============================================================================

wt: ## Create a worktree off origin/main (usage: make wt name=<branch>)
	@test -n "$(name)" || (echo "usage: make wt name=<branch>" && exit 1)
	@REPO=$$(basename $$(git rev-parse --show-toplevel)); \
	 WT="../$$REPO-$(name)"; \
	 git fetch origin main && \
	 git worktree add "$$WT" -b "$(name)" origin/main && \
	 echo "" && \
	 echo "Worktree created: $$WT" && \
	 echo "  cd $$WT" && \
	 echo "  make install        # per-worktree dependency install" && \
	 echo "  make db-start       # local Supabase (stop main worktree's first if port collides)" && \
	 echo "See docs/runbooks/multi-agent-worktrees.md for coordination patterns."

wt-list: ## List active worktrees
	@git worktree list

wt-remove: ## Remove a worktree and delete its branch (usage: make wt-remove name=<branch>)
	@test -n "$(name)" || (echo "usage: make wt-remove name=<branch>" && exit 1)
	@REPO=$$(basename $$(git rev-parse --show-toplevel)); \
	 git worktree remove "../$$REPO-$(name)" && \
	 git branch -d "$(name)" && \
	 echo "Removed worktree and branch: $(name)"

# =============================================================================
# Context Management
# =============================================================================

enable-rules: ## Symlink platform-specific rules (interactive)
	@echo "Available platform rules in .claude/rules-available/:"
	@echo ""
	@ls -1 .claude/rules-available/*.md 2>/dev/null | sed 's/.*\//  /'
	@echo ""
	@echo "To enable a rule, symlink it into .claude/rules/:"
	@echo "  ln -s ../rules-available/<rule>.md .claude/rules/<rule>.md"
	@echo ""
	@echo "Common presets:"
	@echo "  make enable-web       # Next.js / React web app"
	@echo "  make enable-api       # Backend API (any stack)"
	@echo "  make enable-mobile    # React Native mobile app"
	@echo "  make enable-docker    # Dockerized / containerized project"
	@echo "  make enable-python    # Python (uv, ruff, FastAPI)"
	@echo "  make enable-ios       # Native iOS (Swift / SwiftUI)"
	@echo "  make enable-android   # Native Android (Kotlin / Compose)"

enable-web: ## Enable rules for Next.js / React web projects
	@ln -sf ../rules-available/nextjs.md .claude/rules/nextjs.md
	@ln -sf ../rules-available/security-web.md .claude/rules/security-web.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: nextjs, security-web, security-owasp"

enable-api: ## Enable rules for backend API projects
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: security-owasp"

enable-mobile: ## Enable rules for React Native mobile projects
	@ln -sf ../rules-available/security-mobile.md .claude/rules/security-mobile.md
	@ln -sf ../rules-available/security-web.md .claude/rules/security-web.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: security-mobile, security-web, security-owasp"

enable-python: ## Enable rules for Python (uv/ruff/FastAPI) projects
	@ln -sf ../rules-available/python.md .claude/rules/python.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: python, security-owasp"

enable-docker: ## Enable rules for Dockerized projects
	@ln -sf ../rules-available/docker.md .claude/rules/docker.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: docker, security-owasp"

enable-ios: ## Enable rules for native iOS (Swift/SwiftUI) projects
	@ln -sf ../rules-available/ios.md .claude/rules/ios.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: ios, security-owasp"

enable-android: ## Enable rules for native Android (Kotlin/Compose) projects
	@ln -sf ../rules-available/android.md .claude/rules/android.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: android, security-owasp"
