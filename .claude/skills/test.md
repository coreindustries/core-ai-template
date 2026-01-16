# /test

Run tests with coverage reporting and quality gates.

## Usage

```
/test [target] [--coverage] [--watch] [--failed] [--verbose]
```

## Arguments

- `target`: Specific test file, directory, or test name (optional)
- `--coverage`: Generate coverage report (default: true)
- `--watch`: Watch mode for continuous testing
- `--failed`: Re-run only failed tests
- `--verbose`: Verbose output

## Instructions

When this skill is invoked:

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Complete test execution and analysis end-to-end
- If tests fail, analyze failures and suggest specific fixes
- If coverage is low, identify missing test cases and offer to implement them
- Don't just report results - provide actionable next steps

**Thoroughness:**
- Run full quality suite, not just tests
- Check `prd/02_Tech_stack.md` for project-specific commands:
  ```bash
  {lint_command}                    # Linting
  {type_check_command}              # Type checking
  {test_coverage_command}           # Tests with coverage
  ```
- Report on all aspects: tests, coverage, linting, type checking

**Problem-Solving:**
- If tests fail:
  1. Show the failure details with file:line references
  2. Analyze the root cause
  3. Suggest or implement the fix
  4. Re-run tests to verify
- If coverage is low:
  1. Identify uncovered lines (show file:line references)
  2. Suggest test cases to add
  3. Offer to implement the missing tests

**Presentation:**
- Lead with overall status (pass/fail, coverage %)
- Group results logically (by test file or category)
- Use file:line references for failures and missing coverage
- Provide clear next steps

### Default Run (All Tests)

1. **Read `prd/02_Tech_stack.md`** to find the correct test commands

2. **Run tests with coverage** (example patterns):
   ```bash
   # See prd/02_Tech_stack.md for your specific command
   {test_runner} tests/ --coverage
   ```

3. **Report results**:
   ```
   ==================== Test Results ====================

   ✅ Passed: 42
   ❌ Failed: 0
   ⏭️  Skipped: 2
   ⏱️  Duration: 3.45s

   ==================== Coverage ====================

   Name                              Stmts   Miss  Cover
   -----------------------------------------------------
   src/{project}/__init__              2      0   100%
   src/{project}/main                 45      0   100%
   ...
   -----------------------------------------------------
   TOTAL                             523      0   100%

   ✅ Coverage requirement met
   ```

### Specific Target

```bash
# Test a specific file
/test tests/unit/test_config

# Test a specific class/describe
/test tests/unit/test_api::TestHealthCheck

# Test a specific function/it
/test tests/unit/test_api::test_health_check

# Test a directory
/test tests/integration/
```

### Coverage Analysis

1. **If coverage < minimum**:
   ```
   ⚠️  Coverage below requirement: 95% (required: {min_coverage}%)

   Missing coverage in:
   - src/{project}/services/user:45-52 (error handling)
   - src/{project}/api/auth:78-85 (edge case)

   Suggested tests to add:
   1. Test error handling in UserService.create()
   2. Test authentication timeout scenario
   ```

2. **Generate detailed report** if available in your stack

### Integration Tests

When running integration tests:

1. **Check dependencies are running** (Docker services, etc.)
2. **Run with integration marker** from your test framework
3. **Verify cleanup** after tests

### Quality Gates

The test skill enforces these quality gates (see `prd/02_Tech_stack.md` for specific values):

| Gate | Requirement | Action on Failure |
|------|-------------|-------------------|
| Coverage | Minimum % | Block merge |
| All tests pass | 0 failures | Block merge |
| No skipped (without reason) | Documented skips only | Warn |
| Performance | No test > configured limit | Warn |

## Example Output

```
$ /test

🧪 Running tests...

tests/unit/test_config::TestSettings::test_default_values PASSED
tests/unit/test_config::TestSettings::test_is_development PASSED
tests/unit/test_api::test_health_check PASSED
tests/unit/test_api::test_root_endpoint PASSED

==================== 4 passed in 0.45s ====================

📊 Coverage: 100% ✅
```
