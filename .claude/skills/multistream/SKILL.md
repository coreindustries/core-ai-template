---
name: multistream
description: "Deliver independent feature or repair streams concurrently with isolated writers and test resources, while serializing shared release mutations."
---

# /multistream

Read `.claude/rules/delivery-contract.md`, `.claude/rules/ai-agent-patterns.md`
(subagent briefs and isolation) and `.claude/skills/_shared/agent-protocol.md`.
Parallel delivery is the goal. This skill grants no production access and bypasses no
runtime permission; authorized parent operations use the normal approval path.

## Plan the streams

Use the existing issues and draft-PR claims as the progress authority
(`scripts/dev/board/board.sh`). Do not create a second status registry. Choose
independent outcomes with explicit integration contracts. A shared file, schema or
authority gets one integrator; split implementation around that owner instead of
adding reconciliation or forcing every feature into a serial queue.

Use `architect`/`planner` when the task warrants them. Check how many agents the
runtime allows before fan-out, and give each a self-contained brief.

## Isolate each writer

Give every concurrent writer a parent-created absolute worktree (under `.worktrees/`),
exclusive files, acceptance criteria and forbidden operations. Name the ports,
database/volume names, image tags, credentials and namespaces its tests need.
Read-only workers can share the checkout. A worktree alone does not isolate host
resources such as ports, containers or a local database.

Claim the work (draft PR or issue label) before implementation. The parent keeps
shared-file integration, staging and commits, GitHub mutations, final verification
and any production operation unless explicitly delegated within actual authorization.
Children report code, CI and proof readiness accurately, not deployment success.

## Keep validation independent and promotion serial

Independent validation builds may run concurrently only when their build context,
resources and artifact names are actually isolated. Otherwise serialize them. Never
assume separate worktrees make shared mutable tags or caches private.

One owner controls publication and the production rail. Build and publish each
immutable release once and promote that same artifact through the environment ladder;
do not rebuild per stream or per target. Serialize shared tags, release publication
and production mutations. Independent implementation and isolated checks continue
while that rail is occupied. Do not fold unrelated source changes into an in-flight
release silently. A failed gate stops promotion; unrelated feature work continues.

## Proof and handoff

Use the delivery-contract fields: outcome, authority transfer, retirement, real seam
proof and rollback. Review significant changes with an independent `judge` after
writers stop. Complete the required checks without adding an agent or workflow per
checklist item.

Update the authoritative issue at material transitions. Done means the real requested
outcome is verified; distinguish code-ready, merged, deployed and verified. If
deployment is outside this task's authority, hand off the exact artifact and the
remaining proof instead of implying completion. After compaction, resume from the
recorded next step.
