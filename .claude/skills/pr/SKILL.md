---
name: pr
description: "Create pull requests with comprehensive descriptions and test plans."
---

# /pr

Create pull requests with comprehensive descriptions and test plans.

## Usage

```
/pr [--draft] [--base <branch>] [--reviewers <users>]
```

## Options

| Flag | Description |
|------|-------------|
| `--draft` | Create as draft PR |
| `--base <branch>` | Target branch (default: main) |
| `--reviewers <users>` | Comma-separated list of reviewers |

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Analyze all commits in the branch
- Generate comprehensive PR description
- Create PR without additional prompting

**Thoroughness:**
- Review ALL commits, not just the latest
- Identify breaking changes
- Document testing performed

### PR Creation Process

1. **Analyze branch state**:
   ```bash
   git status
   git log main..HEAD --oneline
   git diff main...HEAD --stat
   ```

2. **Review all commits** in the branch:
   ```bash
   git log main..HEAD --pretty=format:"%h %s"
   ```

3. **Check CI readiness**:
   - Verify tests pass locally
   - Verify linting passes
   - Check for uncommitted changes

4. **Push branch** if needed:
   ```bash
   git push -u origin $(git branch --show-current)
   ```

5. **Generate PR description** following template:

   ```markdown
   ## Summary

   [2-4 bullet points describing the changes]

   ## Changes

   [List of files/modules changed with brief descriptions]

   ## Test Plan

   - [ ] Unit tests added/updated
   - [ ] Integration tests (if applicable)
   - [ ] Manual testing performed
   - [ ] Edge cases considered

   ## Screenshots

   [If UI changes, include before/after screenshots]

   ## Breaking Changes

   [List any breaking changes, or "None"]

   ## Checklist

   - [ ] Code follows project style guidelines
   - [ ] Self-review completed
   - [ ] Documentation updated (if needed)
   - [ ] Tests pass locally

   ---
   Generated with [Claude Code](https://claude.com/claude-code)
   ```

6. **Create PR**:
   ```bash
   gh pr create \
     --title "type(scope): description" \
     --body "$(cat <<'EOF'
   [Generated PR body]
   EOF
   )" \
     --base main
   ```

7. **Post-creation**:
   - Display PR URL
   - Show CI status link
   - Suggest reviewers if not specified

### PR Title Guidelines

Follow the same conventional commit format:
- `feat(scope): add new feature`
- `fix(scope): resolve bug description`
- `refactor(scope): improve code structure`

### Determining PR Type

**From commits:**
- Multiple `feat` commits → `feat` PR
- Mix of `feat` and `fix` → `feat` PR (features take precedence)
- Only `fix` commits → `fix` PR
- Only `refactor`/`chore` → use that type

### Draft PRs

Use `--draft` when:
- Work is in progress
- Seeking early feedback
- CI needs to run before review

### Example Output

```
$ /pr --base main

Analyzing branch: feature/user-auth

Commits (3):
  abc1234 feat(auth): add login endpoint
  def5678 feat(auth): add session management
  ghi9012 test(auth): add authentication tests

Files changed: 8
Lines: +450 / -12

Creating PR...

## Summary

- Add user authentication with JWT tokens
- Implement login/logout endpoints
- Add session management with Redis
- Include comprehensive test coverage

## Changes

- `src/api/auth.py` - New authentication endpoints
- `src/services/session.py` - Session management service
- `src/middleware/auth.py` - Authentication middleware
- `tests/unit/test_auth.py` - Unit tests

## Test Plan

- [x] Unit tests added (15 new tests)
- [x] Integration tests for auth flow
- [x] Manual testing with Postman
- [x] Edge cases: expired tokens, invalid credentials

## Breaking Changes

None

---
Generated with [Claude Code](https://claude.com/claude-code)

PR created: https://github.com/org/repo/pull/123

Next steps:
1. Review PR at the link above
2. Monitor CI: gh pr checks
3. Request reviewers: gh pr edit --add-reviewer @username
```
