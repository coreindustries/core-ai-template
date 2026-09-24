## Summary

<!-- Provide a brief overview of the changes in this PR -->

-
-
-

## Files Changed

<!-- List the key files that were modified, added, or removed -->

-
-
-

## Test Plan

<!-- Checklist of items to verify before merging -->

- [ ]
- [ ]
- [ ]
- [ ]

## Risk Class

<!--
  REQUIRED if this PR touches: LLM/prompt/agent behavior, infra/CI/deploy,
  database schema or writers, scheduled jobs, cost-bearing APIs, or user-visible
  UI. Enforced by .github/workflows/delivery-contract.yml.

  Name the surface and the blast radius if this change is wrong.
  Not applicable? Delete these three sections and apply `skip-delivery-contract`.
-->

## Delivery Contract

<!-- REQUIRED alongside Risk Class. See .claude/rules/delivery-contract.md -->

- **Invariant:** <!-- what must remain true after this merges -->
- **Runtime boundaries touched:** <!-- processes, queues, external calls, schedules -->
- **All writers/callers checked:** <!-- how you know nothing depends on the old shape -->
- **Silent fallback paths changed or ruled out:** <!-- where could this fail without raising -->
- **Rollback/killswitch:** <!-- how to undo this in production -->

## Real Proof

<!--
  Evidence from an ACTUAL run: pasted command output, a real request/response,
  a screenshot from a real device, a log line showing the new path was taken.

  "Tests pass" and "should work" are not proof.
-->

## Additional Notes

<!-- Any additional context, breaking changes, migration steps, or related issues -->

## Related Issues

<!-- Link to related issues or tickets -->

Refs:

## Labels

<!--
  Apply labels before requesting review. The PR Labeler workflow auto-applies
  area/* labels based on changed paths; you apply the rest:

  - **Type** (one): bug | feature | enhancement | docs | chore | refactor |
    test | performance | security | breaking
  - **Priority** (one, if not P3): P0 | P1 | P2 | P3
  - **Status** (as needed): status/wip | needs-review | needs-test |
    needs-info | blocked | do-not-merge | ready-to-merge
  - **Process** (as needed): codex (request cross-model review),
    dependencies (Dependabot or manual dep PR),
    security-hotfix-24h-waiver (sub-24h dep bump with linked GHSA/CVE)

  Full list: .github/labels.yml
-->

- [ ] Type label applied (e.g. `feature`, `bug`, `docs`, `chore`)
- [ ] Priority label applied (if not P3)
- [ ] `codex` label added if cross-model review is desired
