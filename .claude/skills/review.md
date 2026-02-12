# /review

Multi-perspective code review against project standards with P1/P2/P3 severity classification.

## Usage

```
/review [target] [--pr <branch>] [--strict]
```

## Arguments

- `target`: File or directory to review (default: staged changes)
- `--pr <branch>`: Review changes from a PR branch
- `--strict`: Apply stricter standards

## Instructions

When this skill is invoked:

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Complete the review end-to-end
- Provide specific, actionable feedback
- Include file:line references for all issues

**Thoroughness:**
- Check against all standards in `.claude/rules/` (auto-loaded)
- Check security practices from `.claude/rules/security*.md`
- Check technology-specific patterns from `prd/00_technology.md`

### Review Process

1. **Identify files to review**:
   - If `target`: Review specified files
   - If `--pr`: `git diff main...{branch}`
   - Otherwise: `git diff --staged`

2. **Read all relevant files in parallel**:
   - Files being reviewed
   - Related test files
   - PRDs for standards
   - `.claude/agents/simplicity-reviewer.md` (simplicity perspective)
   - `.claude/agents/data-integrity-reviewer.md` (data integrity perspective)
   - `.claude/agents/security-reviewer.md` (security perspective)
   - `.claude/agents/perf-auditor.md` (performance perspective)

3. **Evaluate from 6 perspectives**:

   **Perspective 1 — Code Quality** (inline, using rules):
   - [ ] Type annotations on all functions
   - [ ] Docstrings on public functions/classes
   - [ ] DRY principle followed
   - [ ] Naming conventions followed
   - [ ] No broad exception catches
   - [ ] No silent failures
   - [ ] Complete implementation (no TODOs)
   - [ ] All relevant surfaces updated
   - [ ] Tests exist for new code

   **Perspective 2 — Security** (from security-reviewer agent):
   - [ ] No hardcoded secrets
   - [ ] Input validation present
   - [ ] Parameterized queries
   - [ ] Proper error handling (no internal details leaked)
   - [ ] Audit logging for sensitive operations

   **Perspective 3 — Performance** (from perf-auditor agent):
   - [ ] No N+1 queries
   - [ ] Appropriate indexing for new queries
   - [ ] No unnecessary data loading
   - [ ] Pagination for list endpoints
   - [ ] Caching considered for expensive operations

   **Perspective 4 — Architecture** (project patterns):
   - [ ] Uses project's database pattern
   - [ ] Uses project's logging pattern
   - [ ] Follows project's structure
   - [ ] Appropriate separation of concerns
   - [ ] No circular dependencies

   **Perspective 5 — Simplicity** (from simplicity-reviewer agent):
   - [ ] No unnecessary abstractions
   - [ ] No over-engineering
   - [ ] Functions are focused and right-sized
   - [ ] Code is clear without excessive comments
   - [ ] Right level of complexity for the problem

   **Perspective 6 — Data Integrity** (from data-integrity-reviewer agent):
   - [ ] Input validation complete (lengths, ranges, enums)
   - [ ] Database constraints appropriate (NOT NULL, FKs, indexes)
   - [ ] Migrations are safe and reversible
   - [ ] State transitions are validated
   - [ ] Null handling is explicit

4. **Classify findings with P1/P2/P3 severity**:
   - **P1 (Critical)**: Must fix before merge — security flaws, data loss risk, broken functionality
   - **P2 (Important)**: Should fix before merge — bugs, missing validation, test gaps
   - **P3 (Suggestion)**: Nice to have — style improvements, minor simplifications

5. **Generate report**:

### Review Report Format

```markdown
## Code Review

**Overall Assessment:** [Ready / Needs Work / Major Issues]

### Summary Table

| Perspective | P1 | P2 | P3 | Status |
|-------------|----|----|----|----|
| Code Quality | 0 | 1 | 0 | Pass |
| Security | 1 | 0 | 0 | Fail |
| Performance | 0 | 0 | 1 | Pass |
| Architecture | 0 | 0 | 0 | Pass |
| Simplicity | 0 | 1 | 0 | Pass |
| Data Integrity | 0 | 1 | 0 | Pass |
| **Total** | **1** | **3** | **1** | |

---

### P1 — Critical (must fix)

1. **[Security] Hardcoded API key** (`src/{project}/services/auth:45`)
   JWT secret should be loaded from environment variable.
   ```
   # Current (bad)
   SECRET = "hardcoded-secret-key"

   # Should be
   SECRET = os.environ["JWT_SECRET"]
   ```

### P2 — Important (should fix)

1. **[Code Quality] Missing type hints** (`src/{project}/api/users:15`)
   ```
   # Current
   async def get_user(user_id):

   # Should be
   async def get_user(user_id: str) -> User:
   ```

2. **[Simplicity] Interface with single implementation** (`src/{project}/repos/base:1-20`)
   `BaseRepository` interface has only `UserRepository` implementing it. Use the class directly.

3. **[Data Integrity] Missing length validation** (`src/{project}/models/user:12`)
   `name` field accepts unbounded strings. Add max length constraint.

### P3 — Suggestions

1. **[Performance] Consider index** (`src/{project}/db/queries:34`)
   Query filters on `created_at` without index. Add if query frequency is high.

---

### Recommendations

**Priority 1 (P1 fixes):**
1. Move JWT secret to environment variable

**Priority 2 (P2 fixes):**
1. Add type hints to all functions
2. Remove unnecessary BaseRepository interface
3. Add length validation to user name field

---

### Next Steps

1. Fix P1 issues (blocks merge)
2. Address P2 issues
3. Re-run quality checks
4. Request re-review if needed
```

## Example

```
$ /review --pr feat/user-auth

Reviewing: feat/user-auth (12 files changed)

Reading files and specialist agent perspectives...

## Code Review

**Overall Assessment:** Needs Work

### Summary Table

| Perspective | P1 | P2 | P3 | Status |
|-------------|----|----|----|----|
| Code Quality | 0 | 1 | 0 | Pass |
| Security | 1 | 1 | 0 | Fail |
| Performance | 0 | 0 | 1 | Pass |
| Architecture | 0 | 0 | 0 | Pass |
| Simplicity | 0 | 0 | 1 | Pass |
| Data Integrity | 0 | 1 | 0 | Pass |
| **Total** | **1** | **3** | **2** | |

### P1 — Critical

1. **[Security] Hardcoded secret** (`src/{project}/services/auth:45`)
   JWT secret should be from environment

### P2 — Important

1. **[Code Quality] Missing type hints** in auth service
2. **[Security] No audit logging** for login attempts
3. **[Data Integrity] No rate limiting** on token refresh endpoint

### P3 — Suggestions

1. **[Performance] Consider caching** JWT validation results
2. **[Simplicity] Token validation** could be extracted to middleware

---

Run `/lint --fix` then address P1 issues before merge.
```
