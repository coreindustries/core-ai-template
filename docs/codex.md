# Codex runtime guide

This is the Codex-specific companion to `CLAUDE.md` and `.claude/rules/`. Those remain the
source of truth for standards (code quality, testing, security, git workflow); this file
translates the parts of the workflow that are expressed as Claude Code tool calls — skills,
subagents, worktrees, hooks — into what Codex actually has. Read it once at the start of a
Codex session, then load only the specific rules and skills a task needs.

**Ownership stays with the shared docs.** This file adds a runtime adapter; it does not fork
policy. If a rule in `.claude/rules/` conflicts with something here, the rule wins — fix this
file instead of ignoring the rule.

## 1. Invoking skills

Codex discovers Agent Skills by walking from the current directory up to the repo root looking
for a `.agents/skills/` folder, plus `~/.agents/skills` and `/etc/codex/skills`
([developers.openai.com/codex/skills](https://developers.openai.com/codex/skills)). It reads
each subdirectory's `SKILL.md` frontmatter (`name` + `description` only — no other key is
required) and **follows symlinked skill folders**. It does **not** read `.claude/skills`
directly.

This repo keeps one source of truth: `.agents/skills` is a **symlink** to `.claude/skills`
(`ln -s ../.claude/skills .agents/skills`, committed as a symlink). Every skill Claude Code
can run, Codex can run from the identical file — there is no second copy to drift.
`scripts/check-codex-skills.sh` (wired into CI's Lint job) fails the build if the symlink goes
missing, is re-pointed, or a `SKILL.md` loses its `name`/`description` fields.

`.claude/skills/_shared/agent-protocol.md` has no `SKILL.md` on purpose — it is a shared
document the lane skills' bodies point to, not a skill of its own. Codex's loader simply will
not surface it as an invocable skill, which is correct and is not flagged by the check script.

**Invoke a skill** with `/skills` to list them, `$skill-name` to run one directly (e.g.
`$feature-agent`), or let Codex select one implicitly from its description when a prompt matches
what the skill says it's for. A `SKILL.md` body written for Claude Code (e.g. `/feature`
markdown headers, examples using `Read`/`Edit`/`Bash`) still reads fine — treat the *tool names
inside the body* as illustrative, and use Codex's own tool schema to actually do the work (see
§2's translation table).

## 2. Claude tool names → Codex equivalents

Skills and `.claude/skills/_shared/agent-protocol.md` are written for Claude Code's tool
vocabulary. None of the names below are valid Codex tool calls — use the Codex column, or do the
underlying thing a different way when there's no direct equivalent.

| Claude Code | Codex equivalent | Notes |
|---|---|---|
| `Agent` (with `subagent_type` + `model`) | `spawn_agent` (`task_name`, `message`) | Codex has no registered agent *types* — a `task_name` is a label, not a loader. Name the shared role file explicitly in the brief (see §3). |
| `model: "haiku"` / `"sonnet"` / `"opus"` / `"inherit"` | inherit the current Codex model by default | Claude aliases are not Codex model IDs. Set `model`/`reasoning_effort` on `spawn_agent` only when the user or an applicable rule explicitly authorizes an override, and only to a model ID Codex currently exposes. |
| `isolation: "worktree"` | none — create it yourself | Codex does not auto-create worktrees for children. The **parent** runs `git worktree add`, then passes the absolute path in the child's brief. Children share the checkout by default; only a writer gets its own worktree. |
| `EnterWorktree` / `ExitWorktree` | none | No session-level worktree switch exists. A Codex session's cwd is fixed for its lifetime; work in a different worktree by giving that absolute path to a `spawn_agent` child, not by moving the parent session. |
| `Monitor` | `wait_agent` (blocking wait for a child) + the shell tool's session id/continuation mechanism for a long-running command | There is no standing "notify me when this changes" primitive — poll `wait_agent` or re-issue the shell continuation call. |
| `ScheduleWakeup` / `run_in_background: true` (Bash) | the shell tool's background/continuation mechanism | Use the session id the shell tool returns and its documented continuation call; do not restart a command because it yielded control. There is no scheduled-future-wakeup primitive — the parent must actively re-check. |
| `SendMessage` | `send_message` (to a running child) / `followup_task` (to an idle child) | Only reaches a **live local** child in the same session tree. For durable, cross-session coordination (lane agents, hand-offs), use GitHub issue/PR comments via `scripts/dev/board/board.sh` — the same channel Claude Code lane agents use, already runtime-neutral. |
| `TaskCreate` | none — use `scripts/dev/board/board.sh` (GitHub Issues) or `prd/tasks/*.md` | There is no built-in shared task-list UI in Codex. The lane protocol already treats GitHub Issues as the only source of truth, so nothing changes here between runtimes. |
| `AskUserQuestion` | ask in plain response text and keep working on what doesn't depend on the answer | No structured question/choice UI. Carry the task through (`.claude/rules/ai-agent-patterns.md` → Bias to Action): resolve routine reversible choices yourself, ask a focused question only when a missing answer changes the outcome, and don't block unrelated progress on it. |
| `Skill` (tool call) | `/skills`, `$skill-name`, or implicit selection | See §1. |

`list_agents` before fan-out: Codex's observed concurrency is **4 active agent slots including
the parent**, so at most 3 children run at once. Reserve a slot for the parent; batch work if
capacity is already used.

## 3. Architect → planner → workers → judge

The design-chain roles in `.claude/agents/architect.md`, `planner.md` and `judge.md` are **prompt
contracts, not registered Codex agents.** Codex does not read `.claude/agents/*.md` frontmatter
(`model:`, `tools:`) the way Claude Code does — `spawn_agent` takes a task name and a message, not
an `agent_type` that auto-loads a file and its model pin. Every brief below explicitly names the
file to read and tells the child to ignore the Claude-only frontmatter (`name`/`model`/`tools`)
and follow only the body.

Run the phases **in this order**; skip `architect`/`planner` when they don't apply (single-file
change, shape already agreed), but **never skip `judge`** — CLAUDE.md's Agent Routing has no size
exemption for it. Workers may run concurrently only within their own phase; the judge must not
share a phase with active writers.

### 3.1 Architect — "what should exist?"

Invoke before planning a feature that adds a module, a dependency, or a schema change.

```text
spawn_agent({
  task_name: "architect",
  fork_turns: "none",
  message: "Read docs/codex.md and .claude/agents/architect.md. Ignore the Claude-only
    YAML frontmatter (name/model/tools) at the top of architect.md — follow only the body.
    Worktree: <absolute-path>. Read-only — do not edit, stage, commit, push, open a PR, or
    deploy. Required outcome: <the observable requirement>. Return the smallest complete
    design, the reuse rung it landed on (config -> existing dependency -> composing
    first-party modules -> new code), what it lets us delete, and the evidence for each."
})
```

### 3.2 Planner — "in what order?"

Invoke after the shape is agreed, for anything touching more than two modules, a schema change,
or non-obvious sequencing.

```text
spawn_agent({
  task_name: "planner",
  fork_turns: "none",
  message: "Read docs/codex.md and .claude/agents/planner.md. Ignore the Claude-only YAML
    frontmatter — follow only the body. Worktree: <absolute-path>. Read-only — do not edit,
    stage, commit, push, open a PR, or deploy. Agreed design: <design + acceptance criteria
    from the architect phase, or from the user if architect was skipped>. Return an ordered,
    file-level implementation plan with file:line evidence, a test plan, and risks/gotchas."
})
```

### 3.3 Workers — implementation

Not a shared role file — a parent-composed brief per §2's delegation contract (also
`.claude/rules/ai-agent-patterns.md` → "Delegating to Subagents" and
`.claude/skills/_shared/agent-protocol.md` §6). Every worker brief states: the goal and the
invariant; the files it **owns** (exclusive) vs. may only read; its absolute worktree path;
"no git — the parent commits"; "mutation-check every fix"; and "report in ≤400 words with
`file:line`, no file dumps." Give every **concurrent writer** its own `git worktree`, created by
the parent, with disjoint file ownership — Codex children share the checkout by default and have
no automatic isolation.

### 3.4 Judge — "what does it break?" (every change, no exemption)

Invoke on **every** change before its PR leaves draft (or before the final commit when there is
no PR), and again after fixing P1/P2 findings. A fresh, separate child — never reuse a worker's
context, and never run it in the same phase as an active writer.

```text
spawn_agent({
  task_name: "judge",
  fork_turns: "none",
  message: "Read docs/codex.md and .claude/agents/judge.md. Ignore the Claude-only YAML
    frontmatter — follow only the body. Worktree: <absolute-path>. Read-only adversarial ship
    gate — do not edit, stage, commit, push, open a PR, or deploy. Discover the COMPLETE change
    scope yourself using the commands in docs/codex.md section 3.4 (do not rely on judge.md's
    own 'git diff main...HEAD' hint — it misses untracked files and this repo's default branch
    may not be main). Read every untracked file in full before writing the verdict. Return
    SHIP / SHIP WITH FIXES / HOLD, P1/P2/P3 findings with file:line citations, what you
    attacked, and commands run."
})
```

**Diff discovery the judge must run**, from the named worktree (this supersedes any shorthand
in `judge.md`'s own "Inputs" section, which assumes a Claude Code session that already has the
diff in context):

```sh
# Resolve the base branch: the remote's default, else a local main/master.
BASE="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" \
  || BASE="$(git rev-parse -q --verify main >/dev/null && echo main || echo master)"
git status --porcelain
git diff "$(git merge-base HEAD "$BASE")"
git diff --cached
git ls-files --others --exclude-standard
```

With no remote at all (a fresh copy of the template), `BASE` falls back to the local `main`
(or `master`). If `HEAD` *is* that branch, there is no branch diff: review the working-tree and
staged changes plus the commits you were asked about (`git log -p <from>..HEAD`), and say which
range you reviewed.

`git ls-files --others --exclude-standard` prints **paths only** — it does not show untracked
file contents. The judge must `Read` (or `cat`) every path it lists before issuing a verdict; an
untracked file the judge never opened is exactly the kind of gap this step exists to close.

If any discovery command fails, the verdict is `HOLD — cannot verify scope`. If every discovery
output is empty, the verdict is `HOLD — nothing to review`.

**Codex has no enforced read-only child mode.** A `spawn_agent` child that was told "read-only"
can still write, and a post-phase status check alone is not proof it didn't (it could touch a
file that was already dirty without changing its status). For anything you're trusting a
read-only verdict on, fingerprint the worktree before and after:

```sh
git rev-parse HEAD            # a commit on a clean tree changes nothing else below
git for-each-ref              # new or moved branches/tags
git stash list                # a stash hides edits from every other line
git status --porcelain
git diff --binary
git diff --cached --binary
git ls-files --others --exclude-standard | while read -r f; do
  git hash-object --no-filters -- "$f"; printf ' %s\n' "$f"
done
```

A byte-identical fingerprint before and after is required to trust the child's read-only claim.
Any delta is a write and invalidates the verdict until you inspect it.

## 4. Worktree rules for concurrent writers

Same invariant as Claude Code, different mechanics for getting there:

- Codex children **share the parent's checkout by default.** There is no `isolation: "worktree"`
  flag and no `EnterWorktree`/`ExitWorktree` session switch.
- Every **concurrent writer** needs its own `git worktree`, created by the **parent** with
  `git worktree add <path> <branch>` (under the directory named by `worktreeDir` in
  `.claude/agent-lanes.json`; isolation rules in `.claude/rules/ai-agent-patterns.md`), plus
  **exclusive ownership of its declared files.** Two children must never be told to edit the same
  file, lockfile, or generated artifact.
- Pass the **absolute worktree path** in every writer's brief and tell it to confirm location
  first (`pwd && git rev-parse --show-toplevel`) before touching anything.
- Read-only children (architect, planner, judge, lookups) do not need a worktree merely because
  they run concurrently with something else — only a writer does.
- **The parent commits.** Workers and read-only children never stage, commit, push, open PRs, or
  merge; that stays in the parent session per `.claude/skills/_shared/agent-protocol.md` §6.
  Stage explicit paths (`git -C <worktree> add <path>`), never `add -A`.
- Never run overlapping build/tag/push pipelines against the same checkout or Docker namespace.
  Serialize per SHA; isolated builds and tests may run concurrently.

## 5. Starting a lane in Codex

The four standing lanes (`release-manager`, `feature-agent`, `bugfix-agent`, `prd-manager`) are
skills, not a separate Codex concept — `.claude/skills/_shared/agent-protocol.md` is the shared
protocol every one of them loads. Its coordination (GitHub Issues, `board.sh`, PR babysitting) is
runtime-neutral; its §6 delegation table uses Claude vocabulary (`isolation: "worktree"`,
`general-purpose`, pinned models), which you translate with §2 above. To start one in Codex:

| Say | Loads | Becomes |
|---|---|---|
| `You are the Release Manager` | `$release-manager` + `.claude/skills/_shared/agent-protocol.md` | `<P>-RELEASE` |
| `You are the Feature manager` / `You are feature agent 2` | `$feature-agent` + agent-protocol.md | `<P>-FEATURE-<id>` |
| `You handle bug fixes` / `You are bugfix agent 3` | `$bugfix-agent` + agent-protocol.md | `<P>-BUGFIX-<id>` |
| `You are the PRD manager` | `$prd-manager` + agent-protocol.md | `<P>-PRD` |

In Claude Code the `agent-role.sh` `UserPromptSubmit` hook recognizes these phrases automatically
and records the role for `agent-compact.sh` to re-inject after compaction. In Codex, **the
explicit `$skill-name` invocation above is the primary mechanism** — do it even if the hook (§6)
is also wired and trusted, because:

1. Codex hooks are inert until the user runs `/hooks` once per hook definition to trust it, and
2. there is no verified Codex equivalent of `agent-compact.sh`'s automatic role re-injection after
   compaction/resume — a public issue (openai/codex#45999) reports `SessionStart` hook
   `additionalContext` currently being rejected. **After any compaction or resume, manually
   re-invoke `$<lane-skill>` and re-read `.claude/skills/_shared/agent-protocol.md`** rather than
   assuming the role carried over silently.

Everything after role assignment — claiming work, `board.sh` state transitions, saving progress,
PR babysitting, communication — is identical to the Claude Code lane workflow, because
`scripts/dev/board/board.sh` is shell + `gh` with no Claude-specific tool calls. Only the
delegation steps need the §2 translation.

## 6. UserPromptSubmit hook (lane role detection)

`.codex/hooks.json` wires the same lane-detection logic Claude Code uses:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "root=\"$(git rev-parse --show-toplevel 2>/dev/null)\" || exit 0; exec \"$root/.claude/hooks/agent-role-codex.sh\"",
            "timeout": 5,
            "statusMessage": "Checking prompt for a lane-agent role assignment"
          }
        ]
      }
    ]
  }
}
```

Outside a git repository the command exits 0 without running anything, so it never blocks or
errors a Codex turn. `.claude/hooks/agent-role-codex.sh` is a thin adapter: it sets `AGENT_HOOK_RUNTIME=codex` (reserved: nothing reads it yet) and
execs the **same** `.claude/hooks/agent-role.sh` Claude Code runs — one source of truth for the
role-matching regexes, not a fork. `.claude/settings.json`'s Claude wiring is untouched.

**Trust step:** Codex project hooks are inert until the user runs `/hooks` and explicitly trusts
the hook definition in `.codex/hooks.json`. What trust covers is **not verified** here. Assume it
covers only that JSON: the command resolves the repo root at run time and executes
`.claude/hooks/agent-role-codex.sh`, which runs `.claude/hooks/agent-role.sh` and
`.claude/hooks/lib/agent-state.sh` **from whatever branch is checked out**. Trusting the hook
therefore means trusting future versions of those three scripts on any branch you open in Codex,
without a new prompt. Review changes to them like any other code that runs on your machine.
Nothing breaks if the hook is never trusted: §5's `$skill-name` invocation is the primary
mechanism and works regardless.

**Contract verification status — read before relying on this:**

- **Verified**, `developers.openai.com/codex/hooks` (redirects to `learn.chatgpt.com/docs/hooks`
  as of 2026-09), cross-checked against public `openai/codex` GitHub issue reports on the same
  event: `UserPromptSubmit` stdin JSON carries `session_id`, `turn_id`, `cwd`, `hook_event_name`,
  `model`, `permission_mode`, and `prompt`. `agent-role.sh` reads only `session_id` and `prompt`
  via a `.get(field)`-style lookup that ignores unknown fields, so the extra Codex-only fields are
  harmless without any code change — confirmed by `agent-hooks-codex.test.sh`.
- **Verified**: plain stdout text on exit 0 is accepted as additional developer context, matching
  what `agent-role.sh` already does (`printf '%s\n' "$out"`, always exits 0). One observed
  difference: Codex appears to render this as a **visible** developer-facing message
  (openai/codex#16933) rather than Claude Code's silent system-reminder-style injection — the
  lane-assignment text still reaches the session either way, it's just visible in the transcript
  under Codex.
- **Not independently verified end-to-end against a live Codex session** — this was checked
  against public documentation and issue reports, not by running the hook inside an actual Codex
  CLI/desktop session in this task. If the observed behavior differs (e.g. a stricter JSON-only
  output requirement, a different exit-code-for-block convention), the fallback in §5 (explicit
  `$skill-name` invocation) still assigns the role correctly with no hook involved.
- **Unverified: the state-file write.** `agent-role.sh` records the role under
  `<git-common-dir>/claude-agent-roles/`. Codex's workspace-write sandbox commonly protects `.git`,
  and in a linked worktree the common dir sits outside the workspace. If that write is refused,
  the role message may not be printed at all. To prove it: trust the hook, send "You are the PRD
  manager" in a Codex session, confirm the developer message appears, and check that the state
  file exists. Until then, rely on §5.
- **Known adjacent issue, not applicable to this wiring**: `SessionStart` hook `additionalContext`
  injection is reported broken (openai/codex#45999). This repo does not use `SessionStart` for
  role detection — only `UserPromptSubmit` — so that bug does not affect this hook. It does mean
  the "re-inject role after compaction" half of the Claude Code pattern has no safe Codex
  equivalent yet, which is why §5 tells you to re-invoke the skill manually after compaction.

Tests: `scripts/dev/board/tests/agent-hooks-codex.test.sh` (input-parsing/forwarding behavior of
the adapter — Codex-shaped payload with extra fields, `AGENT_HOOK_RUNTIME=codex` export via a
mutation-checked stub, path-relative resolution, never-blocks-on-malformed-input). Run with the
rest of the suite: `bash scripts/dev/board/tests/run-all.sh`.

## 7. What is Claude-only

Do not look for these in Codex; they don't exist there:

- The `Agent` tool, `subagent_type`, and Claude's model aliases (`haiku`/`sonnet`/`opus`/`inherit`).
- `isolation: "worktree"`, `EnterWorktree`, `ExitWorktree`.
- `Monitor`, `ScheduleWakeup`, the `run_in_background` Bash parameter.
- `SendMessage` (cross-session), `TaskCreate`, `AskUserQuestion`, the `Skill` tool call.
- `.claude/agents/*.md` YAML frontmatter (`model:`, `tools:`) being auto-loaded by an agent-type
  selector — Codex's `spawn_agent` has no such loader; briefs must name the file explicitly (§3).
- `.claude/settings.json`'s hook wiring and its always-on trust model — Codex hooks live in
  `.codex/hooks.json` and require the one-time `/hooks` trust step per §6.
- `.claude/agent-models.json` / `scripts/sync-agent-models.mjs` — these pin Claude Code agent
  frontmatter to model aliases; Codex has no per-agent model routing, so there is nothing to sync
  against. `CLAUDE.md`'s cost principle still applies in spirit: don't escalate reasoning effort
  except for architect/planner/judge, and only delegate bounded, concrete work.

Everything else — `.claude/rules/*.md`, PRD workflow, PR/issue labels, delivery-contract
evidence requirements, git commit format, the lane protocol's GitHub-Issues-as-source-of-truth
model — is runtime-neutral and applies to Codex exactly as written.
