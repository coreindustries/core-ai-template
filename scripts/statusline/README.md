# Claude Code Statusline

A multi-line statusline for Claude Code showing directory, git branch / worktree, context-window usage, model, output style, **effort level**, session cost, and token burn rate.

```
📁 ~/projects/foo
🌿 branch: main
🧠 context: 87% [========--]
🤖 Opus 4.7  📟 v2.0.18  🎨 default  ⚡ auto  💰 $0.4231 ($14.30/h)  📊 142,533 tok (8,932 tpm)
```

Worktree sessions render the worktree name and branch instead of `branch: …`. Context bar color shifts from cyan → yellow → red as remaining context drops.

## What's different from upstream cc-statusline

Forked from [`cc-statusline` v1.4.0](https://www.npmjs.com/package/@chongdashu/cc-statusline) with one addition: the **effort level** segment (`⚡ auto`/`high`/`low`/etc.). The effort level reflects the current `/effort` setting and updates live across turns. Reads from `.effort.level` in the statusline JSON, with a graceful fallback so models that don't expose the field render cleanly.

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

## References

- Claude Code statusline JSON schema: <https://code.claude.com/docs/en/statusline.md>
- Upstream generator: <https://www.npmjs.com/package/@chongdashu/cc-statusline>
