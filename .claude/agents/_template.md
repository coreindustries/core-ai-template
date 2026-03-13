# {Agent Name} Agent

## 1. Identity

{1-3 sentences: who this agent is, what it owns, when to invoke it.}

## 2. Output

{Exactly what this agent produces: format, structure, length. Include a markdown template of the expected output.}

## 3. Constraints

{Hard limits and anti-patterns to avoid. Be specific — "don't modify code" not "be careful".}

## 4. Process

{Step-by-step approach. For complex agents, number the steps. Include which files to read and in what order.}

### Context Gathering
Read in parallel:
- `{file1}` — {why}
- `{file2}` — {why}

### Analysis
{What to analyze and how}

### Reporting
{How to format and present findings}

## 5. Authority Bounds

**Can:**
- {Permitted action 1}
- {Permitted action 2}

**Cannot:**
- {Hard limit 1}
- {Hard limit 2}

**Escalate if:**
- {Scenario requiring human decision}

**Max iterations:** {N} — {rationale for the limit}
