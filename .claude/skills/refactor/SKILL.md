---
name: refactor
description: >-
  Restructure code without changing behavior, with tests verified green before and after
  so any behavior change surfaces immediately. Use when structure is impeding work on
  code that is already covered by tests. Establish missing behavioral coverage before risky changes; mechanical or
  documentation edits need proportionate checks. Keep behavior changes separate.
---

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

## Workflow

Read `.claude/rules/code-quality.md`, `testing.md` and `delivery-contract.md`.

1. Name the recurring cost or structural problem, preserved behavior, callers and scope. Prefer existing modules and supported interfaces. Do not invent a refactor merely to delete code.
2. Respect `--scope`; use architect/planner under `CLAUDE.md` when needed. Name the authoritative owner after replacement and retire old callers, launch paths, flags, tests and docs. Necessary coexistence needs an owner and observable removal condition.
3. `--dry-run` returns the plan without edits, including test additions. For implementation, establish affected behavior with existing tests or a focused characterization before changes that can alter behavior. Documentation or mechanical edits do not require a new harness.
4. Make coherent, bounded changes and run affected checks at useful checkpoints. New behavior is separate scope. Diagnose failures and preserve coverage and required gates.
5. Complete mandatory judge review. Report the structure changed, retired paths, evidence and unresolved compatibility; file or line counts alone do not prove improvement.
