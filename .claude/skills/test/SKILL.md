---
name: test
description: >-
  Run the test suite with coverage reporting against the project's coverage gate. Use to
  verify a change, or when CI's Test job fails. Do not use to author new tests for new
  behavior — that is `/tdd` — and do not use it for linting or type checking (`/lint`).
---

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

## Workflow

Read `prd/00_technology.md` for actual commands and `.claude/rules/testing.md` for scope, TDD and coverage requirements.

- An explicit `target` runs that file, directory or test name. During change verification, start with affected checks; standalone `/test` without a change context runs the configured default suite. An explicit full-suite request is honored.
- `--coverage` reports coverage and preserves configured thresholds; do not add vacuous tests solely to raise a percentage. `--failed` reruns failures using the runner's supported mechanism. `--verbose` increases diagnostic output. `--watch` starts the requested persistent runner, reuses its process/session, and reports how it can be stopped.
- Diagnose failures before changing code, increasing timeouts or retrying. A test-only request does not authorize unrelated fixes. Use negative controls for material regressions when needed, not every assertion.
- Broaden checks for integration risk, new failures, unresolved concerns, required gates or explicit requests. Do not rerun passed checks on unchanged inputs without a reason. Lint/type checks remain their own commands except where configured gates require them.
- Follow `.claude/rules/delivery-contract.md` for real seam proof: mocks alone do not prove runtime delivery. Use authorized isolated test resources and representative non-sensitive state.

Report actual commands, scope, results, coverage when measured, and remaining uncertainty. Do not claim the whole product was tested from a focused run.
