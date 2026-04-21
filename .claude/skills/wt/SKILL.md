---
name: wt
description: "Create or manage a git worktree for isolated parallel development — lets multiple agents work in the repo simultaneously without branch collisions."
---

# /wt

Create a git worktree branched from `origin/main` at `../<repo>-<name>/` and enter it — no manual `cd`. Each worktree is a separate working tree on its own branch, so multiple Claude Code sessions (or other agents) can work the repo in parallel without stepping on each other's staging, HEAD, or `node_modules`.

## Usage

```
/wt <name>                 # Create a new worktree and switch the session into it
/wt list                   # List active worktrees
/wt remove <name>          # Remove a worktree and delete its branch (safe: only if merged)
```

## When to Use

- **Parallel agent tasks:** Two agents working different features. Each gets a worktree; neither sees the other's uncommitted changes.
- **Long-running review + new feature:** Reviewing a PR locally without blocking your main branch work.
- **Hotfix during active feature work:** Worktree off `main` for the hotfix; your feature branch stays untouched.
- **Bisecting:** Bisect in a worktree so your main working tree keeps its state.

Prefer `git stash` or a throwaway branch for 30-second tasks — worktrees are overkill for those.

## Create

When invoked as `/wt <name>`:

**Step 1 — create the worktree on disk:**

```bash
make wt name=<name>
```

This runs:

```bash
REPO=$(basename $(git rev-parse --show-toplevel))
BRANCH=<name>
WORKTREE_PATH=$(realpath "../${REPO}-${BRANCH}")

git fetch origin main
git worktree add "$WORKTREE_PATH" -b "$BRANCH" origin/main
```

Compute `WORKTREE_PATH` deterministically as an absolute path — `EnterWorktree` below requires a path that matches `git worktree list` exactly.

**Step 2 — enter the worktree:**

Call `EnterWorktree` with `path: <WORKTREE_PATH>` (the absolute path from step 1). The session's working directory switches into the worktree. No `cd` required.

**Step 3 — personalize (user must run these):**

Pick a random color from: `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`

Tell the user to run:

```
/rename <name>
/color <chosen-color>
```

> `/rename` and `/color` are Claude Code built-in commands — skills cannot invoke them.

A distinct session name + color per worktree prevents cross-session mistakes.

## After Creation

Report:

- Full path to the worktree
- Branch name
- Suggested color
- That the session is now inside the worktree
- A reminder: secrets, dependencies, and local DB are **per-worktree** — run `make install` and (if needed) `make db-start` in the new tree. See the runbook below.

## Exit

When work is done in this worktree, call `ExitWorktree`:

- `action: "keep"` — return the session to the original dir; worktree + branch preserved. Use this **before opening a PR** (you still want the code to exist).
- `action: "remove"` — return to the original dir and delete the worktree + branch. **Does not work for worktrees created via `make wt`** (ExitWorktree only removes worktrees it originally created). For those, use `action: "keep"` followed by `make wt-remove name=<name>`.

If the worktree has uncommitted changes, `ExitWorktree action: "remove"` refuses unless `discard_changes: true`. Confirm with the user before passing that flag.

## List

```bash
make wt-list
```

Shows each worktree's path, branch, and HEAD SHA.

## Remove

```bash
make wt-remove name=<name>
```

Runs:

```bash
git worktree remove "../${REPO}-<name>"
git branch -d <name>   # safe: only deletes merged branches
```

If the branch is not merged, `git branch -d` refuses — either merge it first, PR it, or delete with `-D` manually once you're sure.

## What NOT to do

- **Don't** create a worktree off your current feature branch instead of `origin/main`. You'll tangle two branches' changes.
- **Don't** commit `.env` or secrets in a worktree. The secrets-hygiene rules apply identically; there's no per-worktree exception.
- **Don't** run `supabase db reset` against a shared local Supabase instance from one worktree while another worktree is using it. Local Supabase is a singleton — coordinate, or give each worktree its own port via `supabase/config.toml` per worktree.
- **Don't** call `EnterWorktree` with a relative path or with a path that isn't in `git worktree list` — the tool rejects both. Always compute the absolute path from `make wt`'s output.
- **Don't** forget to clean up. Stale worktrees clutter the filesystem and confuse `git worktree list`.

## See Also

- [`docs/runbooks/multi-agent-worktrees.md`](../../../docs/runbooks/multi-agent-worktrees.md) — coordination patterns for multiple parallel agents
- [Git worktree docs](https://git-scm.com/docs/git-worktree)
