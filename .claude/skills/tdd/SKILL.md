---
name: tdd
description: "Red→green→refactor discipline for new behavior — forces a failing test before implementation and a passing test before any claim of done."
---

# /tdd

Red→green→refactor for new behavior. This skill exists to fix one specific, observable agent failure mode: writing a lot of code, visually checking it, and claiming success without running the tests. Capturing a failing test *before* the implementation, then the same test passing *after*, makes that failure mode impossible to sustain.

## Usage

```
/tdd <description of the new behavior>
```

## When to Use

Invoke when the work adds **new observable behavior** with a testable contract:

- New function, method, or class with defined inputs and outputs
- New API endpoint, route, or handler
- New validation rule, business rule, or state transition
- New branch in existing logic (new condition, new error path)
- Bug fix where you can write a test that reproduces the bug

## When NOT to Use

TDD hurts when no meaningful test can be written first. Skip it — with a documented reason — for:

- **Exploratory spikes** where the interface is undecided. Timebox the spike, then either discard or TDD the decided shape.
- **UI/visual work** where the verification is "does it look right." Use screenshot diffs or manual review instead.
- **Brownfield refactors** of untested code. Use `/refactor` — it writes characterization tests first, *then* refactors.
- **Pure scaffolding**: new package, config file, dependency install.
- **External integrations without stubs.** If you can't mock or record the dependency, defer until you can.

For any of these, state explicitly: *"Deferring TDD because `<reason>`. Will verify by `<what you'll do instead>`."* Do not silently skip.

## The Failure Mode This Fixes

Agents consistently exhibit this pattern:

1. Agent writes a function.
2. Agent reads the function.
3. Agent asserts "the function works."
4. The function doesn't work. The user finds out later.

Visual inspection is not proof. A test that was never observed to fail cannot prove the implementation made it pass — maybe it was always green, maybe it never actually ran against the new code. **The red→green transition is the proof.**

## The Cycle

### 1. Red — write a failing test

**Before writing any implementation:**

1. Write the smallest test that asserts the new behavior.
2. Run it. Capture the output.
3. Confirm the failure is the *expected* failure — not a syntax error, not an import error, not a "test not found" error. The assertion itself should fail.

```bash
{test_command} tests/unit/test_<feature>::<specific_test_name>
```

If the test doesn't fail, the test is wrong. The behavior already exists, or the assertion is tautological, or you're asserting against a mock that isn't exercised.

### 2. Green — make the test pass

Write the **minimum** implementation that makes the failing test pass. Not "the ideal implementation." Not "handle all the edge cases." The smallest change that turns the assertion from fail to pass.

Run the same test again. Capture the output. Confirm it passes.

If other tests break, stop. You introduced a regression. Fix or revert before continuing.

### 3. Refactor — clean up, tests still green

With tests passing, improve the implementation:

- Remove duplication
- Clarify names
- Extract helpers

After each change, re-run the test suite. If green stays green, keep the refactor. If something breaks, revert the refactor — never the green test.

## Required Evidence

When you report a TDD cycle complete, you MUST include:

- The test file and test name
- The command you ran
- The red output (the specific assertion that failed, or at minimum `1 failed / N passed`)
- The green output (the specific assertion passing, or `N+1 passed`)

"I wrote the test and the implementation and it works" is not acceptable evidence. Report with actual run output.

## Multi-Case Work

For new behavior with multiple cases (happy path + 2 error paths + edge case), loop the cycle once per case:

1. Red test for case 1 → green → refactor.
2. Red test for case 2 → green → refactor.
3. …

Do not write all the tests first, then all the implementation. That breaks the red→green observation — you can't tell which implementation change made which test go green, and "I wrote them all, they all pass" reintroduces the exact failure mode this skill prevents.

## What NOT to Do

- **Don't** write the test after the implementation. That's test-after-development; it gives you a passing test but not the proof that the test actually exercises the new code.
- **Don't** mock the system under test. Mock boundaries (DB, network, clock), not the function you're testing.
- **Don't** skip the red step "because it's obvious the test will fail." Agents have repeatedly claimed this and been wrong.
- **Don't** chain three unrelated assertions into one test. One test = one behavior.
- **Don't** claim a cycle complete while any test is skipped without a documented reason.

## Escape Hatch: Deferring TDD

If the work genuinely can't be TDD'd (see "When NOT to Use"), write a two-line note in the PR description or commit body:

```
TDD deferred. Reason: <why>
Verification plan: <what will verify the behavior instead>
```

Deferral without a note is the same as skipping — and skipping is exactly what this skill exists to prevent.

## See Also

- `.claude/rules/testing.md` — project-level test coverage minimums and organization
- `/refactor` — refactor with a test-first safety net when tests already exist
- `/debug` — systematic debugging when a test is already failing and you need to find out why
