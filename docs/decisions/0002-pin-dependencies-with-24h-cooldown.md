# ADR-0002: Pin Dependencies + 24-Hour Cooldown on New Versions

- **Status**: Accepted
- **Date**: 2026-04-21
- **Deciders**: Platform engineering
- **Supersedes**: —
- **Related**: ADR-0001 (No plaintext secrets on disk), `.claude/rules/dependency-security.md`

## Context

Package-manager supply-chain attacks are the dominant vector for developer-machine compromise in 2024–2026. The pattern is consistent across npm, PyPI, crates.io, RubyGems, and Docker Hub:

1. Attacker publishes a new version of a legitimate package (maintainer account takeover, typosquat, or malicious maintainer).
2. Install-time script (`postinstall`, `setup.py`, Dockerfile `RUN`) runs with full user permissions during `npm install` / `uv sync` / `docker build`.
3. Script exfiltrates `.env`, `~/.aws/credentials`, `~/.ssh/`, browser password stores, or installs a long-lived backdoor.
4. The ecosystem notices and yanks the bad version — typically within **4–36 hours**.

The cheapest single control that cuts this exposure to near-zero is **waiting 24 hours before any new version enters our builds**. The specific attacks we'd have been immune to by this rule alone include:

- `chalk`, `debug`, `color-*` (npm, Sept 2025) — yanked within hours
- `ctx` (PyPI, May 2024) — maintainer account takeover, yanked same day
- Multiple typosquats caught in <24h by OpenSSF and community tooling

The secondary threat is floating version ranges (`^1.2.3`, `~1.2`). Even with a 24h cooldown, a range in a manifest means `npm install` on any machine — CI, dev, staging, prod — may resolve to a different version than what was reviewed. Pinning to exact versions closes this gap and makes every build bit-for-bit reproducible against the lockfile.

## Decision

1. **Every direct dependency is pinned to an exact version** in manifests.
2. **Lockfiles are committed and used exclusively** for installs (`--frozen`, `--locked`, `ci`).
3. **GitHub Actions pin by commit SHA;** Docker base images pin by digest.
4. **Every added or upgraded dependency must be ≥ 24 hours old** at merge time. Enforced by:
   - Dependabot `cooldown.default-days: 1` (prevents PR creation)
   - `scripts/assert-dependency-age.sh` in CI (catches manual bumps)
5. **Waiver path**: `security-hotfix-24h-waiver` label, requires advisory ID in PR description.

## Consequences

**Positive:**

- Near-total immunity to the zero-day supply-chain window.
- Reproducible builds: the lockfile is the complete description of every artifact.
- Explicit review on every new dep (no silent range drift).
- Dependabot PRs batch nicely since cooldown aligns releases.

**Negative:**

- A genuinely urgent upstream fix that isn't a published advisory waits 24h. We accept this.
- Initial friction when migrating an existing project with many unpinned deps. Migration script provided (see `scripts/pin-dependencies.sh` stub — TODO).
- Reviewers must check the Rule 3 checklist on new deps rather than trusting auto-merge.

**Neutral:**

- Transitive deps under a locked range still pin (lockfile captures the resolution); cooldown applies when a transitive resolves to a new version.

## Alternatives considered

- **Renovate with `minimumReleaseAge`**: equivalent functionality to Dependabot cooldown. Chose Dependabot for native GitHub integration; Renovate remains acceptable if a project needs its more flexible config.
- **7-day cooldown**: more conservative but introduces friction on legitimate security fixes. 24h is the empirical sweet spot per attack-yank timelines.
- **Manual review only (no cooldown)**: relies on reviewers noticing brand-new versions. Doesn't scale; humans routinely approve dependency bumps without checking publish times.
- **Socket.dev / Snyk / OpenSSF Scorecard as a gate**: complementary, not a substitute. They catch known-bad; cooldown catches unknown-bad that hasn't been classified yet.

## References

- `.claude/rules/dependency-security.md` — operational rule
- `.github/dependabot.yml` — cooldown configuration
- `scripts/assert-dependency-age.sh` — CI enforcement
- [Dependabot cooldown docs](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference#cooldown--)
- [SLSA framework](https://slsa.dev/)
- [OpenSSF Scorecard](https://github.com/ossf/scorecard)
