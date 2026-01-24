# Error Handling Rules

**Source:** PRD 01 - Technical Standards, Section 5

## Specific Exception Types

**REQUIRED:** Use specific exception/error types, not broad catches.

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

**REQUIRED:** Do NOT add broad exception catches or silent defaults.

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
