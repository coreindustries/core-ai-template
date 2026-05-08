---
id: NNN
direction: incoming           # incoming | outgoing
title: Short description of the cross-repo ask
from: owner/originating-repo  # who opened this
to: owner/receiving-repo      # who is implementing
prd: PRD-NNN or "ad-hoc"
status: Requested             # Requested | In Progress | Done | Superseded
created: YYYY-MM-DD
branch:                       # optional: branch where related work lives
related_pr:                   # optional: list of PR URLs on either side
  - https://github.com/owner/repo/pull/NNN
---

<!--
  Mirrored docs (incoming on the receiving side, or outgoing once the
  partner has accepted): prepend an "## Implementation Notes" section
  describing what was/will be changed, on what branch, with what
  tests. Leave the originator's write-up below intact.

  New outgoing docs: skip "Implementation Notes" until the partner
  starts work; just fill the request below.
-->

## Implementation Notes

<!-- Receiving side's view. What was changed, on what branch, what
     verification, what's left. Update as the work progresses. When
     the work ships and partner confirms, this becomes the durable
     reference for "what we did on our side." -->

---

# {{Title — same as frontmatter `title`}}

## Background

<!-- Why is this ask happening? What's the state of the world that
     made it necessary? Two or three short paragraphs. -->

## Ask

<!-- The concrete change being requested. Be specific:
     - For schema asks: what columns / tables / indexes / RLS / triggers.
     - For API asks: what endpoints / fields / contract changes.
     - For ops asks: what env var, deploy path, CI rule.
     - For deprecation asks: what's being removed and the deadline.
-->

- {request 1}
- {request 2}

## Constraints

<!-- What must be preserved? What can't change?
     - Backwards compatibility windows
     - Data migration constraints (online vs offline, large tables)
     - Deadlines tied to releases or third-party launches
     - Security / compliance requirements
-->

- {constraint 1}
- {constraint 2}

## Acceptance criteria

<!-- How both sides know the ask is satisfied. Write as a checklist
     so it's easy to confirm at handoff. -->

- [ ] {criterion 1}
- [ ] {criterion 2}
- [ ] {criterion 3}

## References

<!-- Links to PRDs, ADRs, related issues/PRs in either repo, design
     docs. Don't paste content — just link. -->

- PRD: `prd/PRD-NNN.md`
- ADR: `docs/decisions/NNNN-<slug>.md`
- Related PR: https://github.com/...
- Slack thread: <permalink>
