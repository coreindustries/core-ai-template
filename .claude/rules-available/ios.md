---
paths:
  - "**/*.swift"
  - "**/*.xcodeproj/**"
  - "**/*.entitlements"
  - "**/*.plist"
---

# Native iOS and iPadOS

Enable with `make enable-ios`; also applies [shared Apple rules](apple-native.md).

- Prefer SwiftUI and small views with one observable state owner. Use Observation for new
  supported targets, retaining ObservableObject where existing shared code owns behavior.
  Bridge UIKit/AVKit only for native capabilities the SwiftUI surface lacks.
- Support touch-sized controls, Dynamic Type, VoiceOver, safe areas, rotation, compact width
  and iPad multitasking. Use adaptive navigation/layouts rather than desktop fixed widths.
  Changing presentation or entering background must not accidentally start another recording.
- Use AVAudioSession as the authority for microphone route/category/mode/activation. Choose
  mixing, Bluetooth, voice processing and speaker routing intentionally, then verify on device.
  Observe interruptions, route changes and media-services resets. Preserve outputs and surface
  stopped/incomplete sessions; do not automatically resume sensitive recording without an
  explicit product policy and authorized user intent.
- Declare only background modes the feature actually needs. Background audio/screen capture
  and finite finalization time have different rules; BGTaskScheduler does not grant unlimited
  live recording or inference time. Test lock, app switching, calls and forced termination.
- Gate capture by SDK/runtime capabilities. On iOS 27+, ScreenCaptureKit uses Apple's content
  sharing picker; retain its selected filter and respect the person's microphone selection.
  Do not port macOS display/app filter constructors, region/sourceRect controls, queue-depth
  or frame-interval settings without verifying iOS API availability. Throttle downstream
  video work with bounded storage when capture rate cannot be configured.
- For older deployment targets, design the supported microphone/import experience or an
  explicitly scoped ReplayKit path. Do not infer arbitrary other-app/call audio capture from
  macOS behavior; protected content and microphone contention can prevent it. Screen capture
  support on a physical device does not imply the simulator has the same framework or behavior.
- Use document/file pickers and balanced security-scope access for imports/exports. Coordinate
  provider-backed files; handle downloads, loss of access and cancellation. Keep durable media
  out of purgeable caches. Choose data-protection/backup classes compatible with the documented
  locked-device recording behavior; do not silently upload a local-only app's recordings.
- Use Keychain for secrets; never UserDefaults or a shipped developer key. Keep ATS protections
  enabled and validate deep links/imported metadata. Use FileManager for media, SwiftData/Core
  Data when structured storage warrants it; do not add a database just to store recording files.
- Compile both generic iOS device and simulator targets. Test shared logic with Swift Testing
  or XCTest, UI with XCUITest, and media/permissions/background behavior on an actual iPhone
  and iPad. Local speech and Apple Intelligence require runtime availability checks even when
  the OS version is supported. Record test hardware and language/model-asset state.
- Test StoreKit with the Xcode scheme's configuration and sandbox/TestFlight as separate
  environments. A verified fixture entitlement is not a production purchase or App Store
  Connect product setup. Preserve native purchase/restore/error states and device eligibility.

Sources: [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession),
[iOS screen capture](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios),
[background modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes),
[document access](https://developer.apple.com/documentation/uikit/providing-access-to-directories).
