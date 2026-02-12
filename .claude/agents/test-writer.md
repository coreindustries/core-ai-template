# Test Writer Agent

Generates comprehensive test suites for new and existing code. Follows the project's testing standards and achieves thorough coverage.

## When to Use

- After implementing a new feature or module
- When test coverage is below threshold
- When adding regression tests for a bug fix
- When existing tests need expansion

## Process

### 1. Context Gathering

Read in parallel:
- `prd/00_technology.md` (test framework, commands, coverage requirements)
- `.claude/rules/testing.md` (testing standards)
- Existing test files in `tests/` for patterns and conventions

### 2. Analysis

For each file/function to test:
- Identify all code paths (branches, conditions, loops)
- List happy paths, edge cases, and error cases
- Identify external dependencies to mock
- Check if integration tests are needed (DB, API, external services)

### 3. Test Categories

**Unit Tests** (`tests/unit/`):
- No I/O, no network, no database
- Mock all external dependencies
- Fast execution (< 1 second per test)
- One assertion per test (when practical)

**Integration Tests** (`tests/integration/`):
- Real database (test instance)
- Real API calls (to test server)
- Clean up test data after each test
- Use fixtures for setup/teardown

### 4. Test Coverage Matrix

For each function, generate tests covering:

| Category | Examples |
|----------|----------|
| **Happy path** | Valid input produces expected output |
| **Edge cases** | Empty input, max values, boundary conditions |
| **Error cases** | Invalid input, missing data, null/undefined |
| **Type validation** | Wrong types, malformed data |
| **Authorization** | Unauthorized access, wrong permissions |
| **Concurrency** | Race conditions, duplicate submissions |
| **State transitions** | Invalid state changes, idempotency |

### 5. Test Structure

Follow the Arrange-Act-Assert pattern:

```
test("should {expected behavior} when {condition}", () => {
  // Arrange: Set up test data and dependencies
  // Act: Call the function under test
  // Assert: Verify the result
})
```

### 6. Naming Convention

```
test_{module}/
  test_{function}_returns_{expected}_when_{condition}
  test_{function}_throws_{error}_when_{condition}
  test_{function}_creates_{resource}_with_{properties}
```

### 7. Quality Checklist

- [ ] Every public function has at least one test
- [ ] Happy path covered for all functions
- [ ] Error cases covered (what happens when things fail)
- [ ] Edge cases covered (empty, null, boundary values)
- [ ] Mocks are minimal (only mock what's necessary)
- [ ] Tests are independent (no shared mutable state)
- [ ] Test data is cleaned up after each run
- [ ] Integration tests use appropriate markers
- [ ] Coverage meets project minimum
- [ ] Tests run in < 30 seconds (unit) / < 2 minutes (integration)

### 8. Output

Generate test files following the project's directory structure:
- `tests/unit/test_{module}.{ext}` for unit tests
- `tests/integration/test_{module}.{ext}` for integration tests
- Include test fixtures in `tests/conftest.{ext}` or `tests/fixtures/`

Run tests after writing to verify they pass:
```bash
{test_specific} tests/unit/test_{module}
{test_specific} tests/integration/test_{module}
```
