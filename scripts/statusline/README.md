# Claude Code Statusline

A multi-line statusline for Claude Code showing directory, git branch / worktree, context-window usage, **5-hour and weekly rate-limit usage**, model, output style, **effort level**, session cost, and token burn rate.

```
📁 ~/projects/foo
🌿 branch: main
🧠 context: 87% [========--]
⏱  5h: 24% [==--------] → 14:30  📅 7d: 41% [====------] → 05/13
🤖 Opus 4.7  📟 v2.0.18  🎨 default  ⚡ auto  💰 $0.4231 ($14.30/h)  📊 142,533 tok (8,932 tpm)
```

Worktree sessions render the worktree name and branch instead of `branch: …`. The context bar colors by *remaining* (cyan → yellow → red as it drops). The rate-limit bars color by *used* (cyan → yellow → orange → red as usage climbs). Reset times after each bar (`→ 14:30` for 5-hour, `→ 05/13` for 7-day) render in light grey from `.rate_limits.*.resets_at`; if the field is absent the time suffix is silently dropped.

## What's different from upstream cc-statusline

Forked from [`cc-statusline` v1.4.0](https://www.npmjs.com/package/@chongdashu/cc-statusline) with two additions:

1. **Effort level** segment (`⚡ auto`/`high`/`low`/etc.). Reflects the current `/effort` setting and updates live across turns. Reads from `.effort.level`.
2. **Rate-limit bars** for the 5-hour rolling window and 7-day weekly window. Reads `used_percentage` and `resets_at` from `.rate_limits.five_hour.*` and `.rate_limits.seven_day.*`. These fields populate only for Claude.ai Pro/Max subscribers and only after the first API response in a session — every segment graceful-skips when absent, so API-only users see only the existing lines. Reset times render in light grey: `→ HH:MM` for the 5-hour window, `→ MM/DD` for the 7-day window.

## Quick install via Claude Code (recommended)

Paste this prompt into a fresh Claude Code session in any repo. The agent will fetch the script, wire it into `~/.claude/settings.json` (preserving other keys), and run the smoke test before reporting done.

```
Set up the multi-line Claude Code statusline from
coreindustries/core-ai-template (effort level + 5h/7d rate-limit
bars + cost + context).

Source files:
- https://raw.githubusercontent.com/coreindustries/core-ai-template/main/scripts/statusline/statusline.sh
- https://raw.githubusercontent.com/coreindustries/core-ai-template/main/scripts/statusline/README.md  (reference)

Steps:

1. If ~/.claude/statusline.sh exists, back it up to
   ~/.claude/statusline.sh.bak before overwriting.

2. Download statusline.sh to ~/.claude/statusline.sh:
     mkdir -p ~/.claude
     curl -fsSL "<RAW URL above>" -o ~/.claude/statusline.sh
     chmod +x ~/.claude/statusline.sh

3. Update ~/.claude/settings.json to add (or merge) this top-level
   block. Preserve every other key. If a different statusLine config
   already exists, show me the diff and ask before replacing.

     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh",
       "padding": 0
     }

   Use jq for the merge: read the existing JSON, set the statusLine
   key, write it back atomically. Do NOT pretty-print in a way that
   reorders other keys unnecessarily.

4. Smoke test:
     printf '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"effort":{"level":"auto"}}' \
       | bash ~/.claude/statusline.sh

   Expected: three lines — directory, "context: TBD", model + effort.

5. Tell me to restart Claude Code (or send a message) so the new
   statusline takes effect on the next turn.

Hard rules:
- Never paste the contents of ~/.claude/settings.json or any other
  settings file into chat.
- Do not modify anything else under ~/.claude/.
- If curl is missing, use wget; if both missing, fall back to
  `gh api repos/coreindustries/core-ai-template/contents/scripts/statusline/statusline.sh -H "Accept: application/vnd.github.raw" > ~/.claude/statusline.sh`.
```

After it finishes, restart Claude Code (or send any message) and the statusline appears on the next turn.

---

## Manual install

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
