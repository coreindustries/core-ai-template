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

.PHONY: help setup dev test start _start-inner test-hermetic doctor lint format typecheck security scan-secrets deps-audit quality db-start db-stop db-new db-reset db-types db-test db-push db-diff check-migrations wt wt-list wt-remove clean enable-rules enable-ts pr-check lanes-init lanes-check lanes-test ratchet

# =============================================================================
# Secret Injection (see .claude/rules/secrets-hygiene.md)
# =============================================================================
# All runtime commands flow through WRAPPER, so plaintext secrets never touch
# disk. This template names no secret-manager vendor: WRAPPER is the seam your
# project fills in.
#
# THE CONTRACT a wrapper must satisfy:
#   1. Fetch secrets from your secret store at invocation time.
#   2. `exec` the child process with them in its environment.
#   3. Never write them to a file — plaintext must live only in process
#      memory, and die with the process.
#
# Any tool meeting that contract works. It is a prefix, ending in `--` if the
# tool requires one, e.g.:
#   WRAPPER ?= <secret-cli> exec <service> --
#   WRAPPER ?= <secret-cli> run --env-file=.env.tpl --
#
# UNSET IS A VALID STATE. With no WRAPPER, commands run without injection and
# the app's own fail-closed check (secrets-hygiene.md Rule 8) reports which
# variables are missing. That keeps an uninitialized template runnable.
#
# Override per project:
#   SERVICE_NAME:  logical service name, if your wrapper scopes secrets by one
#   RUNNER:        your project's run command (e.g. npm run, uv run, go run)
#   WRAPPER:       the secret-injection prefix described above
# =============================================================================

SERVICE_NAME ?= $(shell basename $(CURDIR))
WRAPPER      ?=
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
	@echo "Secrets are injected into process memory at runtime by WRAPPER."
	@echo "See .claude/rules/secrets-hygiene.md"
	@echo ""
	@echo "First-time setup:"
	@echo "  1. Install tooling:"
	@echo "       brew install gitleaks supabase/tap/supabase"
	@echo "  2. Choose a secret manager and set WRAPPER in this Makefile."
	@echo "       It must exec the child process with secrets in its env,"
	@echo "       and never write them to disk. Currently: '$(WRAPPER)'"
	@echo "  3. Load your team's secrets into that store, then list the"
	@echo "       expected variable names in .env.tpl (references only)."
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

dev:  ## Start dev server with secrets injected into process memory
	$(WRAPPER) $(RUNNER) dev

start:  ## Start production server locally (uses PROD_WRAPPER if set)
	@$(MAKE) WRAPPER="$(if $(PROD_WRAPPER),$(PROD_WRAPPER),$(WRAPPER))" _start-inner

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

db-push: ## Push migrations to a remote DB (run through WRAPPER; e.g. make db-push ENV=staging)
	@test -n "$(DATABASE_URL)" || (echo "DATABASE_URL not set — run it through your secret wrapper, e.g. $(WRAPPER) make db-push" && exit 1)
	supabase db push --db-url "$(DATABASE_URL)"

db-diff: ## Show schema drift between local migrations and a linked remote
	supabase db diff --linked

check-migrations: ## Verify migration conventions
	@scripts/assert-migration-conventions.sh

# =============================================================================
# Testing
# =============================================================================

test:  ## Run tests with secrets injected into process memory
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
	@echo ""
	@echo "Auditing for known vulnerabilities..."
	@scripts/audit-dependencies.sh
	@echo "  ✓ deps pinned + aged + audited"

ratchet: ## Ratchet gates: fail on regression AND on stale-baseline slack (.claude/ratchets.json). CI itself runs non-strict; use --update to resync.
	@node scripts/ratchet.mjs --strict

agent-models: ## Write .claude/agent-models.json pins into agent frontmatter
	@node scripts/sync-agent-models.mjs

agent-models-check: ## Verify agent frontmatter matches .claude/agent-models.json
	@node scripts/sync-agent-models.mjs --check

deps-vuln: ## Audit only the dependency manifests this branch changed
	@scripts/audit-dependencies.sh --changed-only

pr-check: ## Run the PR gates locally before a push (usage: make -C <pr-worktree> pr-check BODY=body.md [BASE=main])
	@test -n "$(BODY)" || (echo "usage: make -C <pr-worktree> pr-check BODY=body.md [BASE=main]" && exit 1)
	@scripts/dev/board/pr-check.sh "$(abspath $(BODY))" $(BASE)

lanes-init: ## Agent lanes: validate .claude/agent-lanes.json and create the lane labels in this repo
	@scripts/dev/board/lanes-config.sh check
	@scripts/dev/board/board.sh init-labels

lanes-check: ## Agent lanes: validate .claude/agent-lanes.json
	@scripts/dev/board/lanes-config.sh check

lanes-test: ## Agent lanes: run the board tooling + hook tests (no network)
	@scripts/dev/board/tests/run-all.sh

contract-check: ## Dry-run the delivery-contract gate against this PR's body
	@gh pr view --json body -q .body 2>/dev/null \
	  | MODE=warn scripts/pr-delivery-contract-check.sh \
	  || echo "  (no open PR for this branch — nothing to check)"

doctor:  ## Audit the project for secret-hygiene + dep compliance
	@echo "Checking for plaintext .env files..."
	@scripts/assert-no-plaintext-env.sh && echo "  ✓ no plaintext .env files" || exit 1
	@echo "Checking secret injection is configured..."
ifeq ($(strip $(WRAPPER)),)
	@echo "  ⚠ WRAPPER unset — no secret injection configured."
	@echo "    Expected on an uninitialized template; set it before handling real secrets."
	@echo "    See the Secret Injection block at the top of this Makefile."
else
	@echo "  ✓ WRAPPER set: $(WRAPPER)"
	@command -v $(firstword $(WRAPPER)) >/dev/null 2>&1 \
	  && echo "  ✓ $(firstword $(WRAPPER)) on PATH" \
	  || (echo "  ✗ $(firstword $(WRAPPER)) not found on PATH" && exit 1)
endif
	@echo "Checking gitleaks is installed..."
	@command -v gitleaks >/dev/null 2>&1 && echo "  ✓ gitleaks installed" || (echo "  ✗ gitleaks missing. brew install gitleaks" && exit 1)
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
	@echo "=== Ratchet gates ==="
	@node scripts/ratchet.mjs --strict
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
	@test -n "$(WRAPPER)" && echo "  ✓ WRAPPER set" || echo "  ✗ WRAPPER unset — no secret injection configured"
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
	@TOP=$$(git rev-parse --show-toplevel); \
	 REPO=$$(basename "$$TOP"); \
	 PARENT=$$(dirname "$$TOP"); \
	 WT="$$PARENT/$$REPO-$(name)"; \
	 git fetch origin main && \
	 git worktree add "$$WT" -b "$(name)" origin/main && \
	 echo "" && \
	 echo "WORKTREE_PATH=$$WT" && \
	 echo "" && \
	 echo "From a shell:   cd $$WT" && \
	 echo "From Claude:    EnterWorktree path:\"$$WT\"" && \
	 echo "" && \
	 echo "Next steps (in the new worktree):" && \
	 echo "  make install        # per-worktree dependency install" && \
	 echo "  make db-start       # local Supabase (stop main worktree's first if port collides)" && \
	 echo "" && \
	 echo "See docs/runbooks/multi-agent-worktrees.md for coordination patterns."

wt-list: ## List active worktrees
	@git worktree list

wt-remove: ## Remove a worktree and delete its branch (usage: make wt-remove name=<branch>)
	@test -n "$(name)" || (echo "usage: make wt-remove name=<branch>" && exit 1)
	@TOP=$$(git rev-parse --show-toplevel); \
	 REPO=$$(basename "$$TOP"); \
	 PARENT=$$(dirname "$$TOP"); \
	 git worktree remove "$$PARENT/$$REPO-$(name)" && \
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
	@echo "  make enable-ts        # TypeScript (strict tsconfig, ESLint, tsc)"
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

enable-ts: ## Enable rules for TypeScript projects (strict tsconfig, ESLint, tsc)
	@ln -sf ../rules-available/typescript.md .claude/rules/typescript.md
	@ln -sf ../rules-available/security-owasp.md .claude/rules/security-owasp.md
	@echo "Enabled: typescript, security-owasp"
