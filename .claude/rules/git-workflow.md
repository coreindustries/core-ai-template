# Git Workflow Rules

**Source:** PRD 01 - Technical Standards, Section 9

## Working with Dirty Worktrees

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

## Commit Message Standards

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
- `ci`: CI/CD changes
- `build`: Build system changes

**Example:**
```
feat: add user authentication with JWT

Implements JWT-based authentication with session storage.
Includes login, logout, and token refresh endpoints with full
test coverage and audit logging.

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Guidelines:**
- Use imperative mood ("add" not "added")
- Max 72 characters for subject line
- No period at end of subject
- Lowercase after type
- Reference tickets in footer when available

## Git Hygiene Checklist

- [ ] Conventional commit format used
- [ ] Co-authored by Claude attribution included
- [ ] Quality checks passed before commit
- [ ] No unrelated changes in commits
- [ ] Existing changes preserved (not reverted)
- [ ] Commit is atomic (single logical change)
