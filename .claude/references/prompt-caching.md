# Prompt Caching — Defaults and Patterns

Reference for Claude API integrations in this project. Load this when implementing or reviewing code that calls the Claude API.

## Default: always cache the system prompt

The system prompt (tools list + instructions + context) is the cheapest thing to cache — it's large, stable, and sent on every turn. Enable caching on it unconditionally.

```typescript
// Python (anthropic SDK)
import anthropic

client = anthropic.Anthropic()

response = client.messages.create(
    model="claude-sonnet-5",
    max_tokens=8096,
    system=[{
        "type": "text",
        "text": SYSTEM_PROMPT,
        "cache_control": {"type": "ephemeral"}   # ← cache the system prompt
    }],
    messages=messages,
)
```

```typescript
// TypeScript
import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic();

const response = await client.messages.create({
  model: "claude-sonnet-5",
  max_tokens: 8096,
  system: [{
    type: "text",
    text: SYSTEM_PROMPT,
    cache_control: { type: "ephemeral" },   // ← cache the system prompt
  }],
  messages,
});
```

## Cache large tool definitions too

If the tools array is large (>1 message worth of tokens), cache the last tool definition:

```typescript
tools: [
  { name: "search", description: "...", input_schema: {...} },
  { name: "read_file", description: "...", input_schema: {...} },
  {
    name: "write_file",
    description: "...",
    input_schema: {...},
    cache_control: { type: "ephemeral" },  // ← last tool in list
  },
]
```

## Multi-turn conversations: cache the oldest user message

In a long conversation, add `cache_control` to the last "stable" point — typically the last user turn before the rolling window:

```typescript
const messages = [
  // old turns (stable — cache up to here)
  { role: "user", content: [{ type: "text", text: old_user_msg, cache_control: { type: "ephemeral" } }] },
  { role: "assistant", content: old_assistant_response },
  // new turns (not cached — they change every request)
  { role: "user", content: new_user_msg },
];
```

## Reading cache usage from the response

```typescript
const response = await client.messages.create({ ... });

// cache_read_input_tokens: tokens served from cache (cheap: ~10% of base)
// cache_creation_input_tokens: tokens written to cache (slightly more than base, one-time cost)
// input_tokens: tokens NOT cached
console.log(response.usage);
// { input_tokens: 12, cache_creation_input_tokens: 2048, cache_read_input_tokens: 0 }
// Next call same system prompt:
// { input_tokens: 12, cache_creation_input_tokens: 0, cache_read_input_tokens: 2048 }
```

## Cache TTL

- **Ephemeral** (`"type": "ephemeral"`): 5-minute TTL, refreshed on each cache hit. This is the only type currently available.
- The cache is per-API-key, per-model, per-exact-prefix — changing even one token in the cached prefix invalidates it.
- Keep the cached prefix identical across calls: no timestamps, no per-request IDs in the system prompt.

## Anti-patterns

| Anti-pattern | Why it breaks caching |
|---|---|
| Timestamp or request ID in system prompt | Invalidates the cache on every call |
| Building the system prompt string dynamically | Order or whitespace changes bust the cache |
| Not sorting tools alphabetically | Tool order changes break the prefix |
| Caching a prefix shorter than ~1024 tokens | Minimum cache size; below this threshold caching is ignored |
| Placing `cache_control` on a middle message | Only the turn at the breakpoint and all content before it are cached |

## When caching saves money

Caching reads cost ~10% of normal input token price. It makes sense whenever:
- System prompt ≥ ~1024 tokens (minimum cacheable unit)
- Same prompt sent ≥ 2 times within the 5-minute TTL window
- Multi-turn agents (every turn re-sends the full conversation history)

A 4096-token system prompt called 100 times per hour: caching saves ~90% of those tokens after the first write per 5-minute window.

## See Also

- [Anthropic prompt caching docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- `.claude/skills/claude-api` — full SDK usage patterns
- `.claude/references/orchestration-patterns.md` — multi-agent patterns that benefit most from caching
