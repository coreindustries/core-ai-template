# /compound

Capture knowledge from solved problems to prevent re-discovery. Creates searchable solution documents after non-trivial debugging, fixes, or investigations.

## Usage

```
/compound [--category <category>] [--from-commit <hash>]
```

## Arguments

- `--category`: Override auto-detected category (see categories below)
- `--from-commit`: Extract context from a specific commit instead of current state

## Categories

| Category | When to Use |
|----------|-------------|
| `build-errors` | Build/compile failures, dependency resolution |
| `test-failures` | Test failures, flaky tests, fixture issues |
| `runtime-errors` | Crashes, unhandled exceptions, unexpected behavior |
| `performance` | Slow queries, memory leaks, optimization wins |
| `database` | Migration issues, schema problems, query optimization |
| `security` | Vulnerability fixes, auth issues, data exposure |
| `integration` | API issues, third-party service problems, webhook failures |
| `deployment` | CI/CD failures, environment issues, infrastructure |
| `logic-errors` | Incorrect business logic, edge cases, race conditions |

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Gather all context from the current session without prompting
- Infer category from the problem type
- Generate the solution document end-to-end

**Quality:**
- Be specific — include exact error messages, file paths, and code snippets
- Focus on what future developers need to solve this problem fast
- Keep it concise — aim for a document that takes < 2 minutes to read

### Process

#### 1. Gather Problem Context

Collect from the current session or recent git history:

- **Problem**: What went wrong? (exact error message or symptom)
- **Root Cause**: Why did it happen?
- **Failed Attempts**: What didn't work and why (saves future time)
- **Working Solution**: What fixed it, with code snippets
- **Files Changed**: Which files were modified
- **Prevention**: How to avoid this in the future

If `--from-commit` is specified:
```bash
git show {hash} --stat
git log {hash} -1 --format="%B"
git diff {hash}^..{hash}
```

#### 2. Check for Duplicates

```bash
# Search existing solutions for similar problems
ls docs/solutions/
grep -r "{key_error_term}" docs/solutions/ || true
```

If a similar solution exists:
- Update the existing file instead of creating a duplicate
- Add a "See Also" reference if it's related but distinct

#### 3. Create Solution Document

**Directory structure:**
```
docs/solutions/{category}/{YYYY-MM-DD}-{slug}.md
```

**Template:**

```markdown
---
title: "{Descriptive title of the problem and fix}"
category: "{category}"
date: "{YYYY-MM-DD}"
tags: ["{tag1}", "{tag2}", "{tag3}"]
stack: ["{language}", "{framework}", "{tool}"]
severity: "{critical|high|medium|low}"
time_to_resolve: "{approximate time spent}"
---

# {Title}

## Problem

{What went wrong — include exact error message or symptom}

```
{exact error output or stack trace snippet}
```

## Root Cause

{Why it happened — be specific about the mechanism}

## Failed Attempts

{What was tried and why it didn't work — this saves the most future time}

1. **{Attempt 1}**: {Why it didn't work}
2. **{Attempt 2}**: {Why it didn't work}

## Solution

{What fixed it — include exact code changes}

```{language}
// Before
{old code}

// After
{new code}
```

## Files Changed

- `{file_path}` — {what changed}

## Prevention

{How to avoid this in the future — config changes, linting rules, tests}

## See Also

- {Links to related solutions, docs, or issues}
```

#### 4. Create Directory if Needed

```bash
mkdir -p docs/solutions/{category}
```

#### 5. Confirm with User

Present a summary:
```
Solution captured: docs/solutions/{category}/{date}-{slug}.md

Category: {category}
Tags: {tags}
Severity: {severity}

Summary: {one-line description}
```

## Example

```
$ /compound

Analyzing recent debug session...

Solution captured: docs/solutions/database/2025-01-15-prisma-enum-migration-failure.md

Category: database
Tags: prisma, migration, enum, postgresql
Severity: medium

Summary: Prisma enum migrations fail on PostgreSQL when adding values to
existing enums. Fix: use raw SQL migration with IF NOT EXISTS guard.
```

## When to Use This Skill

Use `/compound` after:
- Fixing a bug that took > 15 minutes to diagnose
- Discovering a non-obvious workaround
- Solving a problem that required reading external docs
- Debugging a CI/CD or deployment failure
- Any fix where you thought "I wish I'd known this earlier"

**Don't use for:**
- Trivial typo fixes
- Standard CRUD operations
- Well-documented framework features
