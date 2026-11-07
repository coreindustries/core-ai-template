---
paths:
  - "**/*.swift"
  - "**/*.xcodeproj/**"
  - "**/*.xcworkspace/**"
  - "**/*.plist"
  - "**/*.entitlements"
  - "**/*.xcprivacy"
  - "**/Package.swift"
---

# Native Apple engineering

Enable with `make enable-apple`, or through `make enable-macos` / `make enable-ios`.
These shared obligations complement the platform rule. Read
[Apple AI models](../references/apple-ai-models.md) before choosing or changing inference.

## Ownership and concurrency

- Keep one owner for recording state, audio-session lifetime, each file writer, playback,
  and each inference operation. Share portable models/services across targets; adapt UI,
  permissions and capture at the platform boundary.
- Use Swift concurrency for asynchronous operations and `@MainActor` for UI publication.
  A serial dispatch queue remains appropriate for framework callbacks and queue-confined
  media writers. An actor alone does not make synchronous expensive work leave MainActor.
- Real-time audio callbacks must not perform disk/network I/O, inference, blocking waits,
  unbounded allocations or task creation. Copy borrowed buffers into bounded owned storage;
  process them on the owning queue. Never retain framework pointers past their lifetime.
- Make cross-isolation ownership explicit. Do not add `@unchecked Sendable` without a
  documented lock/queue invariant; prefer immutable values or `sending` transfer where supported.
- Bound every stream, queue, cache and task fan-out. Specify the overflow policy and surface
  lost audio. Use one active write plus one replaceable latest snapshot, not a task per update.
- Guard delayed results by operation and session identity. Cancel on replacement, drain
  accepted packets before closing writers, and prevent stale callbacks from publishing.
  Preparation, recording, stopping and failed finalization must be distinct observable states.

## App state and persistence

- Share app-owned database and inference services across windows/scenes. Opening a diagnostic
  view must not construct another service or restart work. Guard view queries by selection,
  page and request identity; closing a view cancels its queries, not unrelated app-owned work.
- Keep SwiftData/Core Data contexts and managed models within their isolation boundary; return
  immutable Sendable projections to UI/services. Keep expensive work off MainActor explicitly.
- For structured storage, migrations, retrieval indexes or inspectors, read
  [Apple persistence](../references/apple-persistence.md). Keep product-specific folder,
  provider and cloud-routing choices in the project's own PRD; these presets do not select them.

## Long sessions, CPU and storage

- Stream audio/video to disk; never accumulate a full recording, decoded movie or per-second
  screenshots in RAM. Use bounded decoder batches and scoped autorelease pools where needed.
- Keep source-specific monotonic timestamps on a shared recording clock. Overlapping speakers
  are valid; one input must not advance the other input's clock. Preserve offsets through
  resampling and playback. Validate format changes, discontinuities and converter tails.
- Isolate metering from transcript observation. Use a rolling FFT with cached band mapping,
  coalesced level snapshots and an explicit refresh budget. Pause timers/animations when idle
  or hidden; expire stale meters. Avoid recomputing the full transcript on every audio packet.
- Coalesce serialization off MainActor. Persist an authoritative atomic snapshot and derive
  Markdown/exports from it. A flush barrier must report failures; do not label unsaved work saved.
- Budget disk from actual sample rate, channels and sample format plus duration/headroom.
  Recheck remaining space during capture. Low disk and failed exports must be visible; preserve
  usable audio when optional video or live transcription fails.
- For long screen capture, prefer bounded-resolution hardware-encoded video with recoverable
  fragments/checkpoints over an always-on PNG folder. Throttle before rendering. Link only
  finalized media; retain a recovery journal and distinguish recovered/incomplete output.
- Generate key-moment stills on explicit request, normally after Stop. Bound decoding, image
  size, inference, output count and bytes. Preserve actual media timestamps in a JSON manifest
  with content summaries and uncertainty; do not invent slide times or person identities.
- Profile Release builds with Instruments: CPU, allocations/leaks, resident-memory growth,
  energy, thermal state, disk throughput, dropped buffers and UI responsiveness. Record device,
  OS, capture modes and start/peak/end values. Hardware acceleration is not proof of low cost.
- For a two-hour requirement, run an actual two-hour capture including Stop/final flush and
  playback/readback. Accelerated synthetic tests establish invariants, not endurance. Test
  screen recording separately, plus low disk, interruption, sleep/lock and device/route changes.
  Respect a user's deferred long-test window and report unrun checks explicitly.

## Privacy, security and distribution

- Request microphone/screen access only for a clear user action. Use least-privilege sandbox
  entitlements and purpose strings; permission denial is a supported state. Never disable
  platform protections, edit TCC databases or silently expand capture to another source.
- Store secrets in Keychain, preferences in UserDefaults, and media in an appropriate local
  container or user-selected directory. Local storage is not automatically app-encrypted;
  document file protection, backup/export policy and possible cloud-sync destinations.
- Hold a security-scope lease through every asynchronous consumer. Balance successful access
  calls, handle stale bookmarks, and reauthorize visibly. Validate imported metadata paths,
  bounds and file types; do not follow arbitrary manifest URLs or traversal/symlink escapes.
- Treat audio, transcripts, OCR, images and model output as sensitive, untrusted data. Do not
  upload them as automatic telemetry. Keep logs free of content, secrets and private file paths.
  Third-party crash reporting needs reviewed collection/retention settings, sanitized context
  and the product's consent policy; disable automatic screenshots/session replay by default.
- Use Apple crash reports/TestFlight feedback and MetricKit where supported. MetricKit delivers
  payloads to the app; it is not a hosted analytics backend. Aggregate lightweight performance
  counters outside audio callbacks. Any cloud collection changes privacy disclosures.
- Verify StoreKit 2 transactions/current entitlements, observe updates, handle pending,
  cancellation, refund/revocation and Restore. Never persist an authoritative `isPurchased`
  Boolean. Display localized product pricing; keep purchase authorization separate from hardware
  model availability and from reading existing user exports.
- If an explicitly requested developer bypass is necessary, compile it only under
  `DEBUG && LOCAL_DEVELOPMENT && !APP_STORE`, with an explicit local-development build
  configuration; ordinary debug builds must not imply access. Keep it
  separate from verified purchase state; test that App Store builds cannot activate it.
  Never persist an authoritative unlock in UserDefaults, environment-derived state or files.
- Retain release archives/dSYMs, stable bundle identities and explicit signing configuration.
  Reconcile entitlements, usage descriptions, privacy manifests, required-reason APIs, third-party
  SDK behavior and App Store privacy answers. Never claim submission-ready from an unsigned build.

## Verification

- For native feature acceptance or release verification, use `/apple-verify`
  ([workflow](../skills/apple-verify/SKILL.md)); keep its detailed checks on demand.
- Probe the installed SDK and deployment target before broad implementation. Compile each
  target with Swift's strict concurrency checks; build iOS device and simulator variants.
  Do not suppress deprecations globally to conceal unsupported platform paths.
- Test state/cancellation, stale callbacks, per-source clocks, backpressure, persistence failure,
  corrupt/legacy files and recovery with meaningful negative controls. Drive the actual UI and
  confirm exports/media render and seek correctly; core coverage alone cannot prove capture.
- Simulator/model fixtures are not evidence for device speech, permissions, microphone echo
  reduction, other-app capture, background execution or real StoreKit purchases. Record the
  physical-device checks and remaining release blockers under the delivery contract.

Sources: [audio workgroups](https://developer.apple.com/documentation/audiotoolbox/understanding-audio-workgroups),
[security-scoped access](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()),
[MetricKit](https://developer.apple.com/documentation/metrickit),
[StoreKit entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements),
[App privacy](https://developer.apple.com/app-store/app-privacy-details/).
