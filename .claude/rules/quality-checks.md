# Quality Checks Rules

Use `prd/00_technology.md` for project commands and `testing.md` for verification scope.

- Run affected lint, formatting, type and test checks at meaningful change boundaries. Broaden for integration risk, failures, unresolved concerns, explicit requests and configured gates. Do not rerun unchanged checks on a timer.
- All code must pass applicable lint before commits. Preserve configured security scans, dependency policies, coverage thresholds, hooks and required CI checks; this guidance does not waive them.
- Before committing, inspect the actual diff and staged paths, run `git diff --check`, and finish applicable checks. Do not apply whole-tree automatic fixes to unrelated files or force a full suite merely because another commit is due.
- Before merge, satisfy existing CI, review, security and coverage gates and document any unverified runtime boundary under `delivery-contract.md`. Local success does not prove remote CI or a deployed target.
- Reuse the existing pipeline. Add or change a check for a demonstrated uncovered failure and a decision that consumes its result. Deployment is not an automatic stage of every project or task; preserve the configured release policy and authority.
