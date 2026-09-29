---
name: deploy
description: >-
  Deploy the application to a target environment using the commands defined in
  prd/00_technology.md. Use when a release is ready to ship to staging or production. Do
  not use to cut a version tag or changelog first (`/release`), use scripts/post-deploy-health.sh for the configured post-deploy health checks.
---

# /deploy

Deploy the application to target platform.

## Usage

```
/deploy [environment] [--platform <platform>] [--dry-run]
```

## Arguments

- `environment`: `staging`, `production` (default: `staging`)
- `--platform`: Override auto-detected platform
- `--dry-run`: Preview deployment without executing

## Workflow

Read `prd/00_technology.md`, the project's release runbook and `.claude/rules/guardrails.md`, `secrets-hygiene.md`, `dependency-security.md`, and `delivery-contract.md`. Use the configured deployment entrypoint and release owner; do not invent platform commands. `--platform` overrides selection, not authorization or release policy.

1. Identify the target, immutable revision, verified artifact/digest, configuration inputs and rollback artifact. Require a clean release worktree, the configured branch and applicable checks. Respect the staging-first ladder and explicit production confirmation; existing in-session authorization need not be requested again.
2. Reuse the verified artifact across environments. Rebuild only when required inputs changed, the artifact is unavailable/invalid or reproducibility is requested. Changed artifacts need new proof. Never remove locks or freshly resolve dependencies merely to make deployment pass.
3. Identify durable state, migration authority, readiness and rollback compatibility. Preserve existing locks, journal and production-data controls. `--dry-run` presents the exact plan and stops before mutation.
4. Execute the authorized configured entrypoint. A failed gate stops promotion; diagnose the cause before a safe bounded retry or authorized rollback. Do not substitute an ad hoc command or create another release publisher.
5. Run the configured post-deploy health check (including `scripts/post-deploy-health.sh` where applicable) and real user-path proof. Record actual artifact/configuration placement, observed results and remaining uncertainty in the existing journal or release record. Build success alone is not deployment proof. Do not create extra deployment tags or trackers unless the release process requires them.
