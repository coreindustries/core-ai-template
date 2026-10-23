---
name: prd-audit
description: "Systematically review every PRD against what actually shipped vs what remains, catching PRDs that reached MVP and were then forgotten. Produces a prioritized, dependency-ordered backlog and files it as GitHub issues. Verifies REAL completion against code, PRs and deployed state, never the frontmatter status or an unchecked box. Use periodically, or when deciding what to finish next."
---

# /prd-audit

Sweep the PRD corpus, separate **done** from **remaining** for each PRD, surface the
**MVP'd-then-abandoned** ones, and emit a **prioritized, dependency-ordered backlog**.
Fixes the failure mode where a PRD ships an MVP and its remaining requirements are
silently dropped.

## Usage
```
/prd-audit [--area <subsystem>] [--since <date>]
```

## Core principle

**Claimed status lies.** `status: In Progress`, an unchecked `[ ]`, "FR4-TODO, separate
PR": none tell you what is true. Check the actual artifact: is the requirement's code
in the default branch? is it deployed? does the user-visible outcome work in the real
app? A PRD is only as complete as its verifiable shipped surface.

## Process

### 1. Enumerate and parallelize
List `prd/*.md` (index: `prd/00_index.md`). Treat any existing status record as a
baseline to re-verify, not to trust. Delegate the sweep to subagents in parallel, one
per cluster (area or date range), each returning a structured verdict. Keep verdicts,
not file dumps.

### 2. Per-PRD assessment (each subagent)
Extract each PRD's requirements (FRs / acceptance criteria) and classify each by
checking reality:
- **Shipped:** code in the default branch and, if user-facing, verified in the real
  app. Cite the PR or `file:line`.
- **Remaining:** specced but not merged, or merged but never wired or verified.
- **Superseded:** replaced by a later PRD or approach (name it).

Roll up to a verdict: `Complete`, `MVP-shipped, N requirements remaining` (the
abandoned class), `In progress`, `Not started`, or `Superseded`. Flag every PRD that
reached MVP and then stalled.

### 3. Dependency graph
Note cross-PRD dependencies (X's remaining requirement blocks Y). A remaining item
behind a dependency ranks below one that unblocks others.

### 4. Prioritize and emit
Order remaining work by (a) unblocks-others, (b) release-blocking priority, (c)
effort-to-value. Write it to two places:
- Refresh the PRD status record (`prd/00_index.md`, or a dated audit note beside it).
- File the top items as issues for the feature lane:
  `bash scripts/dev/board/board.sh file-feature --prd <file> --fr <id> --priority P1 --title "..." --body-file <md>`
  (it refuses duplicates). Include a `Depends on` line in each body.

## Output
- Refreshed per-PRD status (verdict, remaining requirements, citations).
- The prioritized backlog with the top N filed as issues.
- A short "abandoned-after-MVP" callout: the PRDs most at risk of being forgotten, and
  the single next step to finish each.

## Agent behavior
- Parallel-delegate the sweep; synthesize here.
- Verify, do not trust: cite the PR or `file:line` that proves a requirement shipped.
- The deliverable is a decision ("the 3 highest-leverage unfinished things and why"),
  not a status dump.
