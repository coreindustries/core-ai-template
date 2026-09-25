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
`node scripts/ratchet.mjs` scans `src/`, `tests/`, `scripts/` for Python
`except: pass` / `except: ...` (same line or next line, CRLF-safe, word-
bounded so `on_except(` isn't mistaken for `except`) and JS/TS empty or
comment-only `catch {}`, `.catch(() => {})`, `.catch((e: unknown) => {})`,
`.catch(() => undefined | null)`, `.catch(async () => {})`, and
`.catch(function () {})`. Both CI's lint job and `make pr-check` run it
**non-strict**, deliberately — see the slack paragraph below. `make
ratchet`/`make quality` run it `--strict`.

It's a ratchet, not a hard zero: the count can't rise above the baseline
committed in `.claude/ratchets.json` (always fatal — "regression"). A count
*below* baseline ("slack") is a warning by default and a failure only
under `--strict`: two PRs that each independently fix one site can
otherwise both merge clean and leave the baseline stale, and if pr-check
ran strict, every *other* unrelated PR would then fail until someone
noticed and ran `--update` — non-strict in CI/pr-check avoids that,
`--strict` locally is how you notice the baseline has drifted and should
be resynced. A genuine exception gets an inline
`ratchet-allow(<check-id>): <reason>` comment — the check-id must match
(`silent-exception-swallowing` here), written as a comment on the matched
line, in that file's comment syntax (`#`/`//`) — rather than a baseline
bump. This is a substring heuristic, not real comment parsing, so a string
literal that happens to contain the exact marker text could still fool
it; that residual gap is accepted because any exemption is visible and
reviewable in the diff that adds it.

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
- Python: a comment line between `except ...:` and `pass`, or a
  multi-line tuple in the except clause (`except (A,\n B):`), is not
  recognized — the pattern only looks at the line immediately following
  the colon.
- JS/TS: a comment-only catch body written entirely on one line, with the
  closing brace on that *same* line (`catch (e) { // ignore }`), is not
  recognized. The line-comment branch must consume through end-of-line to
  stay ReDoS-safe (see the caution in `.claude/ratchets.json`'s
  `_comment`), so it swallows the closing brace too when there's no
  newline to stop it first. Write such catches on two lines, or use
  `.catch(() => null)` / `.catch(() => undefined)` for promises, which
  this check does detect. A well-known idiom that legitimately needs an
  exemption either way: `fs.stat(p).catch(() => null)` to probe file
  existence — mark it `// ratchet-allow(silent-exception-swallowing):
  probing existence, absence is expected` rather than restructuring it.

Once a project picks a linter, prefer its native rule over the pattern
entry in `.claude/ratchets.json` — Python: `ruff` `S110` (`try-except-pass`);
JS/TS: `eslint` `no-empty` (catch clause). A linter rule runs the same
check with a proper AST instead of the ratchet's regex heuristic, closing
the gaps above; the ratchet exists for before a linter is configured, or
for a pattern the chosen linter doesn't cover.
