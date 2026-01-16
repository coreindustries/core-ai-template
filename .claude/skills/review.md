# /review

Perform code review against project standards.

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
- Check against all standards in `prd/01_Technical_standards.md`
- Check security practices from `prd/03_Security.md`
- Check technology-specific patterns from `prd/02_Tech_stack.md`

### Review Process

1. **Identify files to review**:
   - If `target`: Review specified files
   - If `--pr`: `git diff main...{branch}`
   - Otherwise: `git diff --staged`

2. **Read all relevant files in parallel**:
   - Files being reviewed
   - Related test files
   - PRDs for standards

3. **Check each criterion**:

   **Code Quality (PRD 01):**
   - [ ] Type annotations on all functions
   - [ ] Docstrings on public functions/classes
   - [ ] DRY principle followed
   - [ ] Naming conventions followed
   - [ ] No broad exception catches
   - [ ] No silent failures

   **AI Agent Patterns (PRD 01):**
   - [ ] Complete implementation (no TODOs)
   - [ ] End-to-end functionality
   - [ ] All relevant surfaces updated
   - [ ] Tests exist for new code

   **Security (PRD 03):**
   - [ ] No hardcoded secrets
   - [ ] Input validation present
   - [ ] Parameterized queries
   - [ ] Proper error handling
   - [ ] Audit logging for sensitive operations

   **Project Patterns (PRD 02):**
   - [ ] Uses project's database pattern
   - [ ] Uses project's logging pattern
   - [ ] Follows project's structure

4. **Classify findings**:
   - **Critical**: Must fix before merge
   - **Important**: Should fix before merge
   - **Suggestion**: Nice to have improvements

5. **Generate report**:

### Review Report Format

```markdown
## Code Review

**Overall Assessment:** [Ready / Needs Work / Major Issues]

**Summary:**
- Critical issues: X
- Important issues: Y
- Suggestions: Z

---

### Critical Issues

1. **Missing type hints** (`src/{project}/api/users:15`)
   ```
   # Current (❌)
   async def get_user(user_id):

   # Should be (✓)
   async def get_user(user_id: str) -> User:
   ```

### Important Issues

1. **Broad exception handling** (`src/{project}/services/user:42`)
   Catching generic Exception without re-raising or logging.

### Suggestions

1. **Consider extracting validation logic** (`src/{project}/api/users:28-45`)
   Repeated validation code could be extracted.

---

### Recommendations

**Priority 1 (Critical):**
1. Add type hints to all functions
2. Replace broad exception handlers

**Priority 2 (Important):**
1. Add error case tests
2. Add audit logging

---

### Next Steps

1. Fix critical issues
2. Address important issues
3. Re-run quality checks
4. Request re-review if needed
```

## Example

```
$ /review --pr feat/user-auth

📋 Reviewing: feat/user-auth (12 files changed)

Reading files...
Checking standards...

## Code Review

**Overall Assessment:** Needs Work

**Summary:**
- Critical issues: 2
- Important issues: 3
- Suggestions: 1

### Critical Issues

1. **Missing type hints** (`src/{project}/api/auth:23`)
2. **Hardcoded secret** (`src/{project}/services/auth:45`)
   ⚠️  JWT secret should be from environment

### Important Issues

1. **Missing tests** for error cases in auth service
2. **No audit logging** for login attempts
3. **Broad exception catch** in token validation

### Suggestions

1. Consider extracting token validation to shared utility

---

Run `/lint --fix` then address critical issues before merge.
```
