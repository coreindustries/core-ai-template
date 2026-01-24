# Code Quality Rules

**Source:** PRD 01 - Technical Standards, Section 3

## DRY Principle (Don't Repeat Yourself)

**REQUIRED:** All code MUST follow the DRY principle.

- Extract common functionality into reusable functions or modules
- Avoid code duplication across files or services
- Create shared utilities for common patterns
- Search for existing implementations before creating new code
- Refactor duplicated code when identified during reviews

## Static Typing Requirements

**REQUIRED:** Static typing MUST be used for all code.

- All function signatures MUST include type annotations
- All class attributes MUST be type-annotated
- All return types MUST be specified
- Use modern syntax for your language version
- Type checking MUST pass before code can be merged

## Naming Conventions

**REQUIRED:** All code MUST follow consistent naming conventions.

| Element             | Convention         | Example                                       |
| ------------------- | ------------------ | --------------------------------------------- |
| Functions/methods   | Language standard  | `processData`, `process_data`                 |
| Classes/Types       | PascalCase         | `DataProcessor`, `UserService`                |
| Constants           | UPPER_SNAKE_CASE   | `MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT`          |
| Private members     | Language standard  | `_internal`, `#private`, `private`            |
| Modules/Files       | Language standard  | `dataUtils`, `data_utils`, `DataUtils`        |

## Code Documentation

**REQUIRED:** All code MUST be documented.

- All modules MUST have a module-level docstring/comment
- All classes MUST have a class-level docstring/comment
- All public functions MUST have docstrings (use project's convention)
- Complex algorithms MUST include inline comments

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

**REQUIRED:** The project root MUST be kept clean.

**Allowed in root:**
- Configuration files (package manager, linter, type checker)
- Documentation: `README.md`, `LICENSE`, `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`
- CI/CD: `.github/workflows/`
- Environment: `.env.example`

**Must be in subdirectories:**
- Source code → `src/`
- Tests → `tests/`
- Scripts → `scripts/`
- Documentation → `docs/`
- PRDs → `prd/`

## Code Review Checklist

All code reviews MUST verify:
- [ ] Type annotations on all functions and attributes
- [ ] Docstrings on all public functions and classes
- [ ] DRY principle followed
- [ ] Naming conventions followed
- [ ] No code duplication
- [ ] Modern syntax used
- [ ] Project organization followed
