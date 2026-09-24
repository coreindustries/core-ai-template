---
name: feature
description: >-
  Run a feature end to end in an isolated worktree: PRD, implementation, tests, and pull
  request. Use for substantial multi-file work that warrants its own branch and PRD. Do
  not use for a single-file fix (`/commit` directly), for generating one module's
  boilerplate (`/scaffold`), or before requirements are settled (`/brainstorm`).
---

# /feature

Full-cycle feature development: PRD creation, implementation, testing, and PR creation in an isolated worktree.

## Usage

```
/feature <feature_name> [options]
```

## Arguments

- `feature_name`: Name of the feature in kebab-case (e.g., `user-authentication`, `payment-processing`)

## Options

| Flag | Description |
|------|-------------|
| `--prd-only` | Only create the PRD, don't implement |
| `--skip-prd` | Skip PRD creation if one already exists |
| `--scaffold` | Generate CRUD scaffolding (routes, models, services) |
| `--with-db` | Include database model (requires `--scaffold`) |
| `--link-prd <number>` | Link to existing PRD branch instead of creating new |
| `--brainstorm` | Run `/brainstorm` before PRD creation to explore requirements |
| `--compound` | Run `/compound` after PR creation to capture learnings |

## Overview

This skill orchestrates the complete feature development lifecycle:

0. **(Optional)** Brainstorm requirements — if `--brainstorm` flag is set
1. Create isolated worktree
2. Build PRD from template (or link to existing)
3. Confirm PRD with user
4. Implement feature code
5. Write tests
6. Run tests and fix issues
7. Run linting and security scans
8. Create PR
9. Debug CI/CD issues
10. **(Optional)** Capture learnings — if `--compound` flag is set

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete each phase end-to-end before moving to the next
- Make reasonable assumptions based on existing codebase patterns
- Don't request clarification unless truly blocked
- Use parallel operations where possible (reading files, running checks)

**Context Awareness:**
- Read `prd/00_technology.md` for technology-specific commands and patterns
- Study existing PRDs in `prd/` to understand project scope
- Review existing implementations to follow established patterns
- Keep PRD concise and DRY - don't duplicate existing documentation

**Quality:**
- Generate tests alongside code (not as an afterthought)
- Ensure high coverage for new code (target defined in tech stack)
- Run full quality pipeline before PR

---

## Phase 0: Brainstorm Requirements (Optional)

*Only runs if `--brainstorm` flag is set.*

Invoke the `/brainstorm` skill with the feature name to explore requirements before creating the PRD. This separates WHAT from HOW and ensures the right problem is being solved.

```
/brainstorm {feature_name}
```

Once requirements are confirmed, continue to Phase 1 with the brainstorm output as input for PRD creation.

---

## Phase 1: Create Isolated Worktree

### Step 1.1: Validate Feature Name

```bash
# Ensure feature name is kebab-case
# Check it doesn't conflict with existing features
ls src/{project}/
git branch -a | grep -i {feature_name}
```

### Step 1.2: Create Worktree

```bash
# Create worktree for isolated development
WORKTREE_PATH="../$(basename $(pwd))-{feature_name}"

# If --link-prd specified, branch from PRD branch
if [ -n "$LINK_PRD" ]; then
  PRD_BRANCH=$(git branch -a | grep "prd/${LINK_PRD}-" | head -1 | xargs)
  git worktree add "$WORKTREE_PATH" -b feature/{feature_name} "$PRD_BRANCH"
else
  git worktree add "$WORKTREE_PATH" -b feature/{feature_name} main
fi

cd "$WORKTREE_PATH"

# Initialize the worktree (see prd/00_technology.md for commands)
{package_manager} install
{db_generate}  # If applicable
```

**Important:** All subsequent work happens in the worktree, not the main repository.

---

## Phase 2: Build PRD

*Skip this phase if `--skip-prd` or `--link-prd` is specified.*

### Step 2.1: Research Existing Context

Before writing the PRD, understand the project context. Read these files in parallel:
- `prd/00_index.md` - Project overview
- `prd/_prd_template.md` - Template structure
- `prd/00_technology.md` - Technology patterns
- Related PRDs (search for similar features)
- `CLAUDE.md` - Code standards

### Step 2.2: Assign PRD ID

The ID is today's date plus a slug: `PRD-YYYY-MM-DD-<slug>`. Do **not** find the highest existing number and add one. Two agents running that at the same time pick the same number, and neither finds out until merge. A date plus a slug needs no shared counter. Existing numbered PRDs keep their numbers; `scripts/assert-doc-ids.sh` (run in CI and `make pr-check`) rejects any *new* numbered one.

```bash
echo "PRD-$(date -u +%F)-<kebab-slug>"   # e.g. PRD-2026-09-24-oauth-login
```

### Step 2.3: Create PRD File

Create `prd/YYYY-MM-DD-<slug>.md` following the template. The filename has **no** `PRD-` prefix; the prefix appears only in the heading and in `depends_on` references. `prd/PRD-2026-…md` is rejected by the gate.

```markdown
---
prd_version: "0.1"
status: "Draft"
last_updated: "YYYY-MM-DD"
owner: "@owner"
---

# PRD-YYYY-MM-DD-<slug> – {Feature Name}

## 1. Purpose

[Concise description - 2-3 sentences max]

## 2. Functional Requirements

### FR{X}.1 - [Requirement Name]

[Keep it DRY - reference existing docs where possible]

## 3. Technical Implementation

### 3.1 Architecture

[Implementation approach - API client, CRUD service, etc.]

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
- src/{project}/api/{feature} (new)
- src/{project}/services/{feature} (new)
- src/{project}/models/{feature} (new)
- tests/unit/test_{feature} (new)

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

Read existing implementations in parallel to understand patterns:
- Existing routes/controllers in `src/{project}/api/`
- Existing services in `src/{project}/services/`
- Configuration in `src/{project}/config`
- Model definitions in `src/{project}/models/`

### Step 4.2: Implementation Based on Feature Type

#### For CRUD Features (`--scaffold`)

Create standard CRUD structure:

**API Routes** (`src/{project}/api/{feature}`):
- List endpoint (GET /)
- Get by ID endpoint (GET /:id)
- Create endpoint (POST /)
- Update endpoint (PATCH /:id)
- Delete endpoint (DELETE /:id)

**Models** (`src/{project}/models/{feature}`):
- Base schema
- Create schema
- Update schema
- Response schema

**Service** (`src/{project}/services/{feature}`):
- get_by_id method
- list_all method
- create method
- update method
- delete method
- Audit logging for mutations

#### For API Client Integrations

Create client structure:

**Client** (`src/{project}/services/clients/{feature}`):
- Custom exception class
- Client class with retry logic
- Singleton accessor function
- Type hints on all functions
- Google-style docstrings

**Configuration**:
- Add API key and settings to config
- Update `.env.example`

**Integration**:
- Integrate with existing services as needed

### Step 4.3: Database Schema (if `--with-db`)

Add to database schema:
- Model with id, timestamps
- Appropriate indexes
- Run: `{db_generate}` and `{db_migrate}`

### Step 4.4: Register Components

- Register routes in main router
- Export services if needed
- Update configuration documentation

---

## Phase 5: Write Tests

Unit tests go in `tests/unit/test_{feature}`; anything touching a real database,
an end-to-end workflow, or a live API goes in `tests/integration/test_{feature}`.
`.claude/rules/testing.md` is auto-loaded and states the coverage bar.

Cover the happy path *and* the failure modes the feature can actually reach —
for a CRUD surface that means each operation plus validation and authorization;
for an API client it means auth failure, error responses, retry behavior, and the
edge cases that bite in production (empty results, pagination, rate limits). The
useful question is which of these can fail in a way no existing test would catch.

---

## Phase 6: Green Tests and Coverage

Run the suite, fix what fails, repeat until green and coverage meets the gate.
Diagnose each failure to its cause before changing anything — a test edited to
match broken behavior is worse than the failure it silenced.

```bash
{test_command} tests/ -v
{test_command} tests/unit/test_{feature} -v --tb=long   # narrow to a failing file

{test_with_coverage} tests/unit/test_{feature} \
  --cov=src/{project}/{feature_path}
```

---

## Phase 7: Quality Gate

Everything below has to be green before the PR opens. These are independent
checks — run them in whatever order suits, or all at once with `make quality`.

```bash
{lint_fix} src/ tests/ && {format_command} src/ tests/
{type_check} src/
{security_scan}
{pre_commit} run --all-files
```

Then run the `judge` agent on the branch diff. Fix every P1 and P2 and run it again; the final verdict goes in the PR body. This is not optional and has no size exemption. See CLAUDE.md → Agent Routing.

---

## Phase 8: Create PR

### Step 8.1: Stage and Commit Changes

```bash
git add .
git status  # Review changes

git commit -m "$(cat <<'EOF'
feat({feature}): implement {feature}

- Add {feature} with [routes/client/service]
- Add comprehensive unit tests
- [Other notable changes]

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
# Determine base branch
if [ -n "$LINK_PRD" ]; then
  BASE_BRANCH="prd/${LINK_PRD}-*"
else
  BASE_BRANCH="main"
fi

gh pr create --base "$BASE_BRANCH" \
  --title "feat({feature}): implement {feature}" \
  --body "$(cat <<'EOF'
## Summary

- [Key change 1]
- [Key change 2]
- Includes comprehensive unit tests

## Changes

- `src/{project}/...` - [Description]
- `tests/unit/test_{feature}` - Unit tests

## Test Plan

- [x] All unit tests pass
- [x] Coverage target met
- [x] Linting passes
- [x] Type checking passes

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Phase 9: Debug CI/CD Issues

### Step 9.1: Monitor CI

```bash
gh pr checks
gh run watch
```

### Step 9.2: Fix CI Failures

For each CI failure:

1. **Download logs**: `gh run view --log-failed`
2. **Analyze failure**: Identify failing step, compare with local
3. **Common issues:**
   - Missing dependencies: Add to package config
   - Environment differences: Check runtime version, OS
   - Flaky tests: Add retries or fix race conditions
   - Missing secrets: Verify CI has test credentials
4. **Fix and push**:
   ```bash
   git add .
   git commit -m "fix: address CI failure in {component}"
   git push
   ```

**Iterate until CI passes.**

---

## Phase 10: Capture Learnings (Optional)

*Only runs if `--compound` flag is set.*

After the PR is created and CI passes, invoke `/compound` to capture any non-trivial knowledge gained during implementation. This is especially valuable when:

- The feature required debugging a non-obvious issue
- You discovered a workaround or undocumented behavior
- The implementation required reading external documentation
- A pattern was established that future features should follow

```
/compound
```

---

## Branching Workflow

```
main ─────────────────────────────────────────────►
       │                              ▲
       │ create prd branch            │ merge PRD PR
       ▼                              │
prd/{n}-{name} ──────────────────────►│
       │                ▲             │
       │ create feature │ merge feat  │
       ▼                │             │
feature/{name} ────────►│             │
```

### Merge Strategy

1. **Feature → PRD branch**: Feature PRs target their parent PRD branch (if `--link-prd`)
2. **PRD → main**: Once all features complete, PRD branch merges to main
3. **Standalone features**: Features without a PRD target `main` directly

---

## Completion Checklist

Before marking complete, verify:

- [ ] Worktree created and isolated
- [ ] PRD created/linked and approved
- [ ] Feature code implemented following patterns
- [ ] Unit tests written with target coverage
- [ ] All tests pass locally
- [ ] Linting passes
- [ ] Type checking passes
- [ ] Security scan passes
- [ ] Pre-commit hooks pass
- [ ] PR created with descriptive summary
- [ ] CI passes

---

## Examples

### Full Feature Implementation

```
/feature user-authentication
```

Creates complete feature with new PRD, implementation, tests, and PR.

### CRUD Scaffold with Database

```
/feature user-profile --scaffold --with-db --link-prd 04
```

Creates CRUD scaffolding linked to existing PRD #04.

### PRD Only

```
/feature payment-processing --prd-only
```

Creates only the PRD for later implementation.

### Quick Implementation (Existing PRD)

```
/feature api-client --skip-prd --link-prd 05
```

Implements feature using existing PRD #05 without creating a new one.

---

## Quick Reference

| Phase | Key Actions | Commands |
|-------|-------------|----------|
| 1. Worktree | Create isolated env | `git worktree add`, `{package_manager} install` |
| 2. PRD | Create requirements | Read template, create PRD |
| 3. Confirm | Get approval | Present summary |
| 4. Build | Implement feature | Follow existing patterns |
| 5. Tests | Write tests | `{test_command}` |
| 6. Fix | Debug failures | `{test_command} -v --tb=long` |
| 7. Quality | Lint & scan | `{lint_fix}`, `{type_check}` |
| 8. PR | Create PR | `gh pr create` |
| 9. CI | Debug CI | `gh pr checks`, `gh run watch` |
