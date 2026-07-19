# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

nRFThingy52 is a SwiftUI iOS app that scans for and connects to a Nordic Thingy:52 BLE development
kit, and lets the user toggle its LED and observe its button state. There are no external
dependencies (no CocoaPods/Carthage/SPM) — everything is built on `CoreBluetooth`, `SwiftUI`, and
the `Observation` framework directly.

- Bundle ID: `com.armstrongmobile.nRFThingy52`
- Deployment target: iOS 17.0, Swift 5.0 language mode
- No package manager: do not add a Podfile/Cartfile/Package.swift without discussing it first — the
  project intentionally has zero third-party dependencies.
- The pre-migration UIKit/storyboard implementation is archived on branch `nRFThingy52UIKit`
  (deployment target 14.5). `main` is SwiftUI-only; see `SwiftUIMigrationPlan.md` for how it got here.

## Commands

Building/testing requires a full Xcode install (not just Command Line Tools) since this is a
`.xcodeproj`, not SPM.

```bash
# Build the app for the simulator
xcodebuild -project nRFThingy52.xcodeproj -scheme nRFThingy52 \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run all tests (unit + UI test targets)
xcodebuild -project nRFThingy52.xcodeproj -scheme nRFThingy52 \
  -destination 'platform=iOS Simulator,name=iPhone 15' test

# Run a single test class / method
xcodebuild -project nRFThingy52.xcodeproj -scheme nRFThingy52 \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:nRFThingy52Tests/ThingyConnectionTests test
```

If a bare device name is ambiguous across OS versions, pass a simulator UDID via `-destination
'id=<udid>'` (find one with `xcrun simctl list devices available`). There is no shared `.xcscheme`
checked in — Xcode auto-generates the `nRFThingy52` scheme on first open. Real BLE hardware (a
physical Thingy:52) is required to exercise the connect/LED/button flow — the simulator has no
Bluetooth radio, so the scanner shows its empty state there. New source files must be registered
in `project.pbxproj` (this is an old-format project, not a file-system-synchronized one).

## Architecture

SwiftUI app, three layers, all under `nRFThingy52/`:

1. **`ThingyApp`** (`@main`) — `WindowGroup { ScannerView() }` with the Nordic-blue global tint.
   Deliberately no opaque nav-bar color: on iOS 26, an opaque bar background (via
   `UINavigationBarAppearance` or `.toolbarBackground`) paints over the layer where SwiftUI draws
   the large title, so the app uses the native Liquid Glass bar. Do not reintroduce an opaque bar
   without re-testing the large title on an iOS 26 simulator.
2. **Views** (`Views/`) — `ScannerView` (NavigationStack root: `List` of discovered devices,
   `ContentUnavailableView` empty state, toolbar `ProgressView` while scanning,
   `navigationDestination(item:)` push) → `ThingyRowView` (name + RSSI icon) and
   `ThingyDetailView` (LED `Toggle`, button state row, `.sensoryFeedback` haptics, red tint when
   disconnected; connects `.onAppear`, disconnects `.onDisappear`).
3. **Models** (`Models/`) — all `@MainActor @Observable`:
   - **`ScannerModel`** owns the `CBCentralManager` (created lazily on first `startScan()` so the
     Bluetooth permission prompt fires at first scan) and is its *sole delegate for the app's
     lifetime*; it dedupes discoveries by peripheral identifier into `DiscoveredThingy` rows
     (1 s update throttle), and forwards didConnect/didFailToConnect/didDisconnect/state events
     to `selectedPeripheral`. CoreBluetooth delegate methods are `nonisolated` and hop via
     `MainActor.assumeIsolated` (safe: the manager is created with `queue: nil` = main queue).
   - **`ThingyConnection`** wraps one peripheral behind the **`ThingyControlling`** protocol
     (the seam that makes it unit-testable — `CBPeripheral` cannot be instantiated in tests),
     adopts `ThingyDelegate`, and republishes callbacks as observable state
     (`state`, `ledSupported`, `buttonSupported`, `ledIsOn`, `buttonPressed`). LED writes are
     optimistic and confirmed by the read-back.
   - **`ThingyPeripheral`** is the CoreBluetooth state machine (connect → discover services →
     discover characteristics → enable button notifications → read initial values), carried over
     from the UIKit app. It hard-codes the Thingy:52 UI service UUIDs (`EF680300`/`301`/`302`).
     Equality/hash are by `CBPeripheral.identifier`. Logging via `os.Logger` (subsystem = bundle
     id) — keep using `logger.debug`, not `print`.

**Utilities**: `StringExtension.swift` (`.localized`), `UIColorExtension.swift` (Nordic palette as
`UIColor`, covered by unit tests), `ColorExtension.swift` (SwiftUI `Color` bridge over the same
palette).

**Localization**: user-facing strings live in `Utilities/<lang>.lproj/Localizable.strings` across
16 locales. SwiftUI `Text("KEY")` resolves them automatically. When adding user-facing text, add
the English key and mirror it (English placeholder is fine) across all locale files — several
recent keys are still awaiting real translation.

**Tests** (`nRFThingy52Tests/`): utility tests plus `BLEModelTests.swift` — RSSI bucket
boundaries, scanner helpers, and a `MockThingy`-driven `ThingyConnection` state-machine suite.
Extend `MockThingy` rather than trying to mock CoreBluetooth types.

`nRFThingy52BLEStatus.md` tracks the code-review/fix history and the on-device test checklist
(hardware verification still pending a physical Thingy:52).
