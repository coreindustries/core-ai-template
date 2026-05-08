# Git Workflow Rules

**Scope:** Git workflow (dirty worktrees, commit standards, hygiene)

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

**REQUIRED Format (Gitmoji + Conventional Commits):**
```
<emoji> <type>(<scope>)?: <description>

<body (optional)>

Co-Authored-By: Claude <noreply@anthropic.com>
```

Gitmoji prefix is **required** on every commit. The emoji-to-type
mapping is the canonical signal for visual scanning of `git log`. See
`.claude/references/gitmoji.md` for the full reference.

**Type → Gitmoji map:**

| Type | Emoji | When |
|---|---|---|
| `feat` | ✨ | New user-facing feature |
| `fix` | 🐛 | Bug fix |
| `docs` | 📝 | Documentation only |
| `style` | 🎨 | Formatting / no behavior change |
| `refactor` | ♻️ | Restructure without behavior change |
| `perf` | ⚡️ | Performance improvement |
| `test` | ✅ | Add or improve tests |
| `chore` | 🔧 | Maintenance / dep bumps |
| `ci` | 👷 | CI / CD changes |
| `build` | 📦️ | Build system changes |
| `revert` | ⏪ | Revert a prior commit |
| breaking | 💥 | Use **regardless of type** when the commit is a breaking change (e.g. `💥 feat!: drop Node 18`) |

**Example:**
```
✨ feat(auth): add user authentication with JWT

Implements JWT-based authentication with session storage. Includes
login, logout, and token refresh endpoints with full test coverage
and audit logging.

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Guidelines:**
- Use imperative mood ("add" not "added").
- Max 72 characters for the subject line (emoji + type + scope + description).
- No period at end of subject.
- Lowercase after the type.
- Reference tickets in the footer when available.
- The `commit-msg` hook accepts the leading emoji as part of the
  validation regex; commits without a Gitmoji are rejected.

## Git Hygiene Checklist

- [ ] Gitmoji prefix matches the type
- [ ] Conventional commit format used
- [ ] Co-authored by Claude attribution included (when applicable)
- [ ] Quality checks passed before commit
- [ ] No unrelated changes in commits
- [ ] Existing changes preserved (not reverted)
- [ ] Commit is atomic (single logical change)
