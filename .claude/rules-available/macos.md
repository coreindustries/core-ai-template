---
paths:
  - "**/*.swift"
  - "**/*.xcodeproj/**"
  - "**/*.entitlements"
  - "**/*.plist"
---

# Native macOS

Enable with `make enable-macos`; also applies [shared Apple rules](apple-native.md).

- Use SwiftUI with AppKit adapters where native window lifecycle, menus, panels or AVKit need
  them. Keep one recording owner across windows/menu-bar controls. Compact/expanded views must
  not create another capture session or reset recording state; preserve intended window geometry.
- Use public ScreenCaptureKit selection/capture APIs available to the deployment target.
  Validate a selected region against its original display and scale before each capture;
  never substitute another display silently. Audio-only capture must not save screen pixels.
- Microphone and Screen & System Audio Recording approvals are separate. Check the actual
  capture operation, not just an old UI toggle. Explain denied/revoked access and show the
  relevant System Settings route. Do not request permissions repeatedly from refresh loops.
- Keep development app path, bundle identifier and signing identity stable where practical.
  Ad-hoc rebuilds can change code identity and invalidate privacy approvals; diagnose identity
  before telling people to grant access again. Never promise ad-hoc permission persistence.
- Treat microphone echo reduction as measured signal processing. Test speaker playback,
  simultaneous local speech and route changes. Raw waveform subtraction without alignment,
  acoustic-path estimation and drift handling is not reliable echo cancellation. Headphones
  and native voice processing have different tradeoffs; show the active mode honestly.
- Separate mic/system tracks identify input channels, not individual people. Preserve overlapping
  timestamps. A conferencing app's mute does not necessarily mute this recorder's microphone.
- Use sandbox bookmarks for persistent user-selected output access. Keep leases alive through
  saving, playback, recovery and AI exports. Never rely on an absolute path as authorization.
- Stop and detach players/observers when replacing a session or leaving playback. Opening a
  recording should not autoplay or start capture. Validate actual AVKit linking in the app
  executable; a typecheck or differently linked test harness cannot establish launch success.
- Test the signed app bundle, not only `swift run`: launch/quit/reopen, permission denial and
  revocation, multi-display geometry, sleep/device changes, save/open/export and native playback.
  Archive/signing/notarization or Mac App Store sandbox checks remain separate release gates.

Sources: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit),
[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox),
[crash and diagnostic reports](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs).
