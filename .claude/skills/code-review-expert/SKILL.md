---
name: code-review-expert
description: "Expert code review of current git changes with a senior engineer lens: SOLID, security, performance, error handling, boundary conditions."
---

# /code-review-expert

Expert code review of current git changes with a senior engineer lens. Detects SOLID violations, security risks, performance issues, error handling gaps, boundary condition bugs, and dead code — then proposes actionable improvements.

## Usage

```
/code-review-expert [target] [--commit <range>] [--strict]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `target` | File or directory to review (default: current git changes) |
| `--commit <range>` | Review a specific commit or range (e.g., `HEAD~3..HEAD`) |
| `--strict` | Apply stricter thresholds — flag P2/P3 issues more aggressively |

## Severity Levels

| Level | Name | Description | Action |
|-------|------|-------------|--------|
| **P0** | Critical | Security vulnerability, data loss risk, correctness bug | Must block merge |
| **P1** | High | Logic error, significant SOLID violation, performance regression | Should fix before merge |
| **P2** | Medium | Code smell, maintainability concern, minor SOLID violation | Fix in this PR or create follow-up |
| **P3** | Low | Style, naming, minor suggestion | Optional improvement |

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete the full review end-to-end without pausing
- Present all findings in a single structured report
- Do NOT implement changes until user explicitly confirms

**Thoroughness:**
- Load all reference checklists in parallel before beginning analysis
- Check against all standards in `.claude/rules/` (auto-loaded)
- Cross-reference with `prd/00_technology.md` for technology-specific patterns
- Include file:line references for all findings

### Review Process

#### 1) Preflight context

- Run `git status -sb`, `git diff --stat`, and `git diff` to scope changes.
- If `target` is specified, scope to those files. If `--commit` is specified, use `git diff <range>`.
- Use `rg` or `grep` to find related modules, usages, and contracts.
- Identify entry points, ownership boundaries, and critical paths (auth, payments, data writes, network).

**Edge cases:**
- **No changes**: If diff is empty, inform user and ask if they want to review staged changes or a specific commit range.
- **Large diff (>500 lines)**: Summarize by file first, then review in batches by module/feature area.
- **Mixed concerns**: Group findings by logical feature, not just file order.

#### 2) SOLID + architecture smells

- Load `.claude/references/solid-checklist.md` for specific prompts.
- Evaluate against all 5 SOLID principles:
  - **SRP**: Overloaded modules with unrelated responsibilities.
  - **OCP**: Frequent edits to add behavior instead of extension points.
  - **LSP**: Subclasses that break expectations or require type checks.
  - **ISP**: Wide interfaces with unused methods.
  - **DIP**: High-level logic tied to low-level implementations.
- When proposing a refactor, explain *why* it improves cohesion/coupling and outline a minimal, safe split.
- If refactor is non-trivial, propose an incremental plan instead of a large rewrite.

#### 3) Removal candidates + iteration plan

- Load `.claude/references/removal-plan.md` for template.
- Identify code that is unused, redundant, or feature-flagged off.
- Distinguish **safe delete now** vs **defer with plan**.
- Provide a follow-up plan with concrete steps and checkpoints (tests/metrics).

#### 4) Security and reliability scan

- Load `.claude/references/security-checklist.md` for coverage.
- Also read `.claude/agents/security-reviewer.md` for the security perspective.
- Check for:
  - XSS, injection (SQL/NoSQL/command), SSRF, path traversal
  - AuthZ/AuthN gaps, missing tenancy checks
  - Secret leakage or API keys in logs/env/files
  - Rate limits, unbounded loops, CPU/memory hotspots
  - Unsafe deserialization, weak crypto, insecure defaults
  - **Race conditions**: concurrent access, check-then-act, TOCTOU, missing locks
- Call out both **exploitability** and **impact**.

#### 5) Code quality scan

- Load `.claude/references/code-quality-checklist.md` for coverage.
- Check for:
  - **Error handling**: swallowed exceptions, overly broad catch, missing error handling, async errors
  - **Performance**: N+1 queries, CPU-intensive ops in hot paths, missing cache, unbounded memory
  - **Boundary conditions**: null/undefined handling, empty collections, numeric boundaries, off-by-one
- Flag issues that may cause silent failures or production incidents.

#### 6) Output format

Structure the review as follows:

```markdown
## Code Review Summary

**Files reviewed**: X files, Y lines changed
**Overall assessment**: [APPROVE / REQUEST_CHANGES / COMMENT]

---

## Findings

### P0 — Critical
(none or list)

### P1 — High
1. **[file:line]** Brief title
   - Description of issue
   - Suggested fix

### P2 — Medium
2. (continue numbering across sections)
   - ...

### P3 — Low
...

---

## Removal/Iteration Plan
(if applicable)

## Additional Suggestions
(optional improvements, not blocking)
```

**Inline comments**: Use this format for file-specific findings:
```
::code-comment{file="path/to/file.ts" line="42" severity="P1"}
Description of the issue and suggested fix.
::
```

**Clean review**: If no issues found, explicitly state:
- What was checked
- Any areas not covered (e.g., "Did not verify database migrations")
- Residual risks or recommended follow-up tests

#### 7) Next steps confirmation

After presenting findings, ask user how to proceed:

```markdown
---

## Next Steps

I found X issues (P0: _, P1: _, P2: _, P3: _).

**How would you like to proceed?**

1. **Fix all** — I'll implement all suggested fixes
2. **Fix P0/P1 only** — Address critical and high priority issues
3. **Fix specific items** — Tell me which issues to fix
4. **No changes** — Review complete, no implementation needed

Please choose an option or provide specific instructions.
```

**Important**: Do NOT implement any changes until user explicitly confirms. This is a review-first workflow.

## Resources

| File | Purpose |
|------|---------|
| `.claude/references/solid-checklist.md` | SOLID smell prompts and refactor heuristics |
| `.claude/references/security-checklist.md` | Web/app security and runtime risk checklist |
| `.claude/references/code-quality-checklist.md` | Error handling, performance, boundary conditions |
| `.claude/references/removal-plan.md` | Template for deletion candidates and follow-up plan |

## Example

```
$ /code-review-expert

Scoping changes... 8 files, 342 lines changed

Loading review checklists...

## Code Review Summary

**Files reviewed**: 8 files, 342 lines changed
**Overall assessment**: REQUEST_CHANGES

---

## Findings

### P0 — Critical
(none)

### P1 — High
1. **src/services/payment.ts:89** Race condition in balance deduction
   - Check-then-act pattern: balance is read, checked, then deducted in separate operations
   - Suggested fix: Use `SELECT FOR UPDATE` or atomic `UPDATE WHERE balance >= amount`

2. **src/api/users.ts:34** Missing ownership check (IDOR)
   - Any authenticated user can access other users' data via `GET /users/:id`
   - Suggested fix: Add `where: { id: params.id, orgId: req.user.orgId }`

### P2 — Medium
3. **src/services/order.ts:12-45** SRP violation — mixed concerns
   - Order service handles validation, pricing, inventory, and notifications
   - Suggested fix: Extract `PricingService` and `NotificationService`

4. **src/api/orders.ts:67** Swallowed exception in error handler
   - `catch (e) { return null }` hides failures from callers
   - Suggested fix: Log error with context and throw a typed `OrderError`

### P3 — Low
5. **src/models/user.ts:8** Missing max length on `name` field
   - Could allow unbounded string storage
   - Suggested fix: Add `@MaxLength(255)` constraint

---

## Next Steps

I found 5 issues (P0: 0, P1: 2, P2: 2, P3: 1).

**How would you like to proceed?**

1. **Fix all** — I'll implement all suggested fixes
2. **Fix P0/P1 only** — Address critical and high priority issues
3. **Fix specific items** — Tell me which issues to fix
4. **No changes** — Review complete, no implementation needed
```
