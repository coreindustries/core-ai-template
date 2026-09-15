# Model-Specific Prompting Guides

Reference for model-specific behavioral differences and prompt adjustments when building with Claude. Load this file when debugging unexpected model behavior or tuning prompts for a new model.

For techniques that apply to all current models (XML structuring, few-shot examples, long context, thinking configuration, tool use, agentic patterns), see the [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices).

---

## Claude Opus 5 (`claude-opus-5`)

### Response length and verbosity

Opus 5 defaults to longer responses than prior models. Raising or lowering `effort` does **not** reliably shorten them. Prompt explicitly:

```text
Keep responses concise. Skip preamble. Jump directly to the answer.
Omit summaries of what you just did — I can read the output.
```

### User-facing progress updates in agentic work

Opus 5 narrates its work more than prior Opus models, which is useful in interactive sessions but can add noise in automated pipelines. If you want fewer status lines, tell it directly:

```text
Don't narrate each step. Only write to the user when you need input
or when the task is complete.
```

### Written deliverable length

Long-form documents (reports, specs, analysis) default to thorough rather than concise. If you want a bounded output, specify it:

```text
Write this as a ≤500-word summary. No section headers.
```

### Task scope and over-verification

Opus 5 verifies its own work well without prompting — verification instructions carried over from prompts written for earlier models can cause over-verification, adding tokens and latency. When migrating to Opus 5, **remove** explicit "check your work" / "verify before submitting" instructions rather than rewriting them.

### Controlling subagent spawning

Opus 5 delegates to subagents more readily than prior models. If subagents are triggering on tasks that don't warrant them (single-file edits, simple grep queries), add a damping prompt:

```text
Work directly unless the task requires true parallelism or isolated
context. Don't spawn a subagent for file reads, grep, or any task
you can do in one sequential pass.
```

### Running with thinking disabled

On Opus 5, thinking is on by default. You can disable it only at `effort: "high"` or lower. When thinking is disabled, the model can occasionally emit internal XML tags into its visible output. To suppress this:

```text
Never emit XML tags in your response unless the output format
explicitly requires them.
```

---

## Claude Fable 5.1 (`claude-fable-5-1`)

### Effort levels — run the full sweep

`high` is the default. Run evals at all five levels (`low`, `medium`, `high`, `xhigh`, `max`) — capability gains are largest at higher settings, but at `medium` results roughly match Claude Fable 5 at lower cost. At `low`, Fable 5.1 is often competitive with Opus/Sonnet on cost per task while scoring higher.

```typescript
await client.messages.create({
  model: "claude-fable-5-1",
  max_tokens: 16000,
  thinking: { type: "adaptive" },
  output_config: { effort: "high" },   // low | medium | high | xhigh | max
  messages,
});
```

### Thinking is always on

Fable 5.1 thinking cannot be disabled. `thinking: { type: "adaptive" }` is the correct configuration. Setting `budget_tokens` returns a 400 error on this model.

### User-facing progress updates

Fable 5.1 defaults to fewer visible updates between tool calls than Fable 5, especially at high effort and in long tool chains. Two steps:

1. **Enable progress-update thinking blocks**: Set `thinking.display: "updates"` (beta header `thinking-display-updates-2026-08-18`) to receive non-empty thinking blocks as status lines, or `"summarized"` for summarized reasoning.

2. **Remove suppression instructions**: Check the system prompt for lines like "hold all findings for the final response" — remove them before adding anything.

If you still need more updates (pair-programming, human-in-the-loop):

```text
Before you start, say in a line what you're about to do; brief updates
while you work help the user follow along. Close with a short recap that
stands on its own — what you found, what you did, and what's next.
```

If your product hides tool output, tell the model with a turn-scoped system message (cleared on next user turn):

```text
Only you see that command's output — the user's terminal shows at most
a few lines of it. If the user needs to read any of it, put it in your reply.
```

### Batch independent tool calls in agent loops

In coding and computer-use loops, Fable 5.1 may issue one tool call per turn instead of batching. Add this nudge after each round of tool results as a turn-scoped system message:

```text
First privately list what you need next; then request every item
that doesn't depend on another's result in this one response.
```

Use `role: "system"` with `clear_at: "next_user_message"` (beta header `mid-conversation-system-clear-at-2026-08-21`). Append a fresh copy each turn; leave prior copies in place (the API clears them automatically, they cost no input tokens after clearing, and rewriting them would bust the prompt cache and invalidate thinking blocks).

### Keep conversation history append-only

Editing earlier turns between requests breaks Fable 5.1's thinking blocks and restarts prompt cache from that point. Requests that edit earlier turns can fail with `bound to a different conversation`. Rules:

- Append each assistant turn exactly as returned, thinking blocks included.
- Never rewrite, summarize, or truncate earlier messages in place.
- Move context hydration and system-prompt reminders to turn-scoped system messages (mid-conversation, not editing the original).
- Use server-side context compaction (`compaction`) rather than client-side rewriting.

### Writing density

Fable 5.1 prose runs denser than earlier models — long paragraphs with high information per sentence. If you need more readable output:

```text
Use shorter paragraphs. One idea per paragraph.
```

### Formatting in chat

Fable 5.1 already formats less than earlier models. Do **not** apply a heavy anti-markdown block (common for Opus 4.x) — it suppresses structure the content genuinely needs. If any formatting adjustment is needed, use a shorter rule:

```text
Use prose paragraphs and code blocks. Reserve bullet lists for
truly discrete items. Avoid excessive bold and headers.
```

### Search triggering at low effort

At `low` effort, Fable 5.1 calls search and retrieval tools less often and may answer from training instead. When accuracy matters at low effort, instruct explicitly:

```text
Always search before answering questions about current state,
recent events, or facts that change over time.
```

### Safeguard false positives

Fable 5.1 runs safety classifiers that can return `stop_reason: "refusal"` on benign coding requests. If you see unexpected refusals on legitimate tasks, add context to the system prompt that clarifies the authorized use case:

```text
This is an internal security tooling project. Code examples involving
authentication, tokens, and cryptography are expected and authorized.
```

### Prefer targeted edits over whole-file rewrites

Fable 5.1 may rewrite entire files for small changes. To get surgical edits:

```text
Make targeted edits only. Return the minimal diff, not the whole file,
unless the task explicitly requires a full rewrite.
```

### Leave room for long outputs at xhigh and max effort

At `xhigh` and `max`, Fable 5.1 may think for longer before writing a long deliverable. If `max_tokens` is tight, the thinking can consume the budget before the output starts. Set `max_tokens` generously (32K–100K+) for long-output tasks at high effort.

### Let the lead agent keep working while subagents run

The lead agent may idle while waiting for subagent results. To keep it productive:

```text
While subagents are running, continue with other parts of the task
that don't depend on their results.
```

### Give vision work tools to crop and zoom

Answers about charts and dense images miss detail at native resolution. Provide a crop/zoom tool so the model can zoom into relevant regions before answering:

```text
When analyzing an image, use the crop tool to zoom into areas of
interest before describing or extracting data from them.
```

---

## API breaking changes (Fable 5.1 + 5)

| Area | Old pattern | New pattern |
|---|---|---|
| Thinking | `thinking: { type: "enabled", budget_tokens: N }` | `thinking: { type: "adaptive" }` — `budget_tokens` returns 400 on Fable 5/5.1 and Sonnet 5/Opus 5 |
| Thinking on/off | `thinking` parameter optional — off when omitted | Always on (Fable 5/5.1); on by default (Opus 5, Sonnet 5) |
| Forced tool use | `tool_choice: { type: "tool", name: "X" }` | Same, but returns an error on Fable 5.1 if the tool name doesn't exist |
| Editing turns | Allowed on older models | Editing earlier turns or `system` between requests invalidates thinking blocks on Fable 5.1 — use `mid-conversation-system-clear-at` instead |
| Prefilled assistant turns | Supported through Opus 4.6 | Not supported on Fable 5/5.1, Sonnet 5, or Mythos Preview — returns 400 |

---

## Effort levels at a glance

| Level | Use when |
|---|---|
| `low` | Simple lookups, retrieval, classification. Fastest and cheapest; search triggers less often. |
| `medium` | Standard tasks. Roughly matches Fable 5 quality at lower cost. |
| `high` | Default. Most tasks. |
| `xhigh` | Complex reasoning, long documents. Budget extra `max_tokens`. |
| `max` | Hardest tasks, evals, long-horizon coding. |

Effort controls thinking depth, not output length. Output length is controlled by `max_tokens` and explicit prompts.

---

## Prompt caching with Fable 5.1

Cache reads on Fable 5.1 cost **2.5%** of the base input price (vs. ~10% for other models) — the largest cache discount of any current model. Cache the system prompt unconditionally:

```typescript
system: [{
  type: "text",
  text: SYSTEM_PROMPT,
  cache_control: { type: "ephemeral" },
}]
```

Invalidation rules are the same as all models: per-API-key, per-model, per-exact-prefix. The append-only history rule (above) matters here — editing earlier turns restarts the cache from that point, eliminating the discount.

See `.claude/references/prompt-caching.md` for patterns and anti-patterns.

---

## See Also

- [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) — general techniques (XML, examples, thinking, tool use, agentic)
- [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) — full model-specific guide
- [Prompting Claude Fable 5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1) — full model-specific guide
- [What's new in Claude Fable 5.1](https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1) — API changes, pricing, refusals, billing
- `.claude/references/prompt-caching.md` — caching patterns and anti-patterns
- `.claude/rules/ai-agent-patterns.md` — API defaults (adaptive thinking, streaming, caching defaults)
