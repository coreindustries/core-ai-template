# Error Handling Rules

**Scope:** Error handling patterns (specific exceptions, tight handling)

## Specific Exception Types

Use specific exception/error types, not broad catches.

- Create custom exceptions for domain errors
- Always include context in error messages
- Never swallow exceptions silently

**Example error class structure:**

```typescript
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

## Tight Error Handling

Do NOT add broad exception catches or silent defaults.

**What to Avoid:**
- Broad `try/catch` blocks that swallow errors
- Catching all exceptions without re-raising or logging
- Success-shaped fallbacks that hide failures
- Early returns on invalid input without logging

**Example:**

```typescript
// BAD: Silent failure
function getUser(userId: string) {
  try {
    return db.user.find(userId)
  } catch (e) {
    return null  // What happened? Why did it fail?
  }
}

// GOOD: Explicit error handling
function getUser(userId: string): User {
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

## Error Handling Checklist

- [ ] Custom exception types created for domain errors
- [ ] Error messages include context
- [ ] No silent exception swallowing
- [ ] Errors are logged appropriately
- [ ] Errors are re-raised or handled explicitly
- [ ] No success-shaped fallbacks hiding failures

## Enforcement

"No silent exception swallowing" is checked, not just written policy:
`node scripts/ratchet.mjs` (`make ratchet`, wired into CI's lint job and
`make pr-check`) scans for bare `except: pass` (Python) and empty
`catch {}` / `.catch(() => {})` (JS/TS) under `src/`, `tests/`, `scripts/`.
It's a ratchet, not a hard zero: the count can't rise above the baseline
committed in `.claude/ratchets.json`, and CI fails just the same if the
count drops below it without the baseline being lowered via `--update` —
that "slack" check exists so a new silent catch can't hide in headroom
left by an unrelated fix. A genuine exception gets an inline
`ratchet-allow: <reason>` comment rather than a baseline bump.

Once a project picks a linter, prefer its native rule over the pattern
entry in `.claude/ratchets.json` — Python: `ruff` `S110` (`try-except-pass`);
JS/TS: `eslint` `no-empty` (catch clause). A linter rule runs the same
check with a proper AST instead of the ratchet's regex heuristic; the
ratchet exists for the gap before a linter is configured, or for a
pattern the chosen linter doesn't cover.
