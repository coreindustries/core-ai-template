# Testing Rules

**Scope:** Testing standards (unit, integration, TDD, coverage)

## Unit Test Coverage

Minimum test coverage as defined in `prd/00_technology.md` (typically 66-100%).

- New behavior and non-trivial fixes need tests that catch their failure mode.
- Reuse existing coverage for behavior-preserving work; documentation, formatting and reversible mechanical edits do not need new test harnesses.
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

**For refactors that can alter behavior:** Establish affected behavior with existing tests or a focused characterization before editing.

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

A green unit test alone is not runtime-seam evidence. It only shows the code agrees with the test, and a test written from the same wrong mental model as the code will always agree with it. The failure is common and quiet: fixtures built from what the author *assumed* the data looks like, a retry budget that expired on every real call while its tests stayed green for months, a repair routine that matched nothing and logged "nothing to repair".

- **Take fixtures from reality.** Before writing a fixture for anything that parses or matches a data shape (API payload, DB row, file format, event), capture one real sample and note its source in the fixture or the PR. Do not infer the shape from nearby code: the same logical record often has different shapes one layer apart.
- **Make the fixture's shape an assertion** where practical, so a later edit that drifts back to the wrong shape fails loudly instead of passing quietly.
- **Use negative controls for material regressions.** Temporarily remove the fix or vary the failing input when needed to establish that the regression test catches the failure. Restore changes and report the result; do not mutation-test every assertion or mechanical edit.
- **Pin behavior down before changing it.** When modifying existing behavior with no test asserting what it does *today*, write that characterization test first. It is what catches the adjacent caller you did not know about.
- **Verify coherent changes at useful checkpoints.** Start with affected checks and real seam proof under `delivery-contract.md`. Broaden for relevant integration risk, a failure, unresolved concern, required gate or explicit request. Do not repeat passed checks on unchanged inputs without a reason.
- **Document invariants and respect them.** If code relies on something non-obvious always holding (ordering, idempotency, "never null", "must be absolute"), record it in a short `## Invariants` section in the module header or README. Treat any `## Invariants` you find as a hard constraint, and re-verify it after your change.
- **A constant tuned twice is a design smell.** If a timeout, retry count or budget has been widened more than once for the same bug, the shape is wrong, not the number.

## Test Organization

- **Unit** (`tests/unit/`): No I/O, mock externals, fast
- **Integration** (`tests/integration/`): Real DB, use fixtures
- **Markers**: Use test framework markers for categorization

## Speeding Up a Slow Suite

Speed work is a change like any other: it must not lose coverage, and it needs proof.

- **Measure first.** Run `pytest --durations=30` and fix the few largest causes before touching test files. Typical causes: fixed waits (a server `shutdown()` that waits for its poll interval, real `sleep`), the same constant data re-validated on every call, and schema migration or app construction per test. Removing tests is the smallest lever.
- **Order of work.** Remove waits and repeated setup, then run in parallel (pytest-xdist), then fold redundant tests.
- **Prove nothing was lost.** A green run is not proof. Compare per-file line and branch coverage (`--cov-branch`, JSON report) between the base commit and the branch, for each test scope (unit, integration). For folded tests, also mutate the code under test and run the old and new tests: no mutation the old tests killed may survive. Keep every original assertion; fold by parametrizing, or by merging tests that build the same state.
- **Shared database.** Tests that share one database go in one xdist group (`--dist loadgroup`). Set the marker in a `tryfirst` `pytest_collection_modifyitems` hook, because xdist reads it in its own hook of that name. If the schema is migrated once per process, any test that rolls it back re-applies it in `finally`, or one failure cascades into unrelated tests.
- **Shortened timeouts need a stress run.** After shortening a deadline or sleep, run the suite about 10 times with all cores busy (for example, one busy loop per core).
- **Report honest numbers.** Measure "before" on a clean checkout of the base commit with all extras installed. Report test count, time and total coverage for both. A smaller test count is not the goal.
- **Subagents.** Give each its own worktree, file list and database. Put the brief in a file, pass the worktree path, and have the agent confirm it with `pwd` before editing. Have it report a table mapping each folded test to its originals. The judge reviews the combined result.
- **Local gates.** Run the project's security scan (for example Bandit) yourself; a PR-check target may not include it.

## Testing Checklist

- [ ] Meaningful coverage for new behavior and non-trivial fixes
- [ ] Integration tests written for DB/API operations
- [ ] Tests cover happy path AND error cases
- [ ] Fixtures come from a real sample, not an assumed shape
- [ ] Material regression tests have a negative control where needed
- [ ] Coverage meets minimum (see tech stack)
- [ ] Edge cases covered
- [ ] Test markers used correctly
- [ ] Tests are independent
- [ ] Test data cleaned up after each run
- [ ] Speed-up changes carry a coverage diff, and folded tests a mutation check (see "Speeding Up a Slow Suite")

## Before Pull Request

**Final verification:**
- [ ] All tests pass
- [ ] Coverage is maintained or improved
- [ ] Integration tests pass
- [ ] Test markers correct
