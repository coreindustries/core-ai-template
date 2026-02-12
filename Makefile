# =============================================================================
# Project Makefile
# =============================================================================
# Replace {placeholders} with your stack's commands from prd/02_Tech_stack.md
#
# Usage:
#   make setup     # First-time project setup
#   make dev       # Start development
#   make test      # Run tests
#   make quality   # Full quality check
#   make help      # Show all targets
# =============================================================================

.PHONY: help setup dev test lint format typecheck security quality db-generate db-migrate db-push clean enable-rules

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# Setup
# =============================================================================

setup: ## First-time project setup (run once)
	@echo "Setting up project..."
	@test -f .env || cp .env.example .env && echo "  Created .env from .env.example"
	@echo "  Installing dependencies..."
	{install_command}
	@echo "  Generating database client..."
	{db_generate}
	@echo "  Running migrations..."
	{db_migrate}
	@echo "  Configuring git..."
	git config commit.template .gitmessage
	@echo ""
	@echo "Setup complete! Run 'make dev' to start developing."

install: ## Install dependencies
	{install_command}

# =============================================================================
# Development
# =============================================================================

dev: ## Start development server with hot reload
	{start_dev_server}

deps: ## Start external dependencies (database, cache, etc.)
	{start_dependencies}

deps-stop: ## Stop external dependencies
	{docker_stop_command}

# =============================================================================
# Database
# =============================================================================

db-generate: ## Generate database client after schema changes
	{db_generate}

db-migrate: ## Create and run migrations
	{db_migrate}

db-push: ## Push schema changes (dev only, no migration)
	{schema_push_command}

# =============================================================================
# Testing
# =============================================================================

test: ## Run all tests
	{test_all_command}

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

check-env: ## Verify environment setup
	@echo "Checking environment..."
	@test -f .env && echo "  .env exists" || echo "  WARNING: .env missing (run 'make setup')"
	@command -v {package_manager} >/dev/null 2>&1 && echo "  {package_manager} installed" || echo "  WARNING: {package_manager} not found"
	@echo "  Git branch: $$(git branch --show-current)"
	@echo "  Git status: $$(git status --porcelain | wc -l | tr -d ' ') uncommitted changes"
	@echo "  Auto-loaded rules:"
	@ls -1 .claude/rules/*.md 2>/dev/null | sed 's/.*\//    /' || echo "    (none)"

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
