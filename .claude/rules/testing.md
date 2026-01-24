# Testing Rules

**Source:** PRD 01 - Technical Standards, Section 7

## Unit Test Coverage

**REQUIRED:** Minimum test coverage as defined in `prd/02_Tech_stack.md` (typically 66-100%).

- All new code MUST have corresponding unit tests
- Use project's designated test framework
- Use coverage reporting tools

**Test file naming:**
- Separate test files: `tests/unit/test_{module}.{ext}`

## Integration Testing

**REQUIRED:** Integration tests for all database and external service interactions.

- Test database operations against real (test) database
- Test API endpoints with test client
- Clean up test data after each run
- Use containers for external dependencies
- Mark with appropriate test markers

## Test-Driven Development Pattern

**REQUIRED when refactoring:** Ensure tests exist before modifying code.

**Pattern:**
1. Verify tests exist and pass
2. Make changes
3. Verify tests still pass
4. Add new tests for new behavior
5. Verify coverage hasn't decreased

## Test Organization

- **Unit** (`tests/unit/`): No I/O, mock externals, fast
- **Integration** (`tests/integration/`): Real DB, use fixtures
- **Markers**: Use test framework markers for categorization

## Testing Checklist

- [ ] Unit tests written for new code
- [ ] Integration tests written for DB/API operations
- [ ] Tests cover happy path AND error cases
- [ ] Coverage meets minimum (see tech stack)
- [ ] Edge cases covered
- [ ] Test markers used correctly
- [ ] Tests are independent
- [ ] Test data cleaned up after each run

## Before Pull Request

**Final verification:**
- [ ] All tests pass
- [ ] Coverage is maintained or improved
- [ ] Integration tests pass
- [ ] Test markers correct
