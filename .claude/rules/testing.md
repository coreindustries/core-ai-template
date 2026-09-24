# Testing Rules

**Scope:** Testing standards (unit, integration, TDD, coverage)

## Unit Test Coverage

Minimum test coverage as defined in `prd/00_technology.md` (typically 66-100%).

- All new code MUST have corresponding unit tests
- Use project's designated test framework
- Use coverage reporting tools

**Test file naming:**
- Separate test files: `tests/unit/test_{module}.{ext}`

## Integration Testing

Integration tests for all database and external service interactions.

- Test database operations against real (test) database
- Test API endpoints with test client
- Clean up test data after each run
- Use containers for external dependencies
- Mark with appropriate test markers

## Test-Driven Development Pattern

**REQUIRED when adding new behavior:** Write the failing test before the implementation. Use `/tdd` to run the red→green→refactor cycle with required evidence of the red→green transition.

**REQUIRED when refactoring:** Ensure tests exist before modifying code.

**Pattern (new behavior — see `/tdd`):**
1. Red: write the smallest failing test; run and capture the failure
2. Green: write the minimum implementation; run and capture the pass
3. Refactor: clean up with tests staying green
4. Loop per case for multi-case work — never batch all tests then all implementation

**Pattern (refactoring existing code):**
1. Verify tests exist and pass
2. Make changes
3. Verify tests still pass
4. Add new tests for new behavior
5. Verify coverage hasn't decreased

## Tests That Prove Something

A green test is not evidence. It only shows the code agrees with the test, and a test written from the same wrong mental model as the code will always agree with it. The failure is common and quiet: fixtures built from what the author *assumed* the data looks like, a retry budget that expired on every real call while its tests stayed green for months, a repair routine that matched nothing and logged "nothing to repair".

- **Take fixtures from reality.** Before writing a fixture for anything that parses or matches a data shape (API payload, DB row, file format, event), capture one real sample and note its source in the fixture or the PR. Do not infer the shape from nearby code: the same logical record often has different shapes one layer apart.
- **Make the fixture's shape an assertion** where practical, so a later edit that drifts back to the wrong shape fails loudly instead of passing quietly.
- **Mutation-check every fix.** Break the fix (revert the line, flip the condition), confirm the new test fails, then restore it. State the result: "removing the fix fails 2 of 9". A test that passes with and without the change measures nothing.
- **Pin behavior down before changing it.** When modifying existing behavior with no test asserting what it does *today*, write that characterization test first. It is what catches the adjacent caller you did not know about.
- **Test each edit before the next one.** Run the targeted test for what you just changed before moving on. A failure against one small change is easy to diagnose; a failure against an accumulated diff is a hunt.
- **Document invariants and respect them.** If code relies on something non-obvious always holding (ordering, idempotency, "never null", "must be absolute"), record it in a short `## Invariants` section in the module header or README. Treat any `## Invariants` you find as a hard constraint, and re-verify it after your change.
- **A constant tuned twice is a design smell.** If a timeout, retry count or budget has been widened more than once for the same bug, the shape is wrong, not the number.

## Test Organization

- **Unit** (`tests/unit/`): No I/O, mock externals, fast
- **Integration** (`tests/integration/`): Real DB, use fixtures
- **Markers**: Use test framework markers for categorization

## Testing Checklist

- [ ] Unit tests written for new code
- [ ] Integration tests written for DB/API operations
- [ ] Tests cover happy path AND error cases
- [ ] Fixtures come from a real sample, not an assumed shape
- [ ] Every fix mutation-checked (test fails without it)
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
