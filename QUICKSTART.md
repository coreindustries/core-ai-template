# Quick Start Guide

> **Note:** This is a detailed walkthrough. For a quick overview, see [README.md](README.md#getting-started).

Get your project up and running in **15 minutes** with AI agent-assisted development.

---

## Prerequisites

- Git installed
- Your chosen language runtime (Python, Node.js, Go, etc.)
- Docker (for local database/cache)
- Code editor (VS Code or Cursor recommended)

---

## Step 1: Initialize Project (5 minutes)

### 1.1 Copy Template

```bash
# Clone or copy this template
git clone <template-repo-url> my-project
cd my-project

# Or copy directory
cp -r core-ai-template my-project
cd my-project

# Initialize git (if copying)
git init
git add .
git commit -m "chore: initial project setup"
```

### 1.2 Configure Tech Stack

Edit `prd/02_Tech_stack.md` and fill in your technology choices:

**Quick Reference:**
- **Python:** See README.md → Python example
- **TypeScript/Node.js:** See README.md → Node.js example
- **Go:** See README.md → Go example

**Minimum Required Sections:**
- Language & Runtime (Section 1)
- Package Manager (Section 1.2)
- Database (Section 2)
- ORM (Section 3)
- API Framework (Section 4)
- Testing (Section 8)
- Code Quality Tools (Section 9)

### 1.3 Update Project Commands

Edit `CLAUDE.md` and replace placeholders with your actual commands:

```bash
# Find and replace these patterns:
{package_manager} → uv / bun / pnpm / etc.
{runner} → uv run / bun / pnpm exec / etc.
{start_dev_server} → your dev server command
```

### 1.4 Set Up Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
# Minimum required:
# - DATABASE_URL
# - LOG_LEVEL
# - ENVIRONMENT
```

### 1.5 Configure Git Commit Template

```bash
# Configure git to use the commit message template
git config commit.template .gitmessage

# Or set globally for all repositories
git config --global commit.template ~/.gitmessage
cp .gitmessage ~/.gitmessage
```

This will show the conventional commit format guide when you run `git commit` (without `-m`).

---

## Step 2: Scaffold Project Structure (5 minutes)

### 2.1 Run Initialization Skill

```bash
# In your AI coding assistant (Claude Code, Cursor, etc.)
/init --language {python|typescript|go} --with-db --with-api
```

This will create:
- `src/{project_name}/` directory structure
- Basic configuration files
- Test directory structure
- Docker Compose setup

### 2.2 Install Dependencies

```bash
# Use your package manager (see prd/02_Tech_stack.md)
{package_manager} install
```

### 2.3 Start Dependencies

```bash
# Start database and cache (if using Docker)
docker compose up -d

# Verify services are running
docker compose ps
```

### 2.4 Generate Database Client

```bash
# If using Prisma
{runner} prisma generate

# If using Drizzle
{runner} drizzle-kit generate

# If using other ORM, follow its setup instructions
```

---

## Step 3: Your First Feature (5 minutes)

### 3.1 Create Task File

```bash
# Create task tracking file
cp prd/tasks/TASK_TEMPLATE.md prd/tasks/hello_world_tasks.md
```

Edit `prd/tasks/hello_world_tasks.md`:
- Set feature name: "Hello World API"
- Add initial tasks
- Set branch: `feat/hello-world`

### 3.2 Create Feature Branch

```bash
git checkout -b feat/hello-world
```

### 3.3 Scaffold Feature

```bash
# In your AI coding assistant
/feature hello-world --scaffold --with-api --with-tests
```

This creates:
- API endpoint
- Service layer
- Models/schemas
- Unit tests
- Integration tests

### 3.4 Implement Feature

The AI agent will scaffold the basic structure. Review and customize:

```bash
# Review generated files
ls -la src/{project_name}/api/
ls -la src/{project_name}/services/
ls -la tests/unit/
```

### 3.5 Run Quality Checks

```bash
# Lint and format
/lint --fix

# Run tests
/test

# Type check (if applicable)
{type_check_command}
```

### 3.6 Save Progress

```bash
# Update task file with progress
/checkpoint
```

---

## Step 4: Verify Setup (2 minutes)

### 4.1 Run Full Quality Pipeline

```bash
# Run all quality checks
/lint
/test --coverage
/scan
```

**Expected Results:**
- ✅ Linting passes
- ✅ Tests pass (coverage may be low initially)
- ✅ Security scan passes (no critical issues)
- ✅ Type checking passes (if applicable)

### 4.2 Start Development Server

```bash
# Start your API server
{start_dev_server}

# In another terminal, test the endpoint
curl http://localhost:8000/health
# or
curl http://localhost:3000/api/health
```

### 4.3 Verify Database Connection

```bash
# Test database connection
{runner} {db_test_command}

# Or check via Docker
docker compose exec db psql -U {user} -d {database} -c "SELECT 1;"
```

---

## Common Workflows

### Starting a New Feature

```bash
# 1. Create task file
cp prd/tasks/TASK_TEMPLATE.md prd/tasks/{feature}_tasks.md

# 2. Create branch
git checkout -b feat/{feature}

# 3. Scaffold feature
/feature {feature} --scaffold

# 4. Implement and test
/lint --fix
/test
/checkpoint
```

### Before Committing

```bash
# 1. Run quality checks
/lint --fix
/test --coverage
/scan

# 2. Update task file
/checkpoint

# 3. Review changes
git status
git diff

# 4. Create commit
/commit
```

### Creating a Pull Request

```bash
# 1. Ensure all checks pass
/lint
/test --coverage
/scan

# 2. Push branch
git push origin feat/{feature}

# 3. Create PR
/pr
```

---

## Troubleshooting

### Issue: Package Manager Not Found

**Solution:**
```bash
# Install your package manager first
# Python: pip install uv
# Node.js: npm install -g bun
# Go: Already included
```

### Issue: Database Connection Failed

**Solution:**
```bash
# Check Docker is running
docker compose ps

# Check environment variables
cat .env | grep DATABASE_URL

# Restart services
docker compose restart
```

### Issue: Tests Failing

**Solution:**
```bash
# Run tests with verbose output
{test_command} --verbose

# Run specific test
{test_command} tests/unit/test_specific.{ext}

# Check test database setup
# See prd/02_Tech_stack.md for test configuration
```

### Issue: Linting Errors

**Solution:**
```bash
# Auto-fix what can be fixed
/lint --fix

# Review remaining issues
/lint

# Check linting configuration
# See prd/02_Tech_stack.md → Section 9
```

---

## Next Steps

### Immediate (Today)

1. ✅ Complete Quick Start steps above
2. ✅ Implement your first feature
3. ✅ Run quality checks successfully
4. ✅ Create your first commit

### Short Term (This Week)

1. **Read Core Documentation:**
   - `AGENTS.md` - AI agent quick reference
   - `prd/01_Technical_standards.md` - Code quality standards
   - `prd/03_Security.md` - Security requirements

2. **Set Up CI/CD:**
   - Copy `.github/workflows/ci.yml.example` to `.github/workflows/ci.yml`
   - Customize for your tech stack
   - Push to trigger first pipeline run

3. **Configure Editor:**
   - Install recommended VS Code/Cursor extensions
   - Configure settings from `.vscode/settings.json`

### Medium Term (This Month)

1. **Establish Patterns:**
   - Review `prd/patterns/` (if created)
   - Document project-specific patterns
   - Create reusable components

2. **Set Up Monitoring:**
   - Configure logging
   - Set up error tracking
   - Add metrics collection

3. **Security Hardening:**
   - Run `/scan` regularly
   - Review security checklist
   - Set up dependency scanning in CI/CD

---

## Getting Help

### Documentation

- **Project Overview:** `README.md`
- **AI Agent Guide:** `AGENTS.md`
- **Project Setup:** `CLAUDE.md`
- **Technical Standards:** `prd/01_Technical_standards.md`
- **Tech Stack:** `prd/02_Tech_stack.md`
- **Security:** `prd/03_Security.md`

### Skills Reference

Run `/help` in your AI coding assistant to see all available skills.

**Common Skills:**
- `/feature` - Create new feature
- `/test` - Run tests
- `/lint` - Code quality checks
- `/checkpoint` - Save progress
- `/commit` - Create commit
- `/pr` - Create pull request
- `/scan` - Security scan
- `/debug` - Debugging workflow

### Support

- Check `TROUBLESHOOTING.md` (if available)
- Review task files in `prd/tasks/` for examples
- Check CI/CD logs for build issues
- Review security scan reports

---

## Quick Reference Commands

```bash
# Development
{start_dev_server}              # Start API server
{start_dependencies}            # Start DB, cache, etc.

# Database
{db_generate}                   # Generate client
{db_migrate}                    # Run migrations

# Quality
/lint --fix                      # Lint and format
/test --coverage                 # Tests with coverage
/scan                            # Security scan

# Git
/commit                          # Create commit
/pr                              # Create pull request

# Productivity
/checkpoint                      # Save progress
/feature {name} --scaffold       # Scaffold feature
```

**Replace placeholders** (`{command}`) with actual commands from `prd/02_Tech_stack.md`.

---

## Success Checklist

Before considering setup complete, verify:

- [ ] Tech stack configured (`prd/02_Tech_stack.md` filled in)
- [ ] Project commands updated (`CLAUDE.md` customized)
- [ ] Environment variables set (`.env` configured)
- [ ] Git commit template configured (`git config commit.template .gitmessage`)
- [ ] Dependencies installed (`{package_manager} install`)
- [ ] Database running (`docker compose up -d`)
- [ ] Database client generated (`{db_generate}`)
- [ ] First feature scaffolded (`/feature hello-world`)
- [ ] Quality checks passing (`/lint`, `/test`, `/scan`)
- [ ] Development server starts (`{start_dev_server}`)
- [ ] First commit created (`/commit`)

**If all checked:** 🎉 You're ready to build!

---

**Need help?** Check `TROUBLESHOOTING.md` or review the documentation files listed above.
