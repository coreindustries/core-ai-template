# /onboard

Onboard a new contributor to the project with a guided walkthrough.

## Usage

```
/onboard [--verify]
```

## Arguments

- `--verify`: Also run setup verification (tests, lint, typecheck)

## Instructions

When this skill is invoked:

### 1. Read Project Context

Read these files in parallel:
- `CLAUDE.md` (project overview, commands, architecture)
- `prd/00_technology.md` (technology choices)
- `prd/00_index.md` (current features and status)
- `CONTRIBUTING.md` (contribution workflow)

### 2. Explain Project Structure

Provide a concise overview:
- What this project does
- Technology stack and key dependencies
- Directory structure and where things live
- Key architectural patterns (service layer, database singleton, etc.)

### 3. Check Environment

Verify the development environment:
```bash
# Check required tools
{package_manager} --version
git --version
docker --version

# Check project setup
test -f .env
{package_manager} install --check  # or equivalent
```

Report any missing tools or configuration.

### 4. Show Current State

```bash
# What branch are we on?
git branch --show-current

# Any work in progress?
git status --short

# Recent activity
git log --oneline -5
```

### 5. Show Active Work

Check for in-progress features:
- Read `prd/00_index.md` for "In Progress" items
- List any task files in `prd/tasks/`
- Identify what needs attention

### 6. Suggest First Steps

Based on the project state, suggest:
- Available tasks to work on
- Setup steps if environment isn't configured
- How to use the AI skills effectively

### 7. Verify Setup (if --verify)

```bash
make quality
```

Report results and any issues to fix.

## Example Output

```
Welcome to {project_name}!

## Project Overview
This is a {description} built with {stack}.

## Your Environment
  ✅ Node.js 22.x installed
  ✅ Bun installed
  ✅ Docker running
  ✅ .env configured
  ✅ Dependencies installed

## Current State
  Branch: main
  No uncommitted changes
  Last commit: feat: add user authentication (2 days ago)

## Active Work
  🔄 User Dashboard (In Progress) - see prd/tasks/user-dashboard_tasks.md
  📋 API Rate Limiting (Planned) - not yet started

## Suggested First Steps
1. Read the dashboard task file for context
2. Pick up from "Next Session Priorities"
3. Use `/feature` to scaffold new features
4. Use `/test` after implementing to ensure coverage

## Key Commands
  make dev        - Start development server
  make test       - Run tests
  make quality    - Full quality check
  make help       - Show all commands

Happy coding! Use /help for AI skill reference.
```
