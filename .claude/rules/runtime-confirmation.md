---
paths:
  - "**/*.{js,cjs,mjs,jsx,ts,cts,mts,tsx,py,sh,go,rs,rb,java,kt,swift,cs,php}"
---

# Runtime Confirmation

**Scope:** Changes that parse or match a real data shape, or cross a runtime seam (provider payloads, DB rows, queue or socket events, log-driven features). Fixture and negative-control rules live in `testing.md` ("Tests That Prove Something"); proof of the outcome lives in `delivery-contract.md`. This rule covers what happens after the tests pass.

Why: a test written from the same wrong mental model as the code can only agree with it, and a feature can ship, pass every test, and never execute on real traffic.

## Confirm the feature fires in the running system

Present is not the same as executing. After the change is live (or on the closest real environment), verify the path runs:

- **Look for the fallback or skip log, not the success log.** A feature that always takes its degraded path is dead, and its success log never appears. Search for the SKIPPED, exhausted or fallback wording and count it.
- **Count outcomes, not invocations.** "Ran 40 times" means nothing if it fell back 40 times.
- **Use a real user action** rather than a synthetic probe when the bug class is timing- or ordering-sensitive.

## Minimum bar for a PR touching a runtime seam

- [ ] A real-shape sample with its source named (see `testing.md`)
- [ ] A named post-deploy check that proves the path fires, including which log line would prove it did not
