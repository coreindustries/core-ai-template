---
paths:
  - "**/*.{js,cjs,mjs,jsx,ts,cts,mts,tsx,py,go,rb,java,kt,swift,cs,php}"
---
# Claude API Defaults

Applies when writing code that calls the Claude API. Apply unconditionally.

- **Model**: read the default from `settings.json` / `CLAUDE.md` Agent Routing, via env/config. Never hardcode a model string in application code.
- **Thinking**: `thinking: { type: "adaptive" }` for any non-trivial request. Do NOT use `budget_tokens` (400 on current-generation models).
- **Streaming**: use `.stream()` for long output or high `max_tokens`; `.get_final_message()` / `.finalMessage()` if you only need the result.
- **Prompt caching**: always `cache_control: { type: "ephemeral" }` on the system prompt block; cache the last tool definition if the tools array is large. See `.claude/references/prompt-caching.md`.

```typescript
// Minimum correct API call
const response = await client.messages.create({
  model: config.model,   // read from env / config, not hardcoded
  max_tokens: 8096,
  thinking: { type: "adaptive" },
  system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
  messages,
});
```
