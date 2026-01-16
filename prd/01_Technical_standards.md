---
prd_version: "1.0"
status: "Active"
last_updated: "2026-01-15"
---

# 01 – Technical Standards

## 1. Purpose

This document establishes the technical standards, best practices, and requirements for all code contributions to this project—whether written by humans or AI agents. These standards ensure code quality, maintainability, security, and performance while enabling autonomous, efficient AI-assisted development workflows.

**Goals:**
- Maintain consistent code quality across all contributions
- Enable autonomous AI agent workflows with clear guardrails
- Ensure production-ready code through rigorous testing and quality checks
- Preserve context across long-running features that span multiple sessions

**Related Documents:**
- PRD 02 (Tech Stack) - Language-specific technologies and patterns
- PRD 03 (Security) - Security requirements and audit logging

## 2. Language Requirements

**See `prd/02_Tech_stack.md` for:**
- Supported language versions
- Package manager requirements
- Type system requirements
- Linting and formatting tools

### 2.1 Package Management

**REQUIRED:** Use the project's designated package manager exclusively.

**General principles:**
- Never install packages to the host OS directly
- Use lock files for reproducible builds
- Use the runner/package manager for all script execution

```bash
# Example patterns (see prd/02_Tech_stack.md for specifics)
{package_manager} install              # Install dependencies
{package_manager} add {package}        # Add new package
{runner} {script}                      # Run scripts
```

## 3. Code Quality Standards

### 3.1 DRY Principle (Don't Repeat Yourself)

**REQUIRED:** All code MUST follow the DRY principle.

- Extract common functionality into reusable functions or modules
- Avoid code duplication across files or services
- Create shared utilities for common patterns
- Search for existing implementations before creating new code
- Refactor duplicated code when identified during reviews

### 3.2 Static Typing Requirements

**REQUIRED:** Static typing MUST be used for all code.

- All function signatures MUST include type annotations
- All class attributes MUST be type-annotated
- All return types MUST be specified
- Use modern syntax for your language version
- Type checking MUST pass before code can be merged

### 3.3 Naming Conventions

**REQUIRED:** All code MUST follow consistent naming conventions.

| Element             | Convention         | Example                                       |
| ------------------- | ------------------ | --------------------------------------------- |
| Functions/methods   | Language standard  | `processData`, `process_data`                 |
| Classes/Types       | PascalCase         | `DataProcessor`, `UserService`                |
| Constants           | UPPER_SNAKE_CASE   | `MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT`          |
| Private members     | Language standard  | `_internal`, `#private`, `private`            |
| Modules/Files       | Language standard  | `dataUtils`, `data_utils`, `DataUtils`        |

### 3.4 Code Documentation

**REQUIRED:** All code MUST be documented.

- All modules MUST have a module-level docstring/comment
- All classes MUST have a class-level docstring/comment
- All public functions MUST have docstrings (use project's convention)
- Complex algorithms MUST include inline comments

```
# Example structure (language-agnostic):

/**
 * Module: User data processing
 *
 * This module provides utilities for validating and transforming user data.
 */

/**
 * User class representing a system user.
 *
 * @property id - Unique identifier
 * @property email - User's email address
 * @property name - Display name
 */

/**
 * Validates an email address format.
 *
 * @param email - The email address to validate
 * @returns True if valid, false otherwise
 * @throws ValueError if email is empty
 */
```

### 3.5 Project Organization

**REQUIRED:** The project root MUST be kept clean.

**Allowed in root:**
- Configuration files (package manager, linter, type checker)
- Documentation: `README.md`, `LICENSE`, `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`
- CI/CD: `.github/workflows/`
- Environment: `.env.example`

**Must be in subdirectories:**
- Source code → `src/`
- Tests → `tests/`
- Scripts → `scripts/`
- Documentation → `docs/`
- PRDs → `prd/`

## 4. AI Agent Development Principles

### 4.1 Autonomy and Persistence

**REQUIRED:** AI agents MUST operate autonomously and persist until tasks are fully complete.

**Autonomous Senior Engineer Mindset:**
- Once given direction, proactively gather context, plan, implement, test, and refine
- No waiting for additional prompts at each step
- Complete tasks end-to-end within a single turn whenever feasible
- Bias to action: default to implementing with reasonable assumptions

**Persistence Criteria:**
- Don't stop at analysis or partial fixes
- Carry changes through implementation, verification, and clear explanation
- Continue until working code is delivered, not just a plan
- Only pause if explicitly redirected or truly blocked

**Anti-patterns to Avoid:**
- Stopping after creating a plan without implementing
- Requesting clarification on details that can be reasonably inferred
- Implementing halfway and asking "should I continue?"
- Excessive looping on the same files without progress

### 4.2 Bias to Action

**REQUIRED:** Agents MUST default to implementation over clarification.

**When to Implement Immediately:**
- Requirements are reasonably clear (even if some details missing)
- Multiple valid approaches exist (choose the most standard one)
- Implementation patterns exist in the codebase
- Missing details can be inferred from context

**When to Ask Questions:**
- Critical architectural decisions with significant tradeoffs
- Conflicting requirements that need resolution
- Truly blocked on external information
- User preference matters significantly and isn't inferrable

**Example Decision Tree:**
```
User: "Add user authentication"
├─ API approach? → JWT (standard, matches existing patterns)
├─ Password hashing? → bcrypt/argon2 (industry standard)
├─ Session storage? → Redis (if already configured)
└─ IMPLEMENT with these defaults ✓

User: "Add payment processing"
├─ Provider? → Could be Stripe, PayPal, Square... → ASK ✓
```

### 4.3 Correctness Over Speed

**REQUIRED:** Prioritize correctness, clarity, and reliability over implementation speed.

**Quality Criteria:**
- Cover the root cause or core ask, not just symptoms
- Avoid risky shortcuts and speculative changes
- Investigate before implementing to ensure understanding
- No messy hacks just to get code working

**Discerning Engineer Approach:**
- Read enough context before changing files
- Understand existing patterns and follow them
- Consider edge cases and error paths
- Write production-ready code, not just "working" code

### 4.4 Comprehensiveness and Completeness

**REQUIRED:** Ensure changes are comprehensive across all relevant surfaces.

**Example:**
```
Task: Add "archived" status to users

Incomplete (❌):
- Only add field to database schema

Complete (✓):
- Add field to database schema
- Generate migration
- Update create/update models
- Add filtering in service layer
- Add query param to API endpoint
- Update tests for archived users
- Add audit logging for archive action
```

### 4.5 Behavior-Safe Defaults

**REQUIRED:** Preserve intended behavior and UX.

- Don't change existing behavior without explicit request
- Gate intentional behavior changes with feature flags or configuration
- Add tests when behavior shifts
- Document behavioral changes in commit messages

```
// UNSAFE: Changes default behavior
getUsers(includeDeleted = true)  // Was false

// SAFE: Preserves existing behavior
getUsers(includeDeleted = false, includeArchived = false)  // New parameter
```

## 5. Error Handling

### 5.1 Specific Exception Types

**REQUIRED:** Use specific exception/error types, not broad catches.

- Create custom exceptions for domain errors
- Always include context in error messages
- Never swallow exceptions silently

```
// Example error class structure
class UserNotFoundError extends Error {
  constructor(userId: string) {
    super(`User not found: ${userId}`)
    this.userId = userId
  }
}

class ValidationError extends Error {
  constructor(field: string, message: string) {
    super(`Validation error on ${field}: ${message}`)
    this.field = field
  }
}
```

### 5.2 Tight Error Handling

**REQUIRED:** Do NOT add broad exception catches or silent defaults.

**What to Avoid:**
- Broad `try/catch` blocks that swallow errors
- Catching all exceptions without re-raising or logging
- Success-shaped fallbacks that hide failures
- Early returns on invalid input without logging

```
// BAD: Silent failure
function getUser(userId) {
  try {
    return db.user.find(userId)
  } catch (e) {
    return null  // What happened? Why did it fail?
  }
}

// GOOD: Explicit error handling
function getUser(userId) {
  try {
    const user = db.user.find(userId)
    if (!user) throw new UserNotFoundError(userId)
    return user
  } catch (e) {
    if (e instanceof DatabaseError) {
      logger.error(`Database error fetching user ${userId}`, e)
      throw new ServiceError(`Failed to fetch user: ${userId}`, e)
    }
    throw e
  }
}
```

## 6. Exploration Patterns

### 6.1 Think First, Batch Everything

**REQUIRED:** Plan all file reads before executing, then batch them in parallel.

**Pattern:**
1. **Think**: Decide ALL files/resources needed
2. **Batch**: Read all files together in one parallel call
3. **Analyze**: Process results
4. **Repeat**: Only if new, unpredictable reads are needed

```
// BAD: Sequential reads
read("api/routes.{ext}")
// ... analyze ...
read("services/user.{ext}")
// ... analyze ...

// GOOD: Parallel batch
read_parallel([
    "api/routes.{ext}",
    "services/user.{ext}",
    "models/user.{ext}"
])
// ... analyze all together ...
```

### 6.2 Maximize Parallelism

**REQUIRED:** Always read files in parallel unless logically unavoidable.

**Applies To:**
- File reads
- File searches
- Directory listings
- Git operations

**Only Sequential If:**
- You truly cannot know the next file without seeing a result first
- Example: Reading a config file to determine which modules to load next

### 6.3 Efficient, Coherent Edits

**REQUIRED:** Batch logical edits together, not repeated micro-edits.

- Read enough context before changing a file
- Make all related changes in one pass
- Avoid thrashing with many tiny patches to the same file

## 7. Testing Standards

### 7.1 Unit Test Coverage

**REQUIRED:** Minimum test coverage as defined in `prd/02_Tech_stack.md` (typically 66-100%).

- All new code MUST have corresponding unit tests
- Use project's designated test framework
- Use coverage reporting tools

**Test file naming:**
- Separate test files: `tests/unit/test_{module}.{ext}`

### 7.2 Integration Testing

**REQUIRED:** Integration tests for all database and external service interactions.

- Test database operations against real (test) database
- Test API endpoints with test client
- Clean up test data after each run
- Use containers for external dependencies
- Mark with appropriate test markers

### 7.3 Test-Driven Development Pattern

**REQUIRED when refactoring:** Ensure tests exist before modifying code.

**Pattern:**
1. Verify tests exist and pass
2. Make changes
3. Verify tests still pass
4. Add new tests for new behavior
5. Verify coverage hasn't decreased

## 8. Quality Checks

### 8.1 Frequent Check Pattern

**REQUIRED:** Run quality checks every 15-30 minutes during active development.

**Benefits:**
- Prevents error accumulation (50% less debugging time)
- Immediate feedback on smaller change sets
- Easier to identify which change caused issues
- Reduces pre-commit hook failures (40% less frustration)

```bash
# After writing/modifying a file
{lint_check} src/{module}
{format_check} src/{module}

# After writing type annotations
{type_check} src/{module}

# After writing tests
{test_specific} tests/unit/test_{module}
```

### 8.2 Pre-Commit Requirements

**REQUIRED:** All code MUST pass linting before commits.

**Typical tools (see `prd/02_Tech_stack.md` for specifics):**
- Linting tool
- Formatting tool
- Static type checker
- Security analyzer
- Dependency vulnerability scanner

### 8.3 Before Every Commit

**REQUIRED:** Run the full quality check suite:

```bash
# 1. Lint and format
{lint_fix} src/ tests/

# 2. Type check
{type_check} src/

# 3. Security scan
{security_scan} src/

# 4. Tests with coverage
{test_with_coverage}

# 5. Verify changes
git status
git diff
```

**All checks MUST pass before committing.**

## 9. Git and Version Control

### 9.1 Working with Dirty Worktrees

**REQUIRED:** Preserve existing changes not made by you.

**Rules:**
- **NEVER revert changes you didn't make** unless explicitly requested
- Unrelated changes in files → ignore them, don't revert
- Changes in files you've touched recently → read carefully, work with them
- Unexpected changes you didn't make → STOP and ask user

**Safe Commands:**
```bash
git status               # Check current state
git diff                 # See what changed
git diff --cached        # See staged changes
git log -5               # Recent commits
```

**NEVER Use Without Approval:**
```bash
git reset --hard         # Destroys all changes
git checkout --          # Discards specific file changes
git clean -fd            # Removes untracked files
```

### 9.2 Commit Message Standards

**REQUIRED Format:**
```
<type>: <description>

<body (optional)>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

**Example:**
```
feat: add user authentication with JWT

Implements JWT-based authentication with session storage.
Includes login, logout, and token refresh endpoints with full
test coverage and audit logging.

Co-Authored-By: Claude <noreply@anthropic.com>
```

## 10. Plan and Task Management

### 10.1 When to Create Plans

**Skip Plans For:**
- Straightforward tasks (easiest ~25% of work)
- Single-step changes
- Obvious fixes

**Create Plans For:**
- Multi-step features
- Complex refactorings
- Cross-cutting changes
- Tasks requiring coordination across multiple files

### 10.2 Plan Discipline

**REQUIRED:** Plans MUST be reconciled before finishing a task.

**Plan Lifecycle:**
1. Create plan with clear steps
2. Update plan after completing each step (mark as Done)
3. Before finishing, ensure every item is:
   - **Done**: Completed successfully
   - **Blocked**: With one-sentence reason and targeted question
   - **Cancelled**: With reason for cancellation
4. No in_progress or pending items when finishing

**Deliverable is Working Code:**
- Never end with only a plan
- Implement, test, and verify before completion

### 10.3 Task Tracking for Long-Running Features

Long-running features that span multiple sessions require persistent task tracking to survive context compression.

**When to Create Task Files:**
- Feature will span multiple agent sessions
- Feature has >5 distinct tasks
- Feature is marked "In Progress" in PRD index

**Location:** `prd/tasks/{feature_name}_tasks.md`

**Template:** Use `prd/tasks/TASK_TEMPLATE.md` as starting point

**Key Sections:**
1. **Context** - High-level overview and key decisions (critical for recovery)
2. **Tasks** - Hierarchical checklist with phase grouping
3. **Progress Summary** - Percentage complete per phase
4. **Next Session Priorities** - What to do immediately when resuming
5. **Decisions Made** - Architectural decisions with rationale

**Maintenance:**
- Update every 30-60 minutes during active development
- Use `/checkpoint` skill to update automatically

**Context Compression Recovery:**
1. Read `prd/00_PRD_index.md` to find "In Progress" features
2. Read corresponding task file
3. Start from "Next Session Priorities"

## 11. PRD Implementation Workflow

### 11.1 Before Starting Implementation

**Read PRDs thoroughly:**
1. Review the PRD document for the feature you're implementing
2. Understand dependencies on other PRDs
3. Check PRD 01 (Technical Standards) for coding requirements
4. Check PRD 03 (Security) for security requirements

**Setup development environment:**
```bash
{package_manager} install
{start_dependencies}
{db_generate}
{db_migrate}
```

### 11.2 Before Creating Pull Request

**Final verification:**
```bash
# 1. Ensure you're up to date with main
git fetch origin
git rebase origin/main

# 2. Run full test suite
{test_all}

# 3. Verify coverage
{test_with_coverage}

# 4. Review your changes
git log origin/main..HEAD
git diff origin/main
```

**Pull Request Checklist:**
- [ ] All tests pass
- [ ] Coverage is maintained or improved
- [ ] Linting passes
- [ ] Type checking passes
- [ ] Security scan passes
- [ ] All functions have type annotations
- [ ] All public functions have docstrings

## 12. Presenting Work

### 12.1 Communication Style

**Default:** Concise, friendly coding teammate tone.

**Structure:**
- Use natural language with high-level headings (when helpful)
- For substantial work: lead with quick explanation, then details
- For simple confirmations: skip heavy formatting
- Reference file paths with line numbers: `src/{project}/api/auth.{ext}:42`

### 12.2 Presenting Changes

**Structure:**
1. Quick explanation of what changed
2. Details on where and why
3. Logical next steps (if applicable)

**Example:**
```
Added JWT authentication with session storage.

**Changes:**
- `src/{project}/api/auth.{ext}` - Login, logout, refresh endpoints
- `src/{project}/services/auth.{ext}` - Token generation and validation
- `tests/unit/test_auth.{ext}` - Full test coverage (100%)

**Next steps:**
1. Run dev server to test the endpoints
2. Create a migration
3. Commit changes
```

## 13. Code Review Process

### 13.1 Review Checklist

All code reviews MUST verify:
- [ ] Type annotations on all functions and attributes
- [ ] Docstrings on all public functions and classes
- [ ] DRY principle followed
- [ ] Naming conventions followed
- [ ] Unit tests with adequate coverage
- [ ] Integration tests for DB/API operations
- [ ] No hardcoded secrets
- [ ] Security analysis passes
- [ ] Linting passes
- [ ] Error handling is comprehensive

### 13.2 Approval Requirements

- At least one reviewer approval required
- All CI/CD checks MUST pass
- All tests MUST pass
- Coverage MUST not decrease
- Security scans MUST pass

## 14. CI/CD Pipeline

### 14.1 Required Stages

1. **Lint** - Run linting and formatting checks
2. **Test** - Run tests with coverage
3. **Security** - Run security scanners
4. **Build** - Build application/container
5. **Deploy** - Deploy to target environment

### 14.2 Pre-merge Requirements

- All CI stages pass
- Code review approved
- Test coverage maintained
- No security vulnerabilities
- Documentation updated if needed

## 15. References

**PRDs:**
- PRD 02 (Tech Stack) - Technology stack details
- PRD 03 (Security) - Security requirements

**External:**
- OpenAI Codex Prompting Guide: https://cookbook.openai.com/examples/gpt-5/codex_prompting_guide
- Claude Code Documentation: https://claude.com/claude-code

**Project Files:**
- `CLAUDE.md` - Project overview for Claude Code
- `AGENTS.md` - Auto-injected agent instructions
- `.claude/skills/` - Custom slash commands
- `prd/tasks/` - Task tracking files
