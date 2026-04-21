---
name: wt
description: "Create or manage a git worktree for isolated parallel development — lets multiple agents work in the repo simultaneously without branch collisions."
---

# /wt

Create a git worktree branched from `origin/main` at `../<repo>-<name>/`. Each worktree is a separate working tree on its own branch, so multiple Claude Code sessions (or other agents) can work the repo in parallel without stepping on each other's staging, HEAD, or `node_modules`.

## Usage

```
/wt <name>                 # Create a new worktree for branch <name>
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

```bash
make wt name=<name>
```

This runs:

```bash
REPO=$(basename $(git rev-parse --show-toplevel))
BRANCH=<name>
WORKTREE_PATH="../${REPO}-${BRANCH}"

git fetch origin main
git worktree add "$WORKTREE_PATH" -b "$BRANCH" origin/main
```

Then report to the user:

- Full path to the new worktree
- Branch name
- The command to switch: `cd <path>`
- A reminder that secrets, dependencies, and local DB are **per-worktree** (re-run `make setup` or the subset they need in the new tree — see the runbook below).

If using Claude Code, also tell the user to run these built-in commands manually (skills cannot invoke them):

```
/rename <name>
/color <pick one: red | blue | green | yellow | purple | orange | pink | cyan>
```

A distinct session name + color per worktree prevents cross-session mistakes.

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
- **Don't** forget to clean up. Stale worktrees clutter the filesystem and confuse `git worktree list`.

## See Also

- [`docs/runbooks/multi-agent-worktrees.md`](../../../docs/runbooks/multi-agent-worktrees.md) — coordination patterns for multiple parallel agents
- [Git worktree docs](https://git-scm.com/docs/git-worktree)
