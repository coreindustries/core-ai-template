---
name: docs
description: "Generate and update project documentation."
---

# /docs

Generate and update project documentation.

## Usage

```
/docs [target] [--type <type>] [--update]
```

## Arguments

- `target`: Specific file, module, or "all" (default: changed files)
- `--type`: Documentation type (api, readme, changelog, jsdoc, docstring)
- `--update`: Update existing docs instead of regenerating

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Analyze code and generate appropriate documentation
- Follow project's existing documentation style
- Complete documentation without prompting

**Quality:**
- Documentation should be accurate and up-to-date
- Include examples where helpful
- Keep docs concise but complete

### Documentation Process

1. **Analyze target**:
   - If specific file: Document that file
   - If "all": Document all public APIs
   - If no target: Document recently changed files

2. **Detect documentation style** from existing docs:
   - Check for JSDoc, Google-style docstrings, etc.
   - Note formatting conventions
   - Identify required sections

3. **Generate documentation** based on type

### Documentation Types

#### API Documentation (`--type api`)

Generate OpenAPI/Swagger or API reference:

```markdown
## Endpoints

### POST /api/users

Create a new user.

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| email | string | Yes | User email address |
| name | string | Yes | Display name |

**Response:**
- `201`: User created successfully
- `400`: Validation error
- `409`: Email already exists

**Example:**
```json
{
  "email": "user@example.com",
  "name": "John Doe"
}
```
```

#### README Updates (`--type readme`)

Update project README with:
- Installation instructions
- Usage examples
- Configuration options
- API overview

#### Changelog (`--type changelog`)

Generate changelog entry from commits:

```markdown
## [1.2.0] - 2026-01-17

### Added
- User authentication with JWT tokens (#123)
- Password reset functionality (#124)

### Changed
- Improved error messages for validation failures

### Fixed
- Race condition in session management (#125)
```

#### Code Documentation (`--type docstring` or `--type jsdoc`)

**Python (Google-style):**
```python
def get_user(user_id: str) -> User | None:
    """Retrieve a user by their unique identifier.

    Args:
        user_id: The unique identifier of the user.

    Returns:
        The User object if found, None otherwise.

    Raises:
        DatabaseError: If the database connection fails.

    Example:
        >>> user = get_user("abc123")
        >>> print(user.name)
        "John Doe"
    """
```

**TypeScript (JSDoc):**
```typescript
/**
 * Retrieve a user by their unique identifier.
 *
 * @param userId - The unique identifier of the user
 * @returns The User object if found, null otherwise
 * @throws {DatabaseError} If the database connection fails
 *
 * @example
 * const user = await getUser("abc123");
 * console.log(user.name); // "John Doe"
 */
```

### Documentation Checklist

- [ ] All public functions/methods documented
- [ ] Parameters and return types described
- [ ] Examples provided for complex APIs
- [ ] Error cases documented
- [ ] README reflects current state
- [ ] Changelog updated for releases

### Auto-Detection

When no type specified, detect from context:
- `.py` files → docstrings
- `.ts/.js` files → JSDoc
- `README.md` → readme
- `CHANGELOG.md` → changelog
- `api/` directory → api docs

## Example Output

```
$ /docs src/services/user.py --type docstring

Analyzing: src/services/user.py

Functions to document:
- get_user (line 15) - Missing docstring
- create_user (line 32) - Incomplete docstring
- update_user (line 58) - Missing docstring
- delete_user (line 89) - OK

Generating documentation...

Updated src/services/user.py:

+ def get_user(user_id: str) -> User | None:
+     """Retrieve a user by their unique identifier.
+
+     Args:
+         user_id: The unique identifier of the user.
+
+     Returns:
+         The User object if found, None otherwise.
+
+     Raises:
+         DatabaseError: If the database connection fails.
+     """

[... additional updates ...]

Documentation complete:
- 3 functions documented
- 1 function already documented
- 0 functions skipped
```

```
$ /docs --type changelog

Analyzing commits since last release (v1.1.0)...

Commits found: 12
- 4 feat commits
- 3 fix commits
- 5 chore commits

Generated CHANGELOG entry:

## [Unreleased]

### Added
- feat(auth): add password reset endpoint (#145)
- feat(user): add profile picture upload (#142)
- feat(api): add rate limiting middleware (#138)
- feat(notifications): add email notifications (#136)

### Fixed
- fix(auth): handle expired tokens gracefully (#144)
- fix(db): resolve connection pool exhaustion (#141)
- fix(api): correct pagination offset calculation (#139)

Append to CHANGELOG.md? (Entry added at top of file)
```
