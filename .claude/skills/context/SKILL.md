---
name: context
description: "Audit auto-loaded context budget, detect redundancy, and recommend optimizations."
---

# /context

Audit auto-loaded context budget, detect redundancy, and recommend optimizations.

## Usage

```
/context [action] [--verbose]
```

## Arguments

- `action`: `audit`, `redundancy`, `recommendations`, `compare` (default: `audit`)
- `--verbose`: Show per-line token estimates for each file

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Run the full audit pipeline without prompting
- Produce a formatted report, not just raw data
- Prioritize actionable findings over informational noise

**Token Estimation:**
- Use the approximation: **1 token ~ 4 characters** (English prose/code average)
- Read each file, count characters, divide by 4, round to nearest integer
- This is an estimate — actual tokenizer counts vary by ~10%

### Actions

#### Audit (`/context audit`)

Measure all auto-loaded files and report token usage:

1. **Read `CLAUDE.md`** — count characters, estimate tokens
2. **Glob `.claude/rules/*.md`** — read each file, estimate tokens
3. **Check for enabled platform rules** — identify symlinks in `rules/` that point to `rules-available/`
4. **Sum totals** and calculate percentage of 200K context window

**Report format:**
```
Context Budget Report
=====================

Auto-loaded files:
  CLAUDE.md                        1,265 tokens
  rules/ai-agent-patterns.md       1,212 tokens
  rules/code-quality.md              842 tokens
  rules/error-handling.md            534 tokens
  rules/git-workflow.md              687 tokens
  rules/quality-checks.md           612 tokens
  rules/security-core.md          1,705 tokens
  rules/task-management.md           786 tokens
  ─────────────────────────────────────────────
  Total:                           7,643 tokens (3.8% of 200K)

Platform rules (enabled):
  (none active)

Available platform rules (not enabled):
  rules-available/android.md         ~XXX tokens
  rules-available/docker.md          ~XXX tokens
  rules-available/ios.md             ~XXX tokens
  rules-available/nextjs.md          ~XXX tokens
  rules-available/python.md          ~XXX tokens
  rules-available/security-mobile.md ~XXX tokens
  rules-available/security-owasp.md  ~XXX tokens
  rules-available/security-web.md    ~XXX tokens
```

#### Redundancy Scan (`/context redundancy`)

Cross-reference auto-loaded files for duplicated content:

1. **Extract all `{placeholder}` references** from each auto-loaded file
2. **Find placeholders that appear in multiple files** — these are potential redundancies
3. **Scan for repeated guidance** — same concept explained in both CLAUDE.md and a rule file
4. **Check CLAUDE.md against rules** — content in CLAUDE.md that duplicates what a rule already covers

**Report format:**
```
Redundancy Findings
===================

Shared placeholders (appear in 2+ auto-loaded files):
  {lint_fix}        → CLAUDE.md:48, quality-checks.md:45
  {type_check}      → CLAUDE.md:49, quality-checks.md:39
  {test_with_coverage} → CLAUDE.md:50, quality-checks.md:47

Duplicate guidance:
  - CLAUDE.md "Context Recovery" section overlaps with /resume skill
    (low priority — CLAUDE.md version is a brief pointer)

Summary: 3 shared placeholders, 0 high-priority duplicates
```

#### Recommendations (`/context recommendations`)

Produce prioritized optimization suggestions:

1. **Run audit and redundancy scan** (internally)
2. **Categorize findings** by priority:
   - **P1** (high impact): Files > 1,500 tokens that could be split or moved to references
   - **P2** (medium impact): Redundant content that could be consolidated
   - **P3** (low impact): Minor optimizations, formatting improvements

**Report format:**
```
Context Optimization Recommendations
=====================================

P1 - High Impact:
  - security-core.md (1,705 tokens): Consider moving detailed tables
    and checklists to .claude/references/security-checklist.md.
    Auto-loaded portion could be a ~400 token summary with
    "see references/security-checklist.md for details".
    Estimated savings: ~1,200 tokens

P2 - Medium Impact:
  - {lint_fix} placeholder appears in 2 auto-loaded files.
    CLAUDE.md Commands section duplicates quality-checks.md.
    Consider removing command block from one location.
    Estimated savings: ~150 tokens

P3 - Low Impact:
  - quality-checks.md checklist section could move to references.
    Estimated savings: ~80 tokens

Total potential savings: ~1,430 tokens (18.7% of current budget)
```

#### Compare (`/context compare`)

Show the budget impact of enabling/disabling platform rules:

1. **Read all files in `rules-available/`** — estimate tokens for each
2. **Check which are currently enabled** (symlinked into `rules/`)
3. **Show current vs. projected budget** for each combination

**Report format:**
```
Platform Rule Budget Comparison
===============================

Current baseline: 7,643 tokens (3.8% of 200K)

If enabled:
  + python.md             +892 tokens → 8,535 (4.3%)
  + security-owasp.md   +1,105 tokens → 8,748 (4.4%)
  + nextjs.md           +1,340 tokens → 8,983 (4.5%)
  + docker.md             +654 tokens → 8,297 (4.1%)
  + ios.md                +780 tokens → 8,423 (4.2%)
  + android.md            +720 tokens → 8,363 (4.2%)
  + security-web.md       +940 tokens → 8,583 (4.3%)
  + security-mobile.md    +830 tokens → 8,473 (4.2%)

Common combinations:
  make enable-web    (nextjs + security-web + security-owasp)
                     +3,385 tokens → 11,028 (5.5%)
  make enable-python (python + security-owasp)
                     +1,997 tokens → 9,640 (4.8%)
  make enable-mobile (security-mobile + security-web + security-owasp)
                     +2,875 tokens → 10,518 (5.3%)
```

### Implementation Notes

- **File reading**: Use Read tool for each file, count `content.length` characters
- **Token estimation**: `Math.round(charCount / 4)` — acceptable approximation
- **Symlink detection**: Use `ls -la .claude/rules/` via Bash to identify symlinks pointing to `rules-available/`
- **Output**: Always produce the formatted report directly — do not write to a file unless asked
- **No modifications**: This is a read-only diagnostic skill. Never modify files during audit

### Platform Rule Combinations Reference

These mappings come from the Makefile `enable-*` targets:

| Target | Rules Enabled |
|--------|--------------|
| `make enable-web` | nextjs, security-web, security-owasp |
| `make enable-python` | python, security-owasp |
| `make enable-api` | security-owasp |
| `make enable-ios` | ios, security-owasp |
| `make enable-android` | android, security-owasp |
| `make enable-mobile` | security-mobile, security-web, security-owasp |
| `make enable-docker` | docker, security-owasp |

## Example Output

```
$ /context

Context Budget Report
=====================

Auto-loaded files:
  CLAUDE.md                        1,265 tokens
  rules/ai-agent-patterns.md       1,212 tokens
  rules/code-quality.md              842 tokens
  rules/error-handling.md            534 tokens
  rules/git-workflow.md              687 tokens
  rules/quality-checks.md           612 tokens
  rules/security-core.md          1,705 tokens
  rules/task-management.md           786 tokens
  ─────────────────────────────────────────────
  Total:                           7,643 tokens (3.8% of 200K)

Platform rules (enabled):
  (none active)

Redundancy findings:
  3 shared placeholders across auto-loaded files
  0 high-priority content duplicates

Top recommendation:
  P1: Move security-core.md details to references (~1,200 token savings)

Run '/context recommendations' for full optimization plan.
Run '/context compare' to see platform rule budget impact.
```
