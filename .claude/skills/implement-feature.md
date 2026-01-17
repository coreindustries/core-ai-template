# /implement-feature

Full-cycle feature development: PRD creation, implementation, testing, and PR creation in an isolated worktree.

## Usage

```
/implement-feature <feature_name> [--prd-only] [--skip-prd]
```

## Arguments

- `feature_name`: Name of the feature in kebab-case (e.g., `user-authentication`, `cursor-integration`)
- `--prd-only`: Only create the PRD, don't implement
- `--skip-prd`: Skip PRD creation if one already exists

## Overview

This skill orchestrates the complete feature development lifecycle:

1. Create isolated worktree
2. Build PRD from template
3. Confirm PRD with user
4. Implement feature code
5. Write tests
6. Run tests and fix issues
7. Run linting and security scans
8. Create PR
9. Debug CI/CD issues

## Instructions

When this skill is invoked:

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Complete each phase end-to-end before moving to the next
- Make reasonable assumptions based on existing codebase patterns
- Don't request clarification unless truly blocked
- Use parallel operations where possible (reading files, running checks)

**Context Awareness:**
- Study existing PRDs in `prd/` to understand project scope
- Review existing client implementations in `services/clients/`
- Follow established patterns in the codebase
- Keep PRD concise and DRY - don't duplicate existing documentation

**Quality:**
- Generate tests alongside code (not as an afterthought)
- Ensure 100% coverage for new code
- Run full quality pipeline before PR

---

## Phase 1: Create Isolated Worktree

### Step 1.1: Validate Feature Name

```bash
# Ensure feature name is kebab-case
# Check it doesn't conflict with existing features
ls src/att/services/clients/
git branch -a | grep -i {feature_name}
```

### Step 1.2: Create Worktree

```bash
# Create worktree for isolated development
WORKTREE_PATH="../$(basename $(pwd))-{feature_name}"
git worktree add "$WORKTREE_PATH" -b feature/{feature_name} main
cd "$WORKTREE_PATH"

# Initialize the worktree
uv sync
uv run prisma generate
```

**Important:** All subsequent work happens in the worktree, not the main repository.

---

## Phase 2: Build PRD

### Step 2.1: Research Existing Context

Before writing the PRD, understand the project context:

```bash
# Read in parallel:
# - PRD index for overview
# - Related PRDs for context
# - Existing implementations for patterns
# - PRD template for structure
```

Read these files in parallel:
- `prd/00_PRD_index.md` - Project overview
- `prd/PRD_TEMPLATE.md` - Template structure
- Related PRDs (search for similar features)
- `CLAUDE.md` - Code standards

### Step 2.2: Assign PRD Number

```bash
# Find next available PRD number
ls prd/*.md | grep -E "^prd/[0-9]{2}_" | sort -r | head -1
# Increment by 1 for new PRD
```

### Step 2.3: Create PRD File

Create `prd/{number}_{Feature_name}.md` following the template:

```markdown
---
prd_version: "0.1"
status: "Draft"
last_updated: "YYYY-MM-DD"
owner: "@owner"
---

# {PRD_NUMBER} - {Feature Name}

## 1. Purpose

[Concise description - 2-3 sentences max]

## 2. Functional Requirements

### FR{X}.1 - [Requirement Name]

[Keep it DRY - reference existing docs where possible]

## 3. Technical Implementation

### 3.1 API Client

[Implementation details for the service client]

### 3.2 Database Schema

[Only if schema changes required]

### 3.3 Configuration

[Environment variables needed]

## 4. Error Handling

[Error scenarios and handling]

## 5. Testing Strategy

[Key test scenarios]

## 6. References

- [Link to API documentation]
- [Related PRDs]
```

**PRD Best Practices:**
- Keep it concise - don't over-document
- Reference existing implementations
- Focus on what's different from existing patterns
- Include only necessary sections

---

## Phase 3: Confirm PRD with User

### Step 3.1: Present PRD Summary

Present a concise summary to the user:

```
PRD Summary: {Feature Name}

Purpose: [1-2 sentences]

Key Requirements:
1. [Requirement 1]
2. [Requirement 2]
3. [Requirement 3]

Technical Approach:
- [Key technical decision 1]
- [Key technical decision 2]

Files to Create/Modify:
- src/att/services/clients/{feature}.py (new)
- src/att/config.py (modify)
- src/att/services/ingest.py (modify)
- tests/unit/clients/test_{feature}.py (new)

Questions/Clarifications Needed:
- [Any open questions]
```

### Step 3.2: Wait for User Approval

Ask the user to confirm:
- PRD scope is correct
- Technical approach is approved
- Any modifications needed

**If modifications needed:** Update PRD and re-confirm.

**If approved:** Proceed to Phase 4.

---

## Phase 4: Build Feature Code

### Step 4.1: Study Existing Patterns

Read existing implementations in parallel:

```python
# For API client features, read:
# - src/att/services/clients/claude.py (reference pattern)
# - src/att/services/clients/gemini.py (reference pattern)
# - src/att/config.py (configuration pattern)
# - src/att/services/ingest.py (integration pattern)
# - src/att/models/__init__.py (model definitions)
```

### Step 4.2: Implement API Client

Create `src/att/services/clients/{feature}.py`:

Follow the established pattern from existing clients:
- Custom exception class
- Client class with retry logic
- Singleton accessor function
- Type hints on all functions
- Google-style docstrings

### Step 4.3: Update Configuration

Add required settings to `src/att/config.py`:

```python
# {Feature} Configuration
{feature}_api_key: str | None = None
{feature}_enabled: bool = False
```

### Step 4.4: Update Ingestor

Integrate the new client into `src/att/services/ingest.py`:

- Import the new client and error class
- Initialize client in `__init__`
- Add sync method
- Register in platform list

### Step 4.5: Update Related Files

- `.env.example` - Add configuration documentation
- `src/att/services/__init__.py` - Export client if needed
- `CLAUDE.md` - Update if major patterns added

**Parallelization:** Steps 4.2-4.4 can often be done in parallel if there are no dependencies.

---

## Phase 5: Write Tests

### Step 5.1: Create Unit Tests

Create `tests/unit/clients/test_{feature}.py`:

Test categories (aim for 100% coverage):
1. **Authentication tests**
   - Valid credentials
   - Missing credentials
   - Invalid credentials

2. **API response parsing**
   - Success cases with various data shapes
   - Null/missing field handling
   - Date format parsing

3. **Error handling**
   - HTTP errors (401, 403, 429, 500)
   - Network errors
   - Timeout handling

4. **Retry logic**
   - Transient failures
   - Permanent failures

5. **Edge cases**
   - Empty responses
   - Pagination
   - Rate limiting

### Step 5.2: Create Integration Tests (if needed)

Create `tests/integration/test_{feature}.py` for:
- Database operations
- End-to-end sync workflows
- Real API calls (with test credentials)

---

## Phase 6: Run Tests and Fix Issues

### Step 6.1: Run Test Suite

```bash
# Run all tests
uv run pytest tests/ -v --tb=short

# If failures, run specific failing tests with verbose output
uv run pytest tests/unit/clients/test_{feature}.py -v --tb=long
```

### Step 6.2: Fix Failing Tests

For each failure:
1. Analyze the failure output
2. Identify root cause
3. Fix the issue (code or test)
4. Re-run to verify fix

**Iterate until all tests pass.**

### Step 6.3: Verify Coverage

```bash
uv run pytest tests/unit/clients/test_{feature}.py \
  --cov=src/att/services/clients/{feature} \
  --cov-report=term-missing
```

**Coverage requirement:** 100% for new code.

---

## Phase 7: Run Linting and Security Scans

### Step 7.1: Run Ruff Linting

```bash
uv run ruff check --fix src/ tests/
uv run ruff format src/ tests/
```

Fix any remaining issues that can't be auto-fixed.

### Step 7.2: Run Type Checking

```bash
uv run mypy src/
```

Fix any type errors.

### Step 7.3: Run Security Scan

```bash
uv run bandit -r src/ -ll
uv run ruff check --select=S src/
```

Address any security issues.

### Step 7.4: Run Pre-commit Hooks

```bash
uv run pre-commit run --all-files
```

Fix any issues until all hooks pass.

---

## Phase 8: Create PR

### Step 8.1: Stage and Commit Changes

```bash
git add .
git status  # Review changes

git commit -m "$(cat <<'EOF'
feat({feature}): implement {feature} integration

- Add {Feature}Client with retry logic and error handling
- Add configuration settings for {feature}
- Integrate into DataIngestor sync workflow
- Add comprehensive unit tests (X tests, 100% coverage)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

### Step 8.2: Push Branch

```bash
git push -u origin feature/{feature_name}
```

### Step 8.3: Create Pull Request

```bash
gh pr create --title "feat({feature}): implement {feature} integration" --body "$(cat <<'EOF'
## Summary

- Adds {Feature} API client for fetching usage data
- Integrates with existing DataIngestor sync workflow
- Includes comprehensive unit tests

## Changes

- `src/att/services/clients/{feature}.py` - New API client
- `src/att/config.py` - Add configuration settings
- `src/att/services/ingest.py` - Integrate client
- `tests/unit/clients/test_{feature}.py` - Unit tests

## Test Plan

- [x] All unit tests pass
- [x] 100% code coverage for new files
- [x] Linting passes
- [x] Type checking passes
- [x] Security scan passes

## Documentation

- Updated `.env.example` with configuration documentation

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Phase 9: Debug CI/CD Issues

### Step 9.1: Monitor CI

```bash
# Check PR status
gh pr checks

# Watch CI logs
gh run watch
```

### Step 9.2: Fix CI Failures

For each CI failure:

1. **Download logs**
   ```bash
   gh run view --log-failed
   ```

2. **Analyze failure**
   - Identify failing step
   - Understand error message
   - Compare with local environment

3. **Common CI issues:**
   - Missing dependencies: Add to `pyproject.toml`
   - Environment differences: Check Python version, OS
   - Flaky tests: Add retries or fix race conditions
   - Missing secrets: Verify CI has access to test credentials

4. **Fix and push**
   ```bash
   # Make fix
   git add .
   git commit -m "fix: address CI failure in {component}"
   git push
   ```

5. **Re-check CI**
   ```bash
   gh pr checks
   ```

**Iterate until CI passes.**

---

## Completion Checklist

Before marking complete, verify:

- [ ] Worktree created and isolated
- [ ] PRD created and approved
- [ ] Feature code implemented following patterns
- [ ] Unit tests written with 100% coverage
- [ ] All tests pass locally
- [ ] Linting passes (`ruff check`, `ruff format`)
- [ ] Type checking passes (`mypy`)
- [ ] Security scan passes (`bandit`)
- [ ] Pre-commit hooks pass
- [ ] PR created with descriptive summary
- [ ] CI passes

---

## Example

```
/implement-feature cursor-integration
```

Creates:
1. Worktree at `../core-ai-token-dashboard-cursor`
2. PRD at `prd/09_Cursor_Integration.md`
3. Client at `src/att/services/clients/cursor.py`
4. Tests at `tests/unit/clients/test_cursor.py`
5. PR on GitHub

---

## Quick Reference

| Phase | Key Files | Commands |
|-------|-----------|----------|
| 1. Worktree | - | `git worktree add`, `uv sync` |
| 2. PRD | `prd/{num}_{name}.md` | Read template, create PRD |
| 3. Confirm | - | Present summary, get approval |
| 4. Build | `services/clients/{name}.py` | Follow existing patterns |
| 5. Tests | `tests/unit/clients/test_{name}.py` | pytest, coverage |
| 6. Fix | - | `pytest -v --tb=long` |
| 7. Quality | - | `ruff`, `mypy`, `bandit` |
| 8. PR | - | `gh pr create` |
| 9. CI | - | `gh pr checks`, `gh run watch` |
