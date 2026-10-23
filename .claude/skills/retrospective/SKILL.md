---
name: retrospective
description: "Post-incident framework: after a failure's root cause is understood, run a structured retrospective: PR-history archaeology, closest-miss analysis, an RCA-capturing test on the REAL target, and a durable workflow modification (an enforced gate, not a prose rule). Use when a shipped feature failed at the user-visible seam, when a bug feels like a regression, or when the same class of failure keeps recurring. Distinct from /debug (in-the-moment fix) and /compound (capture one solution doc)."
---

# /retrospective

Turn a solved incident into (1) an understanding of **how it shipped broken**, (2) a
test that **captures the root cause**, and (3) a **workflow change that kills the
class**, so the same failure mode stops recurring.

## Usage

```
/retrospective [--incident "<one-line failure>"] [--area <path/subsystem>]
```

Run this AFTER the root cause is confirmed (via `/debug` or investigation). It is not
for finding the fix; it is for finding why the process let it through.

## When to use

- A shipped feature failed at the **user-visible seam** (the DB wrote but the UI did
  not update; the API returned 200 but the user saw nothing).
- A bug "feels like a regression" against something that was supposed to be designed out.
- The **same class of failure keeps recurring** (green units, broken seam).

Skip it for a one-off typo fix with no process signal.

## The framework (produce all five parts)

### 1. Establish the RCA precisely
State the confirmed root cause as a small set of **compounding gaps**, each pinned to
a `file:line`. Distinguish *deliberate design* from *unfinished work* (a missing
listener, an un-run test); the workflow fix differs. Name the mechanism, not the symptom.

### 2. PR-history archaeology (delegate this)
Push the reading into a subagent (`Explore` or `general-purpose`) and keep the verdict,
not the diffs. Have it list **every PR that touched the affected area**
(`gh pr list --state all --search`, `git log --all -- <path>`) and extract for each:
- **What it built.**
- **Its test plan**, and whether it **verified the user-visible outcome end to end**
  or only a proxy (a row was written, an API returned 200, a unit passed).

Return a compact table: `PR# | title | what it did | outcome-test coverage: full / partial / none`.
Flag every PR whose test asserted the write but not the outcome the user sees.

### 3. Closest-miss analysis
Name the 1-2 PRs that had the fix in reach and the **specific line they left undone**.
Recurring miss shapes:
- **Rejected-with-the-baby:** a PR with the exact fix was closed for a different, valid
  reason and the replacement never re-added it.
- **Emit without listener:** a PR added the server-side event but wired the client
  listener into only some surfaces (grep the event name across all clients).
- **Specced-then-deferred:** the fix existed as written acceptance criteria before the
  incident, shipped with every box unchecked as a "separate PR" that never landed.

If the RCA existed as prior acceptance criteria, say so plainly: the failure is "we
knew and did not close the loop," which points straight at the workflow fix.

### 4. RCA-capturing test
Write the test that **asserts the user-visible outcome no prior PR asserted**, and
specify that it runs against the **real target** (the deployed or live seam), not a
local fixture or mock. Enumerate the assertions in order, ending with the one that
would have caught this incident. Add a structural check where relevant (every
`emit` has a listener).

### 5. Workflow modification (an enforced gate, not a prose rule)
Prose rules are how these bugs recur. Propose a **mechanical** change:
- A **merge gate** requiring proof of the user-visible outcome on the real target for
  this class of feature.
- **Ban the deferred outcome:** no merge with the user-outcome checkbox unchecked or
  punted to a "separate PR".
- A **structural lint/test** for the specific miss shape found.

End with a **one-line lesson** in the team's own voice.

## Recurring patterns to hunt for

| Pattern | What it looks like | Where it hides |
|---|---|---|
| Green units, broken seam | Units and "API returns 200" pass; the real cross-service/UI seam is broken | The test plan never drove the real seam |
| Tested the write, not the sighting | Asserts the row or event, never that the user saw it | A load-once effect that never re-subscribes |
| Deferred outcome shipped as done | Unchecked box, `TODO`, "separate PR", e2e written but not run | PR bodies merged with unchecked verification items |
| Emit without listener | Event emitted; only some pages listen | grep the event across all client surfaces |
| Policy fix, code untouched | A "always do X" rule with no mechanical change | The handler the rule describes never changed |
| Specced before the incident | The fix is an acceptance criterion predating the failure | An unchecked requirement in an older PR |

## Output

1. A retro doc at `docs/solutions/<category>/YYYY-MM-DD-<slug>-retrospective.md` with
   the five sections (reuse `/compound` conventions).
2. The RCA-capturing test, added alongside the fix.
3. A concrete workflow-gate proposal, either as a CI check in the same PR or tracked as
   its own follow-up (ask which).

## Agent behavior

- Delegate the archaeology; synthesize the verdict here. Do not inline-read dozens of
  PR diffs.
- Be specific: `file:line` and PR numbers, not adjectives.
- Judge the mechanism, not people. The goal is a gate that makes the next feature reliable.
