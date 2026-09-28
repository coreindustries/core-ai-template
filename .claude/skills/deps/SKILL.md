---
name: deps
description: >-
  Audit, update, and manage dependencies under the pinning and 24h-cooldown rules in
  .claude/rules/dependency-security.md. Use when adding a dependency, reviewing a
  Dependabot PR, or checking for known vulnerabilities. Do not use for secret scanning
  or SAST (`/scan`), and note it will refuse a version that has not cleared the
  cooldown.
---

# /deps

Audit, update, and manage project dependencies safely.

## Usage

```
/deps [action] [package] [--security] [--outdated]
```

## Arguments

- `action`: `audit`, `update`, `add`, `remove`, `outdated` (default: `audit`)
- `package`: Specific package name (for add/remove/update)
- `--security`: Focus on security vulnerabilities only
- `--outdated`: Show only outdated packages

## Workflow

Use `prd/00_technology.md` and `.claude/rules/dependency-security.md` for package-manager commands, exact pins, lockfiles, install-script review and the 24-hour age policy. Read `.claude/rules/delivery-contract.md` for ownership and artifact proof.

- `audit` and `outdated` are read-only reports. `--security` limits findings to vulnerabilities; `--outdated` limits them to available updates. Name affected versions, evidence and remediation; an available version is not an instruction to upgrade.
- `add` first checks whether existing dependencies or modules meet the requirement. Review provenance, maintenance, vulnerabilities, release age and install scripts; pin the chosen version.
- `update` changes the requested package or requested scope. Review compatibility and changelogs; major upgrades require confirmation unless already explicitly authorized. Patch/minor versions are not automatically safe.
- `remove` identifies and retires callers, imports, configuration and documentation in scope before removing the package.

Use the owning manifest and committed lockfile with native workspace commands. Preserve unrelated resolutions; diagnose conflicts rather than deleting the lock. Verify locked installation, affected callers and applicable tests/build gates. Package publication or runtime installation needs proof with the actual artifact, including consequential stale/interrupted state and retry behavior. Commit manifest and lock together when committing is authorized. Report exact changes and unverified boundaries; do not auto-commit or broaden an audit into updates.
