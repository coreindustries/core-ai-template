---
name: review
description: >-
  Multi-perspective code review against project standards with P1/P2/P3 severity
  classification. Works in Claude Code (Agent + optional GitHub MCP) and Cursor
  (Task subagents + gh/git). Use when the user invokes /review, asks for a PR or
  diff review, or wants a standards-aligned review with severity tags.
---

# /review

Multi-perspective code review against project standards with P1/P2/P3 severity classification.

**Runtimes:** Use the blocks labeled **Claude Code** or **Cursor** below. Steps 2, 4, and 6 are identical for both.

## Usage

```
/review [target] [--pr <number|branch>] [--last <n>] [--fix] [--strict]
```

## Arguments

- `target`: File or directory to review (default: staged changes)
- `--pr <number>`: Review a GitHub PR by number (open or merged), via MCP or `gh`
- `--pr <branch>`: Review changes from a local branch vs `main` (or repo default branch)
- `--last <n>`: Review the last `n` merged PRs (skips registry/CSS-only changes)
- `--fix`: After generating the report, implement all P1 and P2 fixes, run tests, commit, push, and open a PR
- `--strict`: Treat P3 findings as P2 (require fixes before merge)

## Specialist delegation (token budget)

| Perspective    | Inline? | Claude Code              | Cursor                                      |
|----------------|---------|--------------------------|---------------------------------------------|
| Code Quality   | yes     | (same)                   | (same)                                      |
| Architecture   | yes     | (same)                   | (same)                                      |
| Performance    | no      | `Agent` with `haiku`     | `Task` with `subagent_type: "perf-auditor"` |
| Security       | no      | `Agent` with `sonnet`    | `Task` with `subagent_type: "security-reviewer"` |
| Simplicity + Data Integrity | no | one `Agent` with `sonnet` (combined prompt) | one `Task` (combined prompt; see Step 3) |

In **Cursor**, do not pass `model: "haiku"` / `"sonnet"` unless the user asked for an explicit model slug your environment supports. Default subagent models are fine.

## Instructions

When this skill is invoked:

### Step 1 — Identify the diff

- **`--pr <number>`**
  - **Claude Code (if GitHub MCP is configured):** call the GitHub MCP diff fetch for that PR (e.g. tools like `pull_request_read` / `get_diff`, depending on the MCP server).
  - **Fallback / Cursor:** `gh pr diff <number>` (works when the repo is a GitHub checkout with `gh` auth).

- **`--pr <branch>`:** `git diff main...{branch}` (replace `main` with the repo default branch if different).

- **`--last <n>`:**
  - **With GitHub MCP:** list recent PRs, filter to substantive changes (skip titles like `chore(registry)`, trivial/CSS-only), fetch diffs in parallel.
  - **With `gh` only:** `gh pr list --state merged --limit <n+5> --json number,title`, filter the same way, then `gh pr diff <number>` for each selected PR.

- **`target` specified:** `git diff HEAD -- <target>`

- **default:** `git diff --staged`

### Step 2 — Run inline checks (no delegation cost)

Do these yourself directly against the diff:

**Code Quality** (`.claude/rules/code-quality.md`):
- [ ] Type annotations on all functions and return types
- [ ] Docstrings on public functions and classes
- [ ] DRY principle followed (no duplicated logic)
- [ ] Naming conventions followed (language standard)
- [ ] No broad exception catches or silent failures
- [ ] No dead code, TODOs, or placeholder implementations
- [ ] All relevant surfaces updated (models, services, routes, tests)
- [ ] Tests exist for new behavior

**Architecture** (project patterns from `prd/00_technology.md`):
- [ ] Routes are thin — delegate to service layer
- [ ] Business logic lives in services, not handlers
- [ ] Database access follows project singleton pattern
- [ ] No circular dependencies introduced
- [ ] Separation of concerns maintained

### Step 3 — Spawn specialist reviewers in parallel

Send **three** delegations in a **single assistant turn** so they run concurrently. Paste the same `<diff>` into each prompt.

**Claude Code** — three `Agent` calls:

```
Agent(
  model: "haiku",
  prompt: """Review this diff for performance issues only.
  Check: N+1 queries, missing pagination, unbounded data loads,
  missing timeouts on external calls, unnecessary sequential ops
  that could be parallel, expensive ops in hot paths.
  Cite file:line for every finding. Return P1/P2/P3.
  <diff>{diff}</diff>"""
)

Agent(
  model: "sonnet",
  prompt: """Review this diff for security issues only.
  Consult .claude/rules/security-core.md.
  Check: hardcoded secrets, SQL/shell injection, missing auth checks,
  unvalidated user input, insecure dependencies, PII in logs.
  Cite file:line for every finding. Return P1/P2/P3.
  <diff>{diff}</diff>"""
)

Agent(
  model: "sonnet",
  prompt: """Review this diff for two concerns — simplicity and data integrity.

  Simplicity: unnecessary abstractions, over-engineering, functions doing
  too much, unclear logic that could be simpler.

  Data integrity: missing input validation (lengths, ranges, enums),
  missing DB constraints (NOT NULL, FKs, indexes), unsafe migrations,
  invalid state transitions, unhandled nulls.

  Cite file:line for every finding. Return P1/P2/P3 for each.
  <diff>{diff}</diff>"""
)
```

> Simplicity and Data Integrity share one `sonnet` call to avoid a third parallel heavy model — they rarely conflict.

**Cursor** — three `Task` calls with `subagent_type`:

| Call | `subagent_type`        | Prompt focus |
|------|-------------------------|--------------|
| 1    | `perf-auditor`          | Same focus as Claude Code haiku prompt above |
| 2    | `security-reviewer`     | Same focus as Claude Code security prompt above |
| 3    | `simplicity-reviewer`   | Same **combined** simplicity + data integrity prompt as the third Claude Code `Agent` block |

Optional: set `readonly: true` on each `Task` when you only want review output (no writes).

> **Note:** Cursor also exposes `data-integrity-reviewer`. Prefer the **combined** third task to match token budget; split only if the diff is large and you need separation.

### Step 4 — Classify and report

Merge inline findings with delegated results. Deduplicate. Classify:

- **P1 (Critical)**: Must fix before merge — security flaws, data loss risk, broken functionality
- **P2 (Important)**: Should fix before merge — bugs, missing validation, test gaps, logging gaps
- **P3 (Suggestion)**: Nice to have — style, minor simplifications, optional improvements

With `--strict`: promote all P3s to P2.

### Step 5 — Optionally fix

If `--fix` was passed (or user confirms after seeing the report):

1. Implement all P1 and P2 fixes directly
2. Run the relevant test suite (see `prd/00_technology.md` for `{test_all}`)
3. `git add <changed files>` (never `-A`)
4. Commit with message `fix(code-quality): <summary of fixes>`
5. Push to a new branch `fix/code-quality-<slug>`
6. Open a PR against `main`:
   - **Claude Code:** GitHub MCP `create_pull_request` (or equivalent), if configured
   - **Cursor / fallback:** `gh pr create` following the repo workflow

Skip P3 fixes unless `--strict` was passed.

### Step 6 — Capture solutions (optional)

If a P1 finding reveals a non-obvious root cause (e.g. a framework gotcha, a subtle migration ordering constraint), write a brief solution doc to `docs/solutions/` summarizing the root cause and canonical fix. Follow the format of existing docs in that directory.

## Review Report Format

```markdown
## Code Review

**Overall Assessment:** [Ready / Needs Work / Major Issues]

### Summary Table

| Perspective | P1 | P2 | P3 |
|-------------|----|----|-----|
| Code Quality | 0 | 1 | 0 |
| Architecture | 0 | 0 | 0 |
| Performance | 0 | 0 | 1 |
| Security | 1 | 0 | 0 |
| Simplicity | 0 | 1 | 0 |
| Data Integrity | 0 | 1 | 0 |
| **Total** | **1** | **3** | **1** | |

---

### P1 — Critical (must fix before merge)

1. **[Security] Hardcoded API key** (`src/{project}/services/auth.py:45`)
   JWT secret should be loaded from environment variable, not hardcoded.

### P2 — Important (should fix before merge)

1. **[Code Quality] Missing type annotations** (`src/{project}/api/users.py:15`)
2. **[Simplicity] Interface with single implementation** (`src/{project}/repos/base.py:1-20`)
3. **[Data Integrity] Missing length validation** (`src/{project}/models/user.py:12`)

### P3 — Suggestions

1. **[Performance] Consider index** (`src/{project}/db/queries.py:34`)
   Query filters on `created_at` without index. Add if query frequency is high.

---

### Next Steps

1. Fix P1 issues (blocks merge)
2. Address P2 issues
3. Re-run `/lint` and quality checks
4. Request re-review if needed
```
