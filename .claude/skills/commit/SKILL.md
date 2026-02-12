---
name: commit
description: "Create well-formatted git commits following conventional commit standards."
---

# /commit

Create well-formatted git commits following conventional commit standards.

## Usage

```
/commit [--amend] [--fixup <commit>]
```

## Options

| Flag | Description |
|------|-------------|
| `--amend` | Amend the previous commit |
| `--fixup <commit>` | Create a fixup commit for interactive rebase |

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Analyze all staged changes end-to-end
- Generate appropriate commit message without prompting
- Follow conventional commit format strictly

**Quality:**
- Never commit secrets, credentials, or sensitive data
- Ensure commit is atomic (single logical change)
- Verify tests pass before committing (if applicable)

### Commit Process

1. **Check repository state**:
   ```bash
   git status
   git diff --staged
   ```

2. **Analyze staged changes**:
   - Identify the type of change (feat, fix, refactor, docs, test, chore, etc.)
   - Determine the scope (component, module, or area affected)
   - Understand the purpose of the change

3. **Review recent commits** for style consistency:
   ```bash
   git log --oneline -10
   ```

4. **Generate commit message** following conventional commits:

   ```
   <type>(<scope>): <description>

   [optional body]

   [optional footer]
   ```

   **Optional:** If Gitmoji is enabled, read `.claude/references/gitmoji.md` for the full reference, then prefix with emoji:
   ```
   <emoji> <type>(<scope>): <description>
   ```

   **Types:**
   - `feat`: New feature (✨ with Gitmoji)
   - `fix`: Bug fix (🐛 with Gitmoji)
   - `docs`: Documentation only (📝 with Gitmoji)
   - `style`: Formatting, no code change (🎨 with Gitmoji)
   - `refactor`: Code change that neither fixes nor adds (♻️ with Gitmoji)
   - `perf`: Performance improvement (⚡️ with Gitmoji)
   - `test`: Adding or updating tests (✅ with Gitmoji)
   - `chore`: Maintenance tasks (🔧 with Gitmoji)
   - `ci`: CI/CD changes (👷 with Gitmoji)
   - `build`: Build system changes (📦️ with Gitmoji)
   
   **Breaking changes:** Use 💥 emoji regardless of type when using Gitmoji

5. **Security check**:
   - Scan for potential secrets in staged files
   - Warn if `.env`, credentials, or API keys detected
   - Block commit if secrets found

6. **Create commit**:
   ```bash
   git commit -m "$(cat <<'EOF'
   type(scope): description

   Body explaining what and why (not how).

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

### Commit Message Guidelines

**Description (first line):**
- Use imperative mood ("add" not "added")
- Max 72 characters
- No period at end
- Lowercase after type

**Body (optional):**
- Explain what and why, not how
- Wrap at 72 characters
- Separate from subject with blank line

**Footer (optional):**
- Reference issues: `Closes #123`
- Breaking changes: `BREAKING CHANGE: description`
- Co-authors: `Co-Authored-By: Name <email>`

### Examples

**Simple feature:**
```
feat(auth): add password reset endpoint
```

**Bug fix with body:**
```
fix(api): handle null response from external service

The payment gateway occasionally returns null instead of an error
object. This adds defensive handling to prevent crashes.

Closes #456
```

**Breaking change:**
```
feat(config): migrate to environment-based configuration

BREAKING CHANGE: Config file format changed from YAML to environment
variables. See migration guide in docs/migration.md.
```

**Refactor with scope:**
```
refactor(db): extract query builder to separate module
```

## Example Output

```
$ /commit

Analyzing staged changes...

Staged files:
  M src/api/auth.py
  M src/services/user.py
  A tests/unit/test_auth.py

Change analysis:
- Type: feat (new functionality)
- Scope: auth (authentication module)
- Purpose: Add password reset feature

Commit message:
feat(auth): add password reset endpoint

- Add POST /auth/reset-password endpoint
- Add password reset token generation
- Add email notification service integration
- Add unit tests for reset flow

Co-Authored-By: Claude <noreply@anthropic.com>

Commit created: abc1234
```
