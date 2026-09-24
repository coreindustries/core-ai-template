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
`node scripts/ratchet.mjs` (CI's lint job, non-strict; `make ratchet` and
`make pr-check`, strict) scans `src/`, `tests/`, `scripts/` for Python
`except: pass` / `except: ...` (same line or next line, CRLF-safe) and
JS/TS empty or comment-only `catch {}`, `.catch(() => {})`,
`.catch(() => undefined | null)`, `.catch(async () => {})`, and
`.catch(function () {})`.

It's a ratchet, not a hard zero: the count can't rise above the baseline
committed in `.claude/ratchets.json` (always fatal — "regression"). A count
*below* baseline ("slack") is a warning in CI (two PRs that each
independently fix one site can otherwise both merge clean and leave the
baseline stale without turning CI red) and a failure under `--strict`,
which `make ratchet` and `make pr-check` use — run `--update` to resync
the baseline once the count has legitimately changed. A genuine exception
gets an inline `ratchet-allow: <reason>` comment — written as a real
comment on the matched line, in that file's comment syntax (`#`/`//`), not
just text anywhere in the file — rather than a baseline bump.

**Known gaps** (regex heuristic, not an AST — false negatives are possible
on anything below, so don't treat a clean ratchet run as proof there's no
silent swallowing):
- Multi-`except` chains that reassign or shadow the exception before
  discarding it.
- A `catch`/`except` that logs but never re-raises (a real anti-pattern,
  but a different one — this check only catches *empty* bodies).
- Nested or non-trivial parameter destructuring in a `catch(...)` clause
  can confuse the naive (non-nesting-aware) parenthesis matching.
- Python exception groups (`except*`) are not specially handled — matched
  the same as a regular `except`.
- A semicolon-only body (`catch (e) {;}`) is not recognized as empty.

Once a project picks a linter, prefer its native rule over the pattern
entry in `.claude/ratchets.json` — Python: `ruff` `S110` (`try-except-pass`);
JS/TS: `eslint` `no-empty` (catch clause). A linter rule runs the same
check with a proper AST instead of the ratchet's regex heuristic, closing
the gaps above; the ratchet exists for before a linter is configured, or
for a pattern the chosen linter doesn't cover.
