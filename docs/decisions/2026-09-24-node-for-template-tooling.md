# 2026-09-24-node-for-template-tooling: Template Tooling Runs on the Runner's Default Node, Zero npm Dependencies

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Core team

## Context

This template is language-agnostic: a project adopting it may end up Python,
TypeScript, Go, or something else entirely, decided later in
`prd/00_technology.md`. But some tooling has to exist and run *before* that
choice is made — checking agent frontmatter against `.claude/agent-models.json`
(`scripts/sync-agent-models.mjs`), and now the ratchet gates
(`scripts/ratchet.mjs`) that keep known-bad patterns (silent exception
swallowing, orphaned test files) from creeping past their committed
baselines. CI's lint job runs both unconditionally, even against an
uninitialized template with no `pyproject.toml` yet.

Adding an npm dependency (a YAML parser, a glob library, a test runner) for
either script would mean a `package.json` + lockfile existing in a template
that may never become a Node project, plus a 24-hour dependency-cooldown and
pinning obligation (`.claude/rules/dependency-security.md`) for tooling that
does almost nothing. `sync-agent-models.mjs` already sets the precedent:
zero dependencies, plain `node scripts/sync-agent-models.mjs` in CI's lint
job, using only `node:fs`, `node:path`, and `node:url`.

## Decision

Template-level tooling scripts — files under `scripts/` that CI, the
Makefile, or `.claude/agent-lanes.json` invoke regardless of which stack a
project ultimately picks — run on the GitHub Actions runner's **default
Node** via plain `node <script>.mjs`, using only Node's built-in modules
(`node:fs`, `node:path`, `node:child_process`, `node:test`, etc.). No
`package.json`, no `node_modules`, no npm dependency of any kind.

This covers `scripts/sync-agent-models.mjs`, `scripts/ratchet.mjs`, and
their test suite `scripts/tests/ratchet.test.mjs` (run via `node --test
scripts/tests/`, itself dependency-free via `node:test` +
`node:assert/strict`).

Concretely: no `import` of anything not resolvable from Node's standard
library in these files; a hand-rolled minimal glob matcher and line-based
frontmatter editor instead of pulling in `minimatch` or `yaml`; `git
ls-files` shelled out via `node:child_process` instead of a git library.

## Consequences

**Positive:**
- Runs on any GitHub Actions `ubuntu-latest` runner with zero setup step —
  no `actions/setup-node`, no `npm install`, no lockfile to keep pinned and
  aged per `.claude/rules/dependency-security.md`.
- Works identically before and after a project picks its stack; an
  uninitialized template still gets these two checks enforced.
- No dependency-security surface (Rule 1–6 of that rule file) to audit for
  tooling this small — the smallest reuse rung that fully delivers the
  requirement.

**Negative:**
- Hand-rolled glob matching and line-based editing are less capable than a
  real library (e.g. no brace expansion, no negation patterns). Acceptable
  because the inputs are template-controlled config, not arbitrary user
  input.
- If either script's scope grows substantially (e.g. needs a real YAML
  parser for multi-document frontmatter), this decision should be revisited
  rather than quietly worked around with more hand-rolled parsing.

**Neutral:**
- Once a project initializes with a Node-based stack (`package.json` exists
  for the app itself), these scripts remain separate and dependency-free;
  they are not folded into the app's own dependency tree.

## Agent Guidance

Do not add an `import` of an npm package to `scripts/sync-agent-models.mjs`,
`scripts/ratchet.mjs`, or `scripts/tests/ratchet.test.mjs` — if a task seems
to need one, treat that as a signal to re-open this ADR rather than adding a
`package.json` to the template root.

## Do Not Change

- **No `package.json` at the template root**: adding one to support these
  scripts would imply a Node stack before `prd/00_technology.md` says so,
  and would bring the dependency-pinning/cooldown machinery into scope for
  tooling that doesn't need it.
- **`node scripts/ratchet.mjs` / `node scripts/sync-agent-models.mjs` run
  unconditionally in CI's lint job**, ungated by the "project initialized"
  check — both must keep working against an empty `src/`/`tests/` tree.
- **`node --test scripts/tests/`** as the test runner for this tooling — no
  Jest/Vitest/Mocha dependency for a handful of `node:test` cases.
