# 0005: CI/CD Supply Chain Hardening

**Status:** Accepted
**Date:** 2026-05-21
**Deciders:** Corey (principal), Claude Code (implementation)

## Context

In May 2026, the "Mini Shai-Hulud" campaign compromised 3,800+ GitHub repositories and 1,000+ npm/PyPI packages via poisoned dev tooling, with valid SLSA provenance on malicious versions. The constant across attack waves: trust in dev tooling and credential exfiltration as the kill chain.

An audit of this repo's `ci.yml` found the following gaps:

| Gap | Description |
|-----|-------------|
| Unpinned actions | `actions/checkout`, `astral-sh/setup-uv`, `codecov/codecov-action`, `gitleaks/gitleaks-action`, `docker/setup-buildx-action`, `docker/build-push-action` all used tag-based refs. Tags are mutable — a compromised maintainer can repoint them. |
| Credential persistence | No `persist-credentials: false` on any checkout step. `GITHUB_TOKEN` remained accessible for the full job duration unnecessarily. |
| No explicit permissions | `ci.yml` inherited full read-write defaults. A compromised workflow step could write to the repo or open issues. |
| No workflow static analysis | No gate preventing future regressions to any of the above gaps. |

`labeler.yml`, `labels-sync.yml`, and `dependabot.yml` were already in good shape (SHA-pinned, explicit permissions, weekly cadence).

## Decision

Apply all four fixes to `ci.yml` in a single commit, and add `zizmor.yml` as a permanent regression gate:

1. **SHA-pin all GitHub Actions** — replace tag refs with immutable commit SHAs; retain tags as trailing comments (`# vN`) for readability and Dependabot compatibility. SHAs resolved 2026-05-21 via `git ls-remote`.
2. **Add `persist-credentials: false`** to all `actions/checkout` steps — reduces `GITHUB_TOKEN` exposure window to zero (no job step requires git credentials post-checkout).
3. **Add `permissions: contents: read`** top-level in `ci.yml` — prevents inherited read-write defaults on fork PRs.
4. **Add `zizmor.yml`** — runs Zizmor on every PR touching `.github/workflows/**`, blocking merge on any finding ≥ low severity.

### SHA Pins (resolved 2026-05-21)

| Action | Tag | Commit SHA |
|--------|-----|------------|
| `actions/checkout` | v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `astral-sh/setup-uv` | v7 | `37802adc94f370d6bfd71619e3f0bf239e1f3b78` |
| `codecov/codecov-action` | v6 | `e79a6962e0d4c0c17b229090214935d2e33f8354` |
| `gitleaks/gitleaks-action` | v2 | `ff98106e4c7b2bc287b24eaf42907196329070c7` |
| `docker/setup-buildx-action` | v4 | `4d04d5d9486b7bd6fa91e7baf45bbb4f8b9deedd` |
| `docker/build-push-action` | v7 | `f9f3042f7e2789586610d6e8b85c8f03e5195baf` |

Dependabot (`github-actions` ecosystem, weekly cadence) is the ongoing source of truth for keeping these pins current.

## Consequences

**Positive:**
- A compromised action maintainer cannot inject code without a Dependabot PR being merged — the SHA is immutable post-merge.
- `GITHUB_TOKEN` exposure window reduced from full job duration to zero for all workflows.
- `contents: read` permission prevents any step from writing to the repo or creating issues without explicit permission escalation.
- Zizmor blocks future regressions silently entering the codebase via workflow changes.

**Negative:**
- Weekly Dependabot churn: SHA-pin bump PRs will appear. Expected steady-state maintenance cost.
- Frozen behavior: SHA-pinned actions don't auto-update. Security patches require Dependabot to surface them.

**Neutral:**
- No behavior impact on workflow execution — all changes are structural, not functional.

## Agent Guidance

All GitHub Actions `uses:` references in `.github/workflows/` must be SHA-pinned with a trailing `# vN` comment. Never replace a SHA pin with a tag reference.

## Do Not Change

- **SHA pins**: Do not replace `owner/action@<sha> # vN` with `owner/action@vN` — tags are mutable and this restores the supply chain vulnerability.
- **`persist-credentials: false`**: Do not remove from checkout steps without an explicit `git push` or `git fetch` requirement and an inline token supplied at the step level.
- **`permissions: contents: read`** on `ci.yml`: Do not remove or widen without a documented reason in the PR description.
- **`zizmor.yml`**: Do not delete or disable — it is the regression gate for all of the above.
