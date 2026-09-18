# Code Quality Rules

**Scope:** Code quality standards (DRY, typing, naming, docs, project organization)

## DRY Principle (Don't Repeat Yourself)

Extract shared behavior rather than duplicating it — duplicated logic drifts, and
the copies stop agreeing without anyone noticing.

- Extract common functionality into reusable functions or modules
- Search for an existing implementation before writing a new one
- Refactor duplication when a review surfaces it

## Static Typing Requirements

Type everything: function signatures, class attributes, and return types all carry
annotations, using the modern syntax for the language version. Type checking gates
the merge — a failing type check is a broken build, not a warning.

## Naming Conventions

Naming follows the table below, so a reader can infer what a symbol is from how it is written.

| Element             | Convention         | Example                                       |
| ------------------- | ------------------ | --------------------------------------------- |
| Functions/methods   | Language standard  | `processData`, `process_data`                 |
| Classes/Types       | PascalCase         | `DataProcessor`, `UserService`                |
| Constants           | UPPER_SNAKE_CASE   | `MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT`          |
| Private members     | Language standard  | `_internal`, `#private`, `private`            |
| Modules/Files       | Language standard  | `dataUtils`, `data_utils`, `DataUtils`        |

## Code Documentation

Document what a reader cannot infer from the code itself.

- Modules and classes carry a docstring saying what they are for
- Public functions carry a docstring covering arguments, return, and what they raise
- Complex algorithms carry inline comments explaining *why*, not what

**Example structure (language-agnostic):**

```javascript
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

## Project Organization

Keep the project root clean — it is the first thing a new contributor reads.

**Allowed in root:**
- Configuration files (package manager, linter, type checker)
- Documentation: `README.md`, `LICENSE`, `CONTRIBUTING.md`, `CLAUDE.md`
- CI/CD: `.github/workflows/`
- Environment: `.env.example`

**Must be in subdirectories:**
- Source code → `src/`
- Tests → `tests/`
- Scripts → `scripts/`
- Documentation → `docs/`
- PRDs → `prd/`

## Code Review Checklist

Code review verifies:
- [ ] Type annotations on all functions and attributes
- [ ] Docstrings on all public functions and classes
- [ ] DRY principle followed
- [ ] Naming conventions followed
- [ ] No code duplication
- [ ] Modern syntax used
- [ ] Project organization followed
