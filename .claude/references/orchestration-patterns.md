# Multi-Agent Orchestration Patterns

Reference document for how agents work together. Loaded on-demand by skills that coordinate multiple agents.

## Pattern 1: Manager (Hub-and-Spoke)

One primary agent coordinates and calls specialists as tools.

**Best for:** `/feature` lifecycle, complex debugging, multi-phase workflows
**Example:** feature-agent → codebase-researcher → architect → test-writer → security-reviewer

**How it works:**
1. Manager agent receives the full task
2. Manager determines which specialists to invoke and in what order
3. Each specialist produces a structured report
4. Manager synthesizes findings and proceeds to next phase

**When to use:** Task requires sequential phases where later phases depend on earlier findings.

## Pattern 2: Parallel Review

Multiple agents run concurrently on the same input, results merged.

**Best for:** `/review` (already uses this), `/scan`, code quality assessment
**Example:** security-reviewer + perf-auditor + simplicity-reviewer + data-integrity-reviewer → merge → deduplicate → rank by severity

**How it works:**
1. Input (files to review) is sent to all relevant agents simultaneously
2. Each agent produces findings in a standardized severity format (P1/P2/P3)
3. Results are merged, duplicates removed, and presented as a unified report

**When to use:** Multiple independent perspectives needed on the same code.

## Pattern 3: Sequential Pipeline

Agents hand off to each other in a defined order, each building on the previous output.

**Best for:** Feature development, refactoring workflows
**Example:** codebase-researcher → architect → (implement) → test-writer → codex-style-agent

**How it works:**
1. Each agent produces a structured handoff document
2. Next agent reads the handoff and builds on it
3. Pipeline stops if any agent raises a blocking concern

**When to use:** Each step requires context from the previous step.

## Handoff Protocol

When agents hand off to each other, the producing agent should output:

```yaml
handoff:
  from: {agent-name}
  status: complete | blocked | needs-review
  summary: {1-2 sentence summary of findings}
  key_findings:
    - {finding 1}
    - {finding 2}
  files_examined:
    - {file1}
    - {file2}
  next_agent_should: {specific instruction for the next agent}
  blockers: [] # or list of blocking issues
```

## When to Escalate to Human

- Any P1/Critical finding with security or data loss risk
- Conflicting recommendations from 2+ specialist agents
- Agent has run >5 iterations without convergence
- Task requires access to external systems or credentials
- Decision has significant cost, compliance, or user-facing impact
