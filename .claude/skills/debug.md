# /debug

Systematic debugging workflow: reproduce, isolate, fix, and verify.

## Usage

```
/debug <issue> [--logs <path>] [--trace]
```

## Arguments

- `issue`: Description of the bug, error message, or issue number
- `--logs <path>`: Path to relevant log files
- `--trace`: Enable verbose tracing during investigation

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete the full debug cycle end-to-end
- Make reasonable hypotheses based on error patterns
- Implement and verify fixes without prompting

**Thoroughness:**
- Exhaust all likely causes before asking for help
- Document findings as you investigate
- Create regression tests for fixed bugs

**Methodology:**
- Follow scientific method: hypothesize → test → conclude
- Never change multiple things at once
- Always verify the fix resolves the original issue

### Debug Process

#### Phase 1: Understand

1. **Gather information**:
   - Read error message/stack trace carefully
   - Identify the failing component
   - Note when the issue started (if known)

2. **Read relevant code** in parallel:
   - File where error occurs
   - Related files (imports, dependencies)
   - Recent changes to affected area

3. **Check logs** if available:
   ```bash
   # Recent logs
   tail -100 {log_path}

   # Search for errors
   grep -i "error\|exception\|fail" {log_path}
   ```

#### Phase 2: Reproduce

1. **Create minimal reproduction**:
   - Identify exact steps to trigger the bug
   - Reduce to smallest failing case
   - Document reproduction steps

2. **Write a failing test**:
   ```bash
   # Create test that captures the bug
   {test_command} tests/unit/test_bug_reproduction.py -v
   ```

3. **Verify test fails** for the right reason

#### Phase 3: Isolate

1. **Form hypotheses** (list 3-5 likely causes):
   - Hypothesis 1: [Most likely cause]
   - Hypothesis 2: [Second most likely]
   - Hypothesis 3: [Edge case possibility]

2. **Test each hypothesis**:
   - Add logging/print statements
   - Use debugger breakpoints
   - Check variable states

3. **Binary search** if issue location unclear:
   - Comment out half the code
   - Determine which half contains the bug
   - Repeat until isolated

4. **Check common causes**:
   - Null/undefined values
   - Off-by-one errors
   - Race conditions
   - Type mismatches
   - Missing error handling
   - Configuration issues

#### Phase 4: Fix

1. **Implement minimal fix**:
   - Change only what's necessary
   - Don't refactor during bug fix
   - Keep the fix focused

2. **Verify fix**:
   ```bash
   # Run the failing test
   {test_command} tests/unit/test_bug_reproduction.py -v

   # Run related tests
   {test_command} tests/unit/test_{module}.py -v

   # Run full test suite
   {test_command} tests/ -v
   ```

3. **Add regression test** if not already covered

#### Phase 5: Document

1. **Update issue/ticket** with:
   - Root cause analysis
   - Fix description
   - Prevention measures

2. **Create commit** with clear message:
   ```
   fix(scope): description of what was fixed

   Root cause: [explanation]
   Solution: [what was changed]

   Closes #issue_number
   ```

### Capture Knowledge

If this fix took more than 15 minutes to diagnose, or the root cause was non-obvious, run `/compound` to capture the solution. This prevents future re-discovery of the same problem and builds the project's knowledge base in `docs/solutions/`.

### Debug Checklist

- [ ] Error message understood
- [ ] Issue reproduced locally
- [ ] Failing test written
- [ ] Root cause identified
- [ ] Minimal fix implemented
- [ ] All tests pass
- [ ] Regression test added
- [ ] Fix documented
- [ ] Knowledge captured with `/compound` (if non-trivial fix)

### Common Debug Patterns

**Null Reference:**
```
# Symptom: "Cannot read property X of undefined"
# Check: Is the object initialized? Is it returned from async?
```

**Race Condition:**
```
# Symptom: Intermittent failures, works sometimes
# Check: Async operations, shared state, missing awaits
```

**Type Error:**
```
# Symptom: "Expected X but got Y"
# Check: API response shape, serialization, type coercion
```

**Configuration:**
```
# Symptom: Works locally, fails in CI/prod
# Check: Environment variables, file paths, permissions
```

## Example Output

```
$ /debug "TypeError: Cannot read property 'id' of undefined in UserService"

====== Phase 1: Understand ======

Error: TypeError: Cannot read property 'id' of undefined
Location: src/services/user.py:45
Stack trace points to: getUserById() method

Reading relevant files...
- src/services/user.py
- src/api/users.py
- tests/unit/test_user.py

====== Phase 2: Reproduce ======

Reproduction steps:
1. Call GET /api/users/999 (non-existent ID)
2. Service returns undefined instead of null
3. Caller tries to access .id property

Writing failing test...
Created: tests/unit/test_user_not_found.py

Test result: FAILED (as expected)

====== Phase 3: Isolate ======

Hypotheses:
1. getUserById returns undefined for missing users
2. Database query doesn't handle empty results
3. Null check missing in API layer

Testing hypothesis 1...
Confirmed: getUserById returns undefined, not null

Root cause: Missing null check after database query

====== Phase 4: Fix ======

Fix: Add explicit null return when user not found

src/services/user.py:45
- return result
+ return result if result else None

Running tests...
- test_user_not_found: PASSED
- test_user_service: PASSED (15/15)
- Full suite: PASSED (142/142)

====== Phase 5: Document ======

Root cause: Database query returned undefined for missing records,
but callers expected null. This caused a TypeError when accessing
properties on the undefined value.

Fix: Added explicit null return with proper type hints.

Ready to commit:
fix(user): handle missing user in getUserById

Closes #789
```
