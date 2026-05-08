# Claude Code Statusline

A multi-line statusline for Claude Code showing directory, git branch / worktree, context-window usage, **5-hour and weekly rate-limit usage**, model, output style, **effort level**, session cost, and token burn rate.

```
📁 ~/projects/foo
🌿 branch: main
🧠 context: 87% [========--]
⏱  5h: 24% [==--------]  📅 7d: 41% [====------]
🤖 Opus 4.7  📟 v2.0.18  🎨 default  ⚡ auto  💰 $0.4231 ($14.30/h)  📊 142,533 tok (8,932 tpm)
```

Worktree sessions render the worktree name and branch instead of `branch: …`. The context bar colors by *remaining* (cyan → yellow → red as it drops). The rate-limit bars color by *used* (cyan → yellow → orange → red as usage climbs).

## What's different from upstream cc-statusline

Forked from [`cc-statusline` v1.4.0](https://www.npmjs.com/package/@chongdashu/cc-statusline) with two additions:

1. **Effort level** segment (`⚡ auto`/`high`/`low`/etc.). Reflects the current `/effort` setting and updates live across turns. Reads from `.effort.level`.
2. **Rate-limit bars** for the 5-hour rolling window and 7-day weekly window. Reads from `.rate_limits.five_hour.used_percentage` and `.rate_limits.seven_day.used_percentage`. These fields are populated only for Claude.ai Pro/Max subscribers and only after the first API response in a session — both segments graceful-skip when absent, so API-only users see only the existing lines.

## Install

### 1. Prerequisites

- `bash`
- `jq` (recommended; the script falls back to `grep`/`sed` parsing if absent)
- `bc` or `awk` for cost-per-hour math (most systems have one)

### 2. Drop in the script

Copy `statusline.sh` to `~/.claude/statusline.sh`:

```bash
mkdir -p ~/.claude
cp scripts/statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

### 3. Wire it up in `~/.claude/settings.json`

Add (or merge) this block at the top level:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

### 4. Restart Claude Code

The status line refreshes on each turn — start a new session or send a message to see it.

## Smoke test

```bash
printf '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"effort":{"level":"auto"}}' \
  | bash ~/.claude/statusline.sh
```

Expected output:

```
📁 /tmp
🧠 context: TBD
🤖 Opus 4.7  ⚡ auto
```

## Customizing colors

Each color is a small helper function near the top of the script (e.g. `effort_color`, `cost_color`, `burn_color`). Each emits a 256-color ANSI escape — change the `38;5;NNN` number to any [256-color code](https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit). The `effort_color` defaults to magenta (213).

The rate-limit bars use a single function `limit_color_for_pct` that picks one of four colors based on the *used* percentage (cyan ≤40%, yellow ≤60%, orange ≤80%, red >80%). Adjust the thresholds or colors there if you want a different gradient or breakpoints.

## References

- Claude Code statusline JSON schema: <https://code.claude.com/docs/en/statusline.md>
- Upstream generator: <https://www.npmjs.com/package/@chongdashu/cc-statusline>
