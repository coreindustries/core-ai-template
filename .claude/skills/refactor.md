# /refactor

Safely refactor code with test-driven approach.

## Usage

```
/refactor <target> [--scope <scope>] [--dry-run]
```

## Arguments

- `target`: File, function, or pattern to refactor
- `--scope`: Limit refactoring scope (`function`, `file`, `module`)
- `--dry-run`: Show planned changes without executing

## Instructions

When this skill is invoked:

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Complete the refactoring end-to-end
- Run tests before, during, and after changes
- Verify no behavior changes unless explicitly requested

**Safety:**
- NEVER refactor without tests in place
- Create tests first if missing
- Make incremental changes with verification

**Quality:**
- Follow DRY principle
- Improve code clarity
- Maintain or improve test coverage

### Refactoring Process

1. **Verify tests exist**:
   ```bash
   {test_command} tests/ --collect-only
   ```
   If tests don't exist for the target:
   - Create tests first
   - Verify tests pass with current implementation
   - Document existing behavior

2. **Run tests to establish baseline**:
   ```bash
   {test_coverage_command}
   ```
   Record:
   - Number of passing tests
   - Coverage percentage
   - Test duration

3. **Plan the refactoring**:
   - Identify code smells or issues
   - Determine refactoring strategy
   - List files that will be affected
   - If `--dry-run`, present plan and stop

4. **Execute refactoring in small steps**:
   For each change:
   - Make the change
   - Run affected tests
   - Verify tests still pass
   - If tests fail, rollback and investigate

5. **Verify final state**:
   ```bash
   {test_coverage_command}
   ```
   Ensure:
   - ✅ All tests pass
   - ✅ Coverage not decreased
   - ✅ No new linting errors
   - ✅ Type checking passes

6. **Present changes**:
   - List all modified files
   - Summarize improvements
   - Show before/after metrics

### Common Refactoring Patterns

**Extract Function/Method:**
```
# Before
def process():
    # 50 lines of code

# After
def process():
    step1()
    step2()
    step3()
```

**Remove Duplication:**
```
# Before: Same code in 3 places
# After: Single shared function
```

**Simplify Conditionals:**
```
# Before
if x and y and z:
    if a or b:
        ...

# After
if should_process(x, y, z, a, b):
    ...
```

**Rename for Clarity:**
```
# Before
def proc(d):

# After
def process_user_data(user_data):
```

### Safety Rules

1. **Never refactor without tests**
2. **Make small, incremental changes**
3. **Run tests after each change**
4. **Preserve existing behavior** (unless explicitly changing it)
5. **Update documentation** if interfaces change
6. **Keep commits atomic** (one logical change per commit)

### Example Output

```
$ /refactor src/{project}/services/user --scope module

🔄 Refactoring: src/{project}/services/user

📋 Pre-refactor state:
- Tests: 24 passing
- Coverage: 95%
- Duration: 1.2s

📝 Planned changes:
1. Extract duplicate validation logic → shared validator
2. Rename process() → process_user_request()
3. Simplify nested conditionals in update()

🔧 Executing refactoring...

Step 1: Extract validation logic
  ✅ Tests pass (24/24)

Step 2: Rename process()
  ✅ Tests pass (24/24)

Step 3: Simplify conditionals
  ✅ Tests pass (24/24)

📋 Post-refactor state:
- Tests: 24 passing
- Coverage: 96% (+1%)
- Duration: 1.1s (-0.1s)

✅ Refactoring complete!

Changes made:
- src/{project}/services/user: Simplified, renamed functions
- src/{project}/utils/validators: New shared validation module
- tests/unit/test_user: Updated imports

Commit suggestion:
git commit -m "refactor(user): extract validation, improve naming"
```
