# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

nRFThingy52 is a SwiftUI iOS app that scans for and connects to a Nordic Thingy:52 BLE development
kit, and lets the user toggle its LED and observe its button state. Built on `SwiftUI`, the
`Observation` framework, and CoreBluetooth via Nordic's **CoreBluetoothMock** — the project's
single dependency (SPM, up-to-next-major from 1.0.6). `CBCentralManagerFactory` returns native
CoreBluetooth on physical devices and a simulated stack on the simulator, where a mock Thingy:52
(`MockThingy52.swift`) is seeded at launch so the full scan→connect→LED→button flow works without
hardware. Do not add further dependencies without discussing first.

- Bundle ID: `com.armstrongmobile.nRFThingy52`
- Deployment target: iOS 17.0, **Swift 6 language mode** (strict concurrency is enforced —
  data-race safety errors, not warnings). Keep new code warning-free under it.
- The CoreBluetooth type names in app code (`CBCentralManager`, `CBPeripheral`, …) are aliases to
  `CBM*` types, declared in `CoreBluetoothTypeAliases.swift`. **Do not `import CoreBluetooth` in
  app or test files** — it collides with the aliases; the aliases (plus
  `import CoreBluetoothMock` where CBM-specific API is needed) cover everything. Note
  `CBPeripheral` is a *protocol* (`CBMPeripheral`) in this world: compare peripherals by
  `identifier`, never `==`.
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
     to `selectedPeripheral`.
   - **`ThingyConnection`** wraps one peripheral behind the **`ThingyControlling`** protocol
     (the seam that makes it unit-testable — `CBPeripheral` cannot be instantiated in tests),
     adopts `ThingyDelegate`, and republishes callbacks as observable state
     (`state`, `ledSupported`, `buttonSupported`, `ledIsOn`, `buttonPressed`). LED writes are
     optimistic and confirmed by the read-back.
   - **`ThingyPeripheral`** is the CoreBluetooth state machine (connect → discover services →
     discover characteristics → enable button notifications → read initial values), carried over
     from the UIKit app. It is `@MainActor` too. It hard-codes the Thingy:52 UI service UUIDs
     (`EF680300`/`301`/`302`). Equality/hash are by peripheral identifier (kept in a
     `nonisolated let` because the NSObject `isEqual`/`hash` requirements are nonisolated).
     Logging via `os.Logger` (subsystem = bundle id) — keep using `logger.debug`, not `print`.

   **Concurrency pattern**: everything is MainActor-isolated, which is *sound because the central
   manager is created with `queue: nil`* (all CoreBluetooth callbacks arrive on the main queue).
   The CB delegate conformances are declared `@preconcurrency` so isolated methods satisfy the
   nonisolated protocol requirements, with a runtime main-thread assertion as the safety net.
   If you ever move CoreBluetooth off the main queue, this pattern must be redesigned — do not
   just silence the assertion. `ThingyDelegate` and `ThingyControlling` are `@MainActor`
   protocols.

**Utilities**: `StringExtension.swift` (`.localized`), `UIColorExtension.swift` (Nordic palette as
`UIColor`, covered by unit tests), `ColorExtension.swift` (SwiftUI `Color` bridge over the same
palette).

**Localization**: user-facing strings live in `Utilities/<lang>.lproj/Localizable.strings` across
16 locales. SwiftUI `Text("KEY")` resolves them automatically. When adding user-facing text, add
the English key and mirror it (English placeholder is fine) across all locale files — several
recent keys are still awaiting real translation.

**Tests** (`nRFThingy52Tests/`): utility tests, `BLEModelTests.swift` (RSSI bucket boundaries,
scanner helpers, `MockThingy`-driven `ThingyConnection` state machine), and
`ThingyIntegrationTests.swift` — end-to-end BLE pipeline tests against the simulated Thingy:52
(simulator-only; they drive `ScannerModel` → `ThingyConnection` → `ThingyPeripheral` through the
mock). Test controls live in the `ThingyMocks` facade (app target) so the test target never
imports CoreBluetoothMock directly. When writing integration tests, keep the `ScannerModel`
alive for the whole test (`withExtendedLifetime`) — disconnect/power events flow through it.

`nRFThingy52BLEStatus.md` tracks the code-review/fix history and the on-device test checklist
(hardware verification still pending a physical Thingy:52).
