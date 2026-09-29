---
name: ci
description: >-
  Generate or update CI/CD pipeline configuration for the project's stack, matching the
  gates already defined in .github/workflows/. Default to read-only status; generate
  a missing pipeline only when explicitly requested. Use fix mode for CI failures; general application debugging belongs to `/debug`.
  Preserve action version pins owned by Dependabot.
---

# /ci

Generate or update CI/CD pipeline configuration for the current stack.

## Usage

```
/ci [action] [--platform <platform>] [--fix]
```

## Arguments

- `action`: `generate`, `update`, `fix`, `status` (default: `status`)
- `--platform`: CI platform — `github` (default), `gitlab`, `bitbucket`
- `--fix`: Diagnose and fix a failing CI pipeline

## Workflow

Read `prd/00_technology.md`, existing pipeline configuration and its documentation before changing it. Follow `.claude/rules/delivery-contract.md`, `testing.md`, and `dependency-security.md`.

- `status` reports the current run and exact revision without editing.
- Explicit `generate` creates a pipeline only when one is missing and the project needs it, using existing templates when applicable; it does not replace a working pipeline or add deployment by default.
- `update` changes the requested jobs while preserving custom jobs, required gates and security controls.
- `fix` or `--fix` diagnoses the first actionable failure from the actual run and revision before editing. Reproduce the failing command where possible. Retries need a transient cause and safe replay; stop blind retries on repeated failure.
- `--platform` selects the requested platform; resolve actual commands from project configuration instead of copying another stack's recipe. Respect existing action-pin ownership.

Use the owning lockfile and native workspace layout. Reuse existing build/test commands; a new gate needs an uncovered failure, an owner and a decision that consumes its result. Validate configuration and affected commands, then distinguish local checks from a live CI run. Do not weaken required checks to obtain green status. Publishing, pushing or deployment requires the relevant authorization.
