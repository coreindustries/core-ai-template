---
name: apple-verify
description: >-
  Verify a native macOS or iOS feature in its signed app using isolated data, actual UI and
  applicable device checks. Use for native acceptance testing or release verification, not
  pure Swift logic tests or publishing to the App Store.
---

# /apple-verify

Prove the requested user workflow on the actual app artifact. Read the enabled
[shared Apple](../../rules-available/apple-native.md) and relevant
[macOS](../../rules-available/macos.md) or [iOS](../../rules-available/ios.md) rules.
Use existing project commands and evidence records; this skill adds no new test harness,
release pipeline, permission, cloud call or publishing authority.

## Establish the target

- Confirm the checkout/commit, target, scheme, build configuration, installed Xcode/SDK,
  deployment target, bundle identifier, signing/capabilities and test device/OS. Separate an
  unavailable SDK, entitlement or model asset from an application failure; record blocked checks.
- Follow the existing acceptance criteria. Probe an uncertain framework boundary before a broad
  implementation; compile the actual target, not just a differently linked helper executable.
- For new projects, put platform/product choices and build/test commands in `prd/00_technology.md`.
  Enable the applicable `make enable-macos` / `make enable-ios` preset. Do not assume this
  template's shell commands, services or media examples are the new product's architecture.

## Isolate before exercising

- Identify the user's running app and durable data. Use synthetic fixtures and isolated test
  storage/preferences, with a separate preview bundle/device install where needed. A worktree
  alone does not isolate containers, Keychain access groups, app groups, cloud or Spotlight.
- Inspect the project's actual UI-test launch behavior before running it: a shared bundle ID
  can terminate/replace the running app. Do not reset TCC, delete user stores, switch live cloud
  containers or broaden entitlements to make a test pass. Reuse existing authorization and
  report genuine missing access without inventing an approval step.

## Exercise the applicable seams

- Run affected deterministic checks, then launch the signed app and follow the user path.
  Use stable accessibility identifiers and inspect the actual hierarchy/label/value. Assert
  visible outcomes rather than assuming a SwiftUI Table is exposed as an accessibility table.
- For stateful UI, test replacement/cancellation, selection during work and close/reopen.
  Delayed results must not overwrite a newer selection. Auxiliary-window closure must not
  terminate unrelated app-owned work. Exercise empty, unavailable and deleted-item states.
- For persistence, read [Apple persistence](../../references/apple-persistence.md). Use real
  temporary stores for save/readback, older schemas and applicable failure cases; verify
  read-only inspectors do not invoke hidden writers/importers.
- For permissions/hardware/background behavior, test on the relevant physical device and
  record denied/revoked access, interruption and supported recovery. Compile iOS device and
  simulator targets; simulator results do not establish hardware/model/background behavior.
- For AI, read [Apple AI models](../../references/apple-ai-models.md). Test actual availability,
  streaming/cancellation, exposed usage metadata and indicators against the same SDK request.
  Only exercise cloud paths authorized by the project/user; unapproved entitlements remain a
  blocker, not evidence that fallback worked. Keep prompts and private content out of telemetry.

## Verify delivery and report

- When packaging/installing is in scope, promote the tested artifact; validate the resulting
  signature/capabilities and app launch. Compare executable content in a way that accounts for
  re-signing, rather than treating a changed signature as a source-code mismatch. A rebuilt or
  changed artifact needs relevant proof again. Preserve user records and previous artifacts.
- Verify a requested alias/launcher resolves to the intended app. Keep ad-hoc development,
  notarization, TestFlight and App Store acceptance as separate evidence levels; do not claim
  distribution readiness from a local build. Publishing requires its own authorization.
- Record commands/results, artifact/commit, signing, OS/device, tested workflow, observed output,
  material failure/negative controls and unrun checks in the existing PR/task record. Distinguish
  unit, signed-app UI, real-device/model and distribution checks. Report the user-visible result
  first; missing hardware or credentials means unverified, not passed.
