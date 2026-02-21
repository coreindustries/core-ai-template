# Karpathy Behavioral Principles

**Scope:** Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM pitfalls. Enable this rule as a cautious counterbalance to the default bias-to-action.

**Source:** [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)

**Tradeoff:** These principles bias toward caution over speed. For trivial tasks (simple typo fixes, obvious one-liners), use judgment — not every change needs the full rigor.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

**Example:**
```
User: "Add a feature to export user data"

Before implementing, clarify:
1. Scope: Export all users or filtered subset? (privacy implications)
2. Format: Download file? Background job? API endpoint?
3. Fields: Which user fields? (some might be sensitive)
4. Volume: How many users typically? (affects approach)
```

**Note:** This complements the "Bias to Action" rule in `ai-agent-patterns.md`. Use judgment on when to ask vs. implement — trivial decisions should still default to action, but non-trivial assumptions should be surfaced.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked
- No abstractions for single-use code
- No "flexibility" or "configurability" that wasn't requested
- No error handling for impossible scenarios
- If you write 200 lines and it could be 50, rewrite it

**The test:** Would a senior engineer say this is overcomplicated? If yes, simplify.

**Common over-engineering patterns to avoid:**
- Strategy pattern for a single calculation
- Factory classes where direct construction works
- Plugin systems with no plugins
- Configuration for things that never change
- Generic solutions for specific problems

**Reference:** Load `.claude/references/karpathy-examples.md` for before/after code examples.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting
- Don't refactor things that aren't broken
- Match existing style, even if you'd do it differently
- If you notice unrelated dead code, mention it — don't delete it

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused
- Don't remove pre-existing dead code unless asked

**The test:** Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform imperative tasks into verifiable goals:

| Instead of... | Transform to... |
|--------------|--------------------|
| "Add validation" | "Write tests for invalid inputs, then make them pass" |
| "Fix the bug" | "Write a test that reproduces it, then make it pass" |
| "Refactor X" | "Ensure tests pass before and after" |

For multi-step tasks, state a brief plan with verification:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria enable independent looping. Weak criteria ("make it work") require constant clarification.

## Working Indicators

These principles are working if you see:
- Fewer unnecessary changes in diffs — only requested changes appear
- Fewer rewrites due to overcomplication — code is simple the first time
- Clarifying questions come before implementation — not after mistakes
- Clean, minimal PRs — no drive-by refactoring or "improvements"
