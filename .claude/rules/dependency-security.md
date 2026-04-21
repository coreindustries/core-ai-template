# Dependency Security — Pin Versions, Cooldown New Releases

Auto-loaded rule. Applies to all package-manager ecosystems (npm, pip, uv, poetry, cargo, gomod, composer, Docker base images, GitHub Actions).

## Core Directive

**Every dependency — direct and transitive — must be locked to an exact, auditable version.** No floating ranges. No `latest`. No unpinned base images.

**Every new version added to the lockfile must be at least 24 hours old at merge time.** This window lets the ecosystem catch a freshly-published malicious release before it lands in our build.

The threat model is identical to `.claude/rules/secrets-hygiene.md`: a malicious package runs with full user permissions at install time (`npm install`, `uv sync`, `pip install`, `docker build`). Documented supply chain attacks — `xz` (2024), `chalk`/`debug` / `color` (Sept 2025 npm), `ctx` / `phpass` on PyPI, multiple typosquats — had their malicious versions yanked within hours to a day of publish. A 24-hour cooldown is the single cheapest control that eliminates the zero-day exposure.

---

## Rule 1 — Pin direct dependencies to exact versions

No ranges in manifests for direct dependencies. No `^`, `~`, `>=`, `*`, `latest`, `main`, `master`, or branch refs.

| Ecosystem | Wrong | Right |
|---|---|---|
| npm / pnpm / yarn / bun (`package.json`) | `"react": "^18.3.0"` | `"react": "18.3.1"` |
| pip / uv / poetry (`pyproject.toml`) | `fastapi = "^0.115"` | `fastapi = "==0.115.6"` |
| cargo (`Cargo.toml`) | `serde = "1"` | `serde = "=1.0.210"` |
| gomod (`go.mod`) | (already pins) | `require foo v1.2.3` with `go.sum` committed |
| Docker (`Dockerfile`) | `FROM node:22` | `FROM node:22.11.0-alpine@sha256:abc…` |
| GitHub Actions | `uses: actions/checkout@v4` | `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` |

- **Docker**: pin to an image digest (`@sha256:...`), not just a tag. Tags are mutable; digests are not.
- **GitHub Actions**: pin to a commit SHA (full 40-character), with the tag as a trailing comment for readability. Dependabot understands this and will bump the SHA.
- **Transitive pinning**: lockfile commits are mandatory (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `uv.lock`, `poetry.lock`, `Cargo.lock`, `go.sum`).
- **Installs must use the lockfile exclusively**: `npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `poetry install --no-update`, `cargo build --locked`. Never plain `install` in CI or production images.

## Rule 2 — 24-hour cooldown on new versions

A package version must be publicly available for **at least 24 hours** before we merge a PR that adds or upgrades to it. This applies to:

- Direct dependencies (primary target)
- Transitive dependencies when a lockfile resolution changes the version
- Docker base images
- GitHub Actions pins (SHA bumps)

Enforcement layers (defense in depth):

| Layer | Mechanism | Fails on |
|---|---|---|
| Dependabot | `cooldown.default-days: 1` in `.github/dependabot.yml` — PRs aren't opened until a version is ≥ 24h old | N/A (prevents at source) |
| Renovate (if used) | `minimumReleaseAge: "24 hours"` | N/A (prevents at source) |
| CI gate | `scripts/assert-dependency-age.sh` queries registry APIs for every added/changed lockfile entry | PR merging a <24h-old dep |
| Manual review | Reviewer checks `npm view <pkg>@<ver> time` or equivalent for any suspicious bump | Human backstop |

### Waiver process

A sub-24h dependency bump is permitted only when:

1. The bump is a published **security advisory** fix (GHSA / CVE with a defined affected range that includes the currently-pinned version).
2. The incident commander (or merging reviewer) documents the waiver in the PR description with:
   - The advisory ID
   - The CVSS score
   - Why the 24h wait is worse than the advisory exposure
3. CI is overridden with the label `security-hotfix-24h-waiver` — the label is auditable and rate-limited (no more than N per month per repo).

Do not waive the cooldown for "urgent feature" bumps. A feature can wait.

## Rule 3 — Review every new direct dependency before adding

The 24-hour cooldown does not replace review; it buys time for review to happen.

**Checklist before adding a new direct dependency:**

- [ ] Maintainer history: at least 6 months, multiple committers, not a single-maintainer brand-new package. (Typosquats and new-account attacks are the majority of active PyPI/npm compromise vectors.)
- [ ] Download / star count: not a ghost package. Sub-100-weekly-downloads packages are high-risk.
- [ ] Security advisories: `npm audit`, `pip-audit`, `cargo audit`, `govulncheck` clean on the target version.
- [ ] Install scripts: check for `postinstall`, `preinstall`, `prepare` (npm) or `setup.py` / build scripts (PyPI) that run arbitrary code. If present, read them. If unreadable / obfuscated, reject.
- [ ] License compatibility.
- [ ] Is it already transitively installed? Prefer adding it as a direct pin of the existing version over pulling a new tree.
- [ ] Could the functionality live in ~50 LoC of first-party code? If yes, prefer that.

Document the decision in the PR description ("Why this package, what did you check"). This is also how the ADR system is fed.

## Rule 4 — Lockfile integrity

- Lockfiles are source of truth; never hand-edit.
- `make deps-audit` fails CI if:
  - A lockfile exists but the manifest has unlocked ranges not reflected in the lock
  - A lockfile has been modified without the manifest changing (unexplained drift — often malware installer behavior)
  - The lockfile integrity hash (npm's `integrity:`, uv's hash block) is missing on any entry

## Rule 5 — Containers & supply chain artifacts

- Base images: pinned by digest, rebuilt weekly (Dependabot `docker` ecosystem will bump digests on a schedule).
- Multi-stage builds: every stage's `FROM` is digest-pinned.
- CI uses minimal base images (`distroless`, `alpine`, `scratch`). Do not install shell utilities "just in case" in production images.
- SBOMs (Software Bill of Materials) generated on every release build: `syft` / `cyclonedx`. Uploaded as a workflow artifact and (for tagged releases) attached to the GitHub Release.
- Signed releases: container images signed with `cosign` and verified in deploy. GitHub Release tarballs use `gh attestation` (or equivalent).

## Rule 6 — Agent behavior

An AI agent editing dependency files must:

- **Never** use the latest-by-default when adding a package; look up the version that's at least 24h old.
- **Never** remove a pin to "fix" a resolution error. Diagnose the conflict.
- **Never** add a package post-install script or shell-out command without calling it out in the PR description.
- **When asked** to update a dep to a just-released version, respond:
  > "That version published <N hours> ago. Our cooldown rule is 24 hours. I'll wait, or you can file a security-hotfix waiver if this is a published advisory fix."

- **When asked** to add a package, propose the pin and version plus the review checklist from Rule 3.
- **When asked** to use an unpinned base image or action, refuse and pin to digest/SHA.

If the agent discovers a floating-range dependency or an unpinned base image during unrelated work: flag it in the PR body, do not silently fix it (out-of-scope changes are hard to review).

## Enforcement summary

| Control | Where | Fails on |
|---|---|---|
| `.github/dependabot.yml` `cooldown:` | Source (prevents PR creation) | New versions younger than 24h |
| `scripts/assert-dependency-age.sh` | CI + pre-push | Lockfile entries whose registry publish time is < 24h old |
| `make deps-audit` | Local + CI | Unpinned manifests, missing lockfile integrity, unreviewed new deps |
| Pre-commit: gitleaks + assert-no-plaintext-env + optional dep-age | Pre-commit hook | Local fast feedback |
| Review checklist (PR template) | Manual | Anything the above missed |

## References

- [Dependabot cooldown](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference#cooldown--)
- [Renovate `minimumReleaseAge`](https://docs.renovatebot.com/configuration-options/#minimumreleaseage)
- [OpenSSF Scorecard](https://github.com/ossf/scorecard) — automated signals on maintainer health
- [SLSA](https://slsa.dev/) — supply chain integrity framework
- NIST SP 800-161 Rev. 1 — Cybersecurity Supply Chain Risk Management
- OWASP Top 10 CI/CD Security Risks: Insufficient Credential Hygiene, Third-Party Services
