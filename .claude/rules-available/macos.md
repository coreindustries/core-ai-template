---
paths:
  - "**/*.{swift,entitlements,xcconfig,plist}"
  - "**/Package.swift"
  - "**/*.xcodeproj/**"
  - "**/*.xcworkspace/**"
---

# macOS Native App Rules

**Scope:** native macOS apps in Swift (SwiftUI, with AppKit where SwiftUI falls short). Loads only when a Swift, Xcode or entitlements file is touched, so it costs no always-loaded context. Language-level Swift patterns (concurrency, `@Observable`, Keychain, testing) live in `ios.md`; enable both (`make enable-ios enable-macos`) for a shared-code iOS + macOS project. This file covers only what differs on the Mac.

## Quick Reference

- **UI**: SwiftUI first (`WindowGroup`, `Settings`, `MenuBarExtra`, `commands`); AppKit via `NSViewRepresentable` / `NSApplicationDelegateAdaptor` only for what SwiftUI cannot do.
- **Sandbox**: App Sandbox on for every distributable build. Each entitlement is a reviewed decision, requested at the narrowest scope.
- **Hardened Runtime**: on for every build that is notarized (required for Developer ID distribution).
- **Dependencies**: Swift Package Manager only, exact versions, `Package.resolved` committed.
- **Build and test**: `xcodebuild` or `swift build` / `swift test`, never an IDE-only step. CI must reproduce it.

## 1. Sandbox and entitlements

- Entitlements live in a committed `*.entitlements` file. A diff that adds one (network client/server, file access, `com.apple.security.cs.*`, Apple Events) must say in the PR why the narrower option is not enough.
- Prefer user-selected file access (`com.apple.security.files.user-selected.read-write`) with security-scoped bookmarks over broad paths. Never request `com.apple.security.files.all` or disable the sandbox to make something work.
- `com.apple.security.cs.disable-library-validation`, `allow-unsigned-executable-memory` and `allow-jit` weaken Hardened Runtime. Require a stated, specific need and an ADR (`/adr`).
- Entitlements that differ between Debug and Release are a smell: the app you test is not the app you ship.

## 2. Signing and notarization — no secrets on disk

`.claude/rules/secrets-hygiene.md` applies in full. Signing material is a secret, so:

- **Never commit** `.p12`, exported private keys, `.p8` API keys, provisioning profiles for distribution, or Sparkle private keys. Add them to `.gitignore` and treat a finding as a leak (`docs/runbooks/secret-leak.md`).
- **Local**: the signing identity lives in the login Keychain. Notarize with a stored profile (`xcrun notarytool store-credentials`), not a password on the command line.
- **CI**: inject the certificate and API key at the step level from the secret store, import into a throwaway keychain (`security create-keychain` → `import` → `set-key-partition-list`), and delete the keychain in an `if: always()` step. The runner must be a fresh or cleaned machine; do not leave signing material on a persistent runner.
- Order of a release build: build → sign (`codesign --options runtime --timestamp`) → `notarytool submit --wait` → `stapler staple` → verify (`spctl --assess --type execute`, `codesign --verify --deep --strict`). A release PR attaches the `spctl` output as Real Proof (`delivery-contract.md`).
- Sparkle (or any updater): the EdDSA private key stays in the Keychain or the CI secret store; only the public key ships in `Info.plist`. Serve the appcast over HTTPS and verify update signatures; an unsigned update channel is a remote-code-execution path.

## 3. Platform behavior that differs from iOS

| Area | macOS rule |
|------|-----------|
| Windows | Support resizing, multiple windows and full-screen. Persist frame via `@SceneStorage` / `defaultSize`, not hard-coded sizes. |
| Menus and keyboard | Every action reachable by menu command and a shortcut via `commands { }`. Respect system shortcuts. |
| Lifecycle | Handle `applicationShouldTerminate`; flush state before quit. A menu-bar app sets `LSUIElement` deliberately. |
| Permissions (TCC) | Request Camera, Microphone, Accessibility, Full Disk Access, Screen Recording only at point of use, with a usage string in `Info.plist`, and handle denial. |
| Background work | Use `SMAppService` for login items and helpers, not deprecated `SMLoginItemSetEnabled` or LaunchAgents written by hand. |
| Files | Use `FileManager` URLs from `.applicationSupportDirectory` / `.cachesDirectory`; never write into the app bundle. |
| Architectures | Build universal (`arm64` + `x86_64`) unless the deployment target is explicitly Apple-silicon only. State the minimum macOS version in one place (`MACOSX_DEPLOYMENT_TARGET`). |
| Secrets | Keychain (`kSecClassGenericPassword`), never `UserDefaults` or a plist. See `ios.md` § Keychain. |

## 4. Dependencies and builds

- Swift Package Manager: pin exact versions (`exact: "1.2.3"` or "Exact Version" in Xcode), commit `Package.resolved`, and resolve from it only: `xcodebuild -disableAutomaticPackageResolution` / `swift package resolve` then `swift build --disable-automatic-resolution`.
- The 3-day cooldown and review checklist in `dependency-security.md` apply to Swift packages. Check a package's maintainers and its build plugins: a plugin runs code at build time, like an npm install script.
- Binary targets (`.binaryTarget`) must pin a checksum. Reject one without.
- Dependabot supports the `swift` ecosystem; enable it in `.github/dependabot.yml`.

## 5. Testing and CI

- Unit tests with Swift Testing (`import Testing`) or XCTest; UI tests with XCUITest. Keep UI logic in testable view models so most tests need no UI host.
- Run tests from the command line: `xcodebuild test -scheme <Scheme> -destination 'platform=macOS'`. Treat build warnings in your own targets as errors in CI (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`).
- CI runs on a macOS runner job you add to your workflow. Pin the runner image (`macos-15`, not `macos-latest`) and the Xcode version (`xcode-select` / `DEVELOPER_DIR`) so a runner image update cannot change a build.
- Lint with SwiftLint and format with swift-format, both configured in-repo and run in CI. Fix root causes before disabling a rule.
- UI changes follow `.claude/rules/ui-qa-gate.md`: attach a real screenshot of the running app.

## 6. Anti-patterns

| Anti-pattern | Fix |
|-------------|-----|
| Disabling the sandbox "for now" | Request the specific entitlement and document why |
| Signing identity or API key in the repo or a CI log | Keychain locally, step-scoped secret + throwaway keychain in CI |
| `latest` Xcode / runner image in CI | Pin both |
| Writing user data under the app bundle or `/Library` | `Application Support` for the user |
| Polling for state in a timer | Observe (`@Observable`, `NotificationCenter`, `NSWorkspace` notifications) |
| Blocking the main thread with file or network work | `async/await`, `@MainActor` only for UI mutation |
| Shipping without notarization and stapling | Fail the release job unless `spctl --assess` passes |

## See Also

- `.claude/rules-available/ios.md` — shared Swift, SwiftUI, concurrency and Keychain patterns
- `.claude/rules/secrets-hygiene.md`, `.claude/rules/dependency-security.md`, `.claude/rules/delivery-contract.md`
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) · [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
