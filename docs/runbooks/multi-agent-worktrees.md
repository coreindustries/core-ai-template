# Runbook: Multi-Agent Parallel Development via Git Worktrees

**Trigger:** You want to run more than one AI coding agent (or more than one human + agent pair) against the same repository simultaneously, each on a separate feature, without them stepping on each other's commits, branches, installed dependencies, or running processes.

**Mechanism:** `git worktree`. Each branch gets its own checkout directory on disk. All worktrees share one `.git/` object store, so switching branches and fetching is fast and disk-cheap, but working files, node_modules, caches, and running servers are isolated per directory.

---

## Quick start

```bash
# From the primary checkout:
make wt name=feat-payments       # creates ../<repo>-feat-payments on branch feat-payments
cd ../<repo>-feat-payments
make install                     # per-worktree dependency install
make db-start                    # local DB stack (see "Port collisions" below)

# When finished (branch merged / abandoned):
make wt-remove name=feat-payments
```

Listing: `make wt-list` (equivalent to `git worktree list`).

## Why one worktree per agent

A single checkout forces every task to share the same working tree. Two agents branching off `main` at 09:00, each making unrelated changes, cannot both run `git checkout` without clobbering each other's in-progress work. Stashing is not a substitute — stashes decouple filesystem state from branch state, which breaks the mental model an agent relies on when reading `git status`.

Worktrees solve this by giving each branch its own directory. An agent's filesystem always matches its branch. `git status` in one worktree is unaffected by work in another.

## Branching rules

- **Always branch from `origin/main`**, never from another feature branch. `make wt` enforces this (`git fetch origin main && git worktree add ... origin/main`). Stacked PRs require an explicit design decision and an ADR.
- **One branch per worktree.** Do not re-use a worktree directory for a new branch — delete it with `make wt-remove` and create a fresh one. Re-using invites "I forgot to run install" class bugs.
- **Worktree directory naming**: `../<repo-name>-<branch-name>`. The Makefile derives this from `git rev-parse --show-toplevel`. Do not customize per-worktree paths — tooling assumes the convention.

## What's shared, what's isolated

| Concern | Shared across worktrees | Isolated per worktree |
|---|---|---|
| Git objects (blobs, commits, refs) | ✅ | |
| Remote config, hooks | ✅ | |
| Branch checkouts | | ✅ |
| Working tree files | | ✅ |
| `node_modules/`, `.venv/`, `target/`, caches | | ✅ |
| Generated types (e.g. `src/types/supabase.ts`) | | ✅ |
| `.env.tpl` (committed) | ✅ (via the branch) | |
| Running processes (dev server, local Supabase) | | ✅ (you start them per worktree) |

**Implication:** every new worktree needs its own `make install` and its own port allocations for any local service that binds a port.

## Port collisions (the main gotcha)

A local Supabase stack binds roughly 10 ports starting at 54321. Running `supabase start` in two worktrees simultaneously will fail the second time with a port-in-use error.

**Options, in order of preference:**

1. **Stop the stack in the worktree you're not actively using:** `cd ../<other-worktree> && supabase stop`. Cheapest.
2. **Use Supabase branching** (for the PR under review, not for long-running dev). Preview branches run as separate cloud projects; no local ports involved. See `.claude/rules/database-migrations.md` Rule 7.
3. **Configure port offsets** in `supabase/config.toml` per worktree. This is last-resort — it means `config.toml` diverges across worktrees, which conflicts with the "one source of truth per branch" model. Document the divergence in an ADR if used.

Other port-binding services to watch for: app dev servers (Next.js 3000, Vite 5173, etc.), Redis, MailHog. Same rule: run one at a time, or offset ports explicitly.

## Secrets

All worktrees share the same `.env.tpl` (it's in git, so it follows the branch). Secrets are injected at runtime by the wrapper — not read from a file on disk — so worktrees don't have per-instance secret state to coordinate. Each shell runs its own:

```bash
aws-vault exec <profile> -- chamber exec <service> -- <command>
```

See `.claude/rules/secrets-hygiene.md`. Never copy a resolved secret into a second worktree's env — always re-run the wrapper.

## Coordinating agents in parallel worktrees

If you're running agents in separate terminals against separate worktrees:

- **Name the terminal / IDE window after the branch.** "What is this window working on?" should be answerable at a glance. In Claude Code: `/rename <branch>` and `/color <random>`.
- **Give each agent a scoped task.** If two agents need to touch the same file, serialize them — have one finish and merge to `main`, rebase the other, then continue.
- **Rebase often.** When another agent's branch merges to `main`, run `git fetch origin main && git rebase origin/main` in every other worktree. Don't let worktrees diverge for days.
- **Commit before switching.** Swapping which worktree you're giving attention to should happen at a commit boundary, not mid-edit.

## Cleanup

Stale worktrees accumulate and consume disk (mostly via per-tree `node_modules`). Two places to check:

```bash
make wt-list
# or:
git worktree list
git worktree prune            # removes references to worktrees whose directories have been deleted out-of-band
```

If a worktree directory was manually deleted, `git worktree prune` cleans the references. Always prefer `make wt-remove` (which also deletes the branch) for graceful cleanup.

## When NOT to use a worktree

- **Quick fix < 5 minutes:** a branch in the main checkout is fine.
- **Exploration with no intent to commit:** use a scratch directory outside the repo.
- **Hotfix on a release branch with uncommitted primary-checkout work:** stash, fix, pop. The overhead of creating a worktree is not worth it for a single-commit hotfix.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `fatal: '<branch>' is already checked out` | You tried to check out a branch already in another worktree | `make wt-list` to find it; either `cd` there or `wt-remove` it |
| `make install` seems to run forever on a fresh worktree | Caches (`.npm`, `.pnpm-store`, `uv` cache) are shared — re-fetching from network shouldn't happen often; if it does, check for lockfile changes | Accept the install time; worktrees trade install time for isolation |
| Supabase won't start in second worktree | Port 54321 already bound by first worktree | `supabase stop` in the first |
| `git worktree list` shows a worktree directory that's been deleted | You deleted the directory manually | `git worktree prune` |
| Changes made in one worktree appear in another | You're not in separate worktrees — check `pwd` and `git worktree list` | Confirm you ran `make wt name=<...>` and `cd`'d into the new directory |

## References

- [Git worktree documentation](https://git-scm.com/docs/git-worktree)
- `.claude/skills/wt/SKILL.md` — agent-facing skill
- `.claude/rules/database-migrations.md` — migration discipline when multiple branches are in flight
- `.claude/rules/secrets-hygiene.md` — why secrets inject per-process, not per-worktree
