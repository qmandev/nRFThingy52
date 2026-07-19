# nRFThingy52 — BLE Code Analysis & Status

*Analysis date: 2026-07-18. Reflects the current working tree (uncommitted changes included), on branch `main`.*
*Update 2026-07-18: all issues below — critical through low priority — have been fixed; see section 8.*

## 1. Overview

nRFThingy52 is a Swift/UIKit iOS app (deployment target iOS 14.5, Swift 5.0, no third-party
dependencies) that scans for a Nordic Thingy:52 over Bluetooth LE, connects to it, and exposes
two interactions: toggling the on-board LED and observing the physical button state. The app is
storyboard-driven with two screens inside a `UINavigationController`.

The BLE stack is built directly on `CoreBluetooth`, with all peripheral logic concentrated in a
single model class, `ThingyPeripheral`.

## 2. BLE Architecture

### GATT profile in use

`ThingyPeripheral` targets the Thingy:52 **User Interface Service**:

| Role | UUID |
|---|---|
| UI Service | `EF680300-9B35-4933-9B10-52FFA9740042` |
| LED characteristic | `EF680301-…0042` (write / write-without-response) |
| Button characteristic | `EF680302-…0042` (notify) |

The base-UUID format string `EF68%@-9B35-4933-9B10-52FFA9740042` plus `getUIServiceUUID()` /
`getLEDCharacteristicUUID()` / `getButtonCharacteristicUUID()` duplicate the same three static
UUIDs and are currently unused by the rest of the code. A commented-out block still carries the
old Nordic Blinky (`00001523-…`) UUIDs from the tutorial this code was adapted from.

### Connection lifecycle

The intended flow, driven by delegate callbacks inside `ThingyPeripheral`:

1. `connect()` — takes over as `CBCentralManager` delegate and calls `centralManager.connect(...)`.
2. `didConnect` → `discoverServices([nordicThingyServiceUUID])`.
3. `didDiscoverServices` → `discoverCharacteristics([led, button], for: service)`.
4. `didDiscoverCharacteristicsFor` — captures both characteristics; if the button characteristic
   exists, enables notifications on it; otherwise notifies the delegate immediately and reads LED state.
5. `didUpdateNotificationStateFor` (button) → `thingyDidConnect(...)` → initial `readButtonValue()` /
   `readLEDValue()`.
6. Value updates arrive via `didUpdateValueFor` and are routed to `ledStateChanged` /
   `buttonStateChanged` on the `ThingyDelegate`.

`ThingyPeripheral` abstracts all of this behind a four-method `ThingyDelegate` protocol, so view
controllers never touch `CoreBluetooth` types for the connected device.

### Scanner

`ScannerTableViewController` owns its own `CBCentralManager`, scans with
`CBCentralManagerScanOptionAllowDuplicatesKey: true` (needed for live RSSI updates), filters by the
Thingy UI service UUID, and dedupes discoveries using `ThingyPeripheral.isEqual` (compares
`CBPeripheral.identifier`). Repeat advertisements update the existing cell's name/RSSI, throttled
to once per second inside `ScannerTableViewCell`.

## 3. Screen Flow

- **`RootViewController`** (`UINavigationController` subclass) — Nordic-branded nav bar appearance,
  light/dark aware via `UIColor.dynamicColor(light:dark:)`.
- **`ScannerTableViewController`** — scan list; empty-state view (`emptyPeripheralsView`) animated
  in/out based on discovery count; row selection stops the scan and segues to the detail screen.
- **`ThingyViewController`** — receives the peripheral via `setPeripheral(_:)` from
  `prepare(for:sender:)`, connects in `viewWillAppear`, and mirrors LED/button state into a switch
  and labels; button presses trigger haptic feedback (`UIImpactFeedbackGenerator`).

## 4. Issues Found

### Critical

1. **Segue identifier mismatch — selecting a device will crash.**
   The storyboard defines the segue as `PushThingyView` (`Main.storyboard:54`), and
   `prepare(for:sender:)` / `shouldPerformSegue` check for `"PushThingyView"` — but
   `didSelectRowAt` calls `performSegue(withIdentifier: "PushThingyViewController", ...)`
   (`ScannerTableViewController.swift:161`). `performSegue` with an unknown identifier throws an
   `NSInvalidArgumentException` at runtime, so tapping a discovered device crashes the app.

2. **`ThingyViewController.viewDidAppear` disconnects immediately after connecting.**
   `viewWillAppear` calls `thingyPeripheral.connect()`, then `viewDidAppear` calls
   `thingyPeripheral.disConnect()` (`ThingyViewController.swift:57-60`). The result is that the
   connection is torn down moments after the screen appears — the LED/button UI can never reach a
   stable connected state. This almost certainly belongs in `viewWillDisappear`.

### High

3. **Wrong delegate method for write confirmation.**
   `ThingyPeripheral` implements `peripheral(_:didWriteValueFor descriptor:error:)` — the
   **descriptor** overload — intending to re-read the LED after a write-with-response
   (`ThingyPeripheral.swift:344`). Characteristic writes call the
   `didWriteValueFor characteristic:` overload, which is not implemented, so the post-write LED
   read never happens for `.withResponse` writes. (State still updates if the LED characteristic
   notifies/reads elsewhere, but the intended confirmation path is dead code.)

4. **Potential retain cycle via strong delegate.**
   `ThingyDelegate` is not class-bound and `public var delegate: ThingyDelegate?` is a strong
   reference (`ThingyPeripheral.swift:60`). `ThingyViewController` strongly holds
   `thingyPeripheral`, and the peripheral strongly holds the view controller back through
   `delegate`. Fix: `protocol ThingyDelegate: AnyObject` + `weak var delegate`.

### Medium

5. **`CBCentralManager` delegate hand-off is fragile.** The scanner and each `ThingyPeripheral`
   share one central manager but reassign its `delegate` at different lifecycle moments
   (`viewDidAppear` in the scanner, `connect()` in the peripheral). During transitions,
   central-level events (e.g., Bluetooth powering off) can be delivered to whichever object last
   claimed the delegate, not necessarily the one on screen.

6. **RSSI icon bucketing is inverted/overlapping.** In `ScannerTableViewCell.setupView`, the first
   branch `RSSI < -60 → rssi_2` swallows every weak signal (−90 dBm shows the same icon as
   −61 dBm), and the fallback `else → rssi_1` maps the *strongest* signals (≥ −30 dBm) to what is
   presumably the weakest-looking icon. The buckets need reordering (e.g., `< -80`, `< -60`,
   `< -40`, else strongest).

7. **`scanHexInt32` is deprecated** (`UIColorExtension.swift:41`, deprecated since iOS 13).
   `Scanner.scanInt32(representation: .hexadecimal)` or `UInt32(hex, radix: 16)` is the modern
   replacement. The `hexString` property also force-unwraps `cgColor.components` and assumes an
   RGB color space — grayscale/pattern colors would crash or misreport.

### Low / cleanup

8. Dead code: the unused base-UUID helper trio in `ThingyPeripheral` (lines 31-51), the
   commented-out Blinky UUIDs, and `ThingyViewController.centralManager` (declared, never used).
9. `pbxproj` naming: typo-prone API names — `disConnect()`, `reuseidentifer`,
   `writeLEDCharcateristic` — worth normalizing before the surface grows.
10. Logging is raw `print` throughout `ThingyPeripheral`; migrating to `os.Logger` (or at least
    `#if DEBUG`) would keep release builds quiet. (The stray scanner-state `print` was already
    removed in the working tree.)
11. `hapticGenerator` is stored as `NSObject?` and downcast at each use — the iOS 14.5 deployment
    target makes the old iOS-10 availability dance unnecessary; store it as
    `UIImpactFeedbackGenerator` directly.

## 5. Tests

Both test targets (`nRFThingy52Tests`, `nRFThingy52UITests`) contain only the Xcode template
stubs — there is effectively **zero test coverage**. `ThingyPeripheral`'s parsing/equality logic
(`parseAdvertisementData`, `isEqual`, RSSI bucketing) is the most testable surface if coverage is
added.

## 6. Localization

User-facing strings go through `String.localized` (`StringExtension.swift`) with
`Localizable.strings` files for ~16 locales under `Utilities/<lang>.lproj/`, plus per-locale
`Main.strings` for the storyboard. Keys in code: `"Unknown Device"`, `"ON"`, `"OFF"`,
`"PRESSED"`, `"RELEASED"`, `"Scanning..."`. The scanner's section header `"Nearby Devices"`
(`ScannerTableViewController.swift:153`) is **not** localized — the one inconsistency found.

## 7. Suggested Priority Order

1. Fix the segue identifier mismatch (crash on device selection). ✅ fixed
2. Move `disConnect()` out of `viewDidAppear` into `viewWillDisappear`. ✅ fixed
3. Replace the descriptor-write callback with the characteristic-write overload. ✅ fixed
4. Make `ThingyDelegate` class-bound with a `weak` delegate. ✅ fixed
5. Reorder RSSI buckets ✅ fixed; localize `"Nearby Devices"` ✅ fixed.
6. Delete dead code ✅; replace deprecated `scanHexInt32` ✅; adopt `os.Logger` ✅.

## 8. Fixes Applied (2026-07-18)

All issues from section 4 — critical, high, medium, and low — have been fixed. The critical
through medium fixes were committed to `main`; the low-priority pass is in the working tree.

### Critical

1. **Segue crash on device selection** (`ScannerTableViewController.swift`)
   `didSelectRowAt` now calls `performSegue(withIdentifier: "PushThingyView", ...)`, matching the
   storyboard segue and the identifier checked in `prepare(for:sender:)` / `shouldPerformSegue`.
   Selecting a device navigates to the Thingy screen and passes the peripheral correctly.

2. **Immediate disconnect after connect** (`ThingyViewController.swift`)
   The `thingyPeripheral.disConnect()` call moved from `viewDidAppear` to a new
   `viewWillDisappear` override. The connection now lives for the duration of the detail screen
   and tears down when the user navigates away. A cancelled back-swipe reconnects via the
   existing `viewWillAppear` guard on `isConnected`.

### High

3. **Dead write-confirmation callback** (`ThingyPeripheral.swift`)
   `peripheral(_:didWriteValueFor:error:)` now uses the **characteristic** overload (the previous
   code implemented the descriptor variant, which never fires for characteristic writes), guarded
   to the LED characteristic UUID. LED writes with response are now confirmed by a follow-up read.

4. **Retain cycle between view controller and peripheral** (`ThingyPeripheral.swift`)
   `ThingyDelegate` is now class-bound (`: AnyObject`) and `delegate` is declared `weak`. The
   view controller strongly owns the peripheral; the back-reference no longer pins the view
   controller in memory.

### Medium

5. **Central-manager delegate ownership consolidated** (`ScannerTableViewController.swift`,
   `ThingyPeripheral.swift`)
   The scanner is now the sole, permanent `CBCentralManager` delegate (assigned at creation via
   `CBCentralManager(delegate:queue:)` in `viewDidLoad`). `ThingyPeripheral.connect()` no longer
   reassigns the delegate. The scanner tracks the user-selected peripheral in a new
   `selectedPeripheral` property and forwards `centralManagerDidUpdateState`, `didConnect`, and
   `didDisconnectPeripheral` events to it (clearing it after disconnect). The scanner also only
   restarts scanning from a state-change callback when its view is on screen (`view.window != nil`),
   so Bluetooth power cycles during the detail screen no longer trigger a hidden background scan.

6. **RSSI icon buckets reordered** (`ScannerTableViewCell.swift`)
   Signal strength now maps monotonically to icons: `< -80` dBm → `rssi_1` (weakest),
   `-80…-60` → `rssi_2`, `-60…-40` → `rssi_3`, stronger → `rssi_4` (strongest).

7. **Deprecated / unsafe color helpers** (`UIColorExtension.swift`)
   `Scanner.scanHexInt32` (deprecated since iOS 13) replaced with `UInt32(hex, radix: 16)`.
   `hexString` now uses `getRed(_:green:blue:alpha:)` with a guard (returning `"#000000"` on
   failure) instead of force-unwrapping `cgColor.components`, so non-RGB colors no longer crash.

Also removed as part of the review: a leftover debug `print` of `centralManager.state` in the
scanner's `viewDidAppear`.

### Low priority (fixed in a follow-up pass, 2026-07-18)

8. **Dead code removed** (`ThingyPeripheral.swift`, `ThingyViewController.swift`)
   Deleted the unused base-UUID format string and helper trio (`getUIServiceUUID`,
   `getLEDCharacteristicUUID`, `getButtonCharacteristicUUID`, `getUUIDString`), the
   commented-out Nordic Blinky UUIDs, and the unused `ThingyViewController.centralManager`
   property along with its no-longer-needed `CoreBluetooth` import.

9. **Naming normalized**
   `disConnect()` → `disconnect()` (definition and both call sites),
   `writeLEDCharcateristic` → `writeLEDCharacteristic`, and
   `ScannerTableViewCell.reuseidentifer` → `reuseIdentifier` (including the dequeue site).

10. **Logging migrated to `os.Logger`** (`ThingyPeripheral.swift`, `ScannerTableViewController.swift`)
    All `print` calls replaced with `logger.debug(...)` — a static logger in `ThingyPeripheral`
    (category `ThingyPeripheral`) and an instance logger in the scanner (category `Scanner`),
    both under the app's bundle-identifier subsystem. Debug-level messages stay out of release
    console output and are filterable in Console.app. The `CBManagerState` interpolation uses
    `.rawValue` since the enum is not directly log-interpolatable.

11. **Localization gaps closed**
    The scanner's `"Nearby Devices"` section header now goes through `.localized`, and both
    `"Nearby Devices"` and `"Scanning..."` (used by `ThingyViewController` but previously missing
    from every strings file) were added to all 16 `Localizable.strings` files with English
    placeholder values, ready for translation.

12. **Haptics simplified** (`ThingyViewController.swift`)
    `hapticGenerator` is now stored as `UIImpactFeedbackGenerator?` directly instead of
    `NSObject?` with downcasts — the iOS-10 availability workaround was obsolete given the
    iOS 14.5 deployment target.

13. **First unit tests added** (`nRFThingy52Tests.swift`)
    Replaced the Xcode template stubs with six tests covering `UIColor(hexString:)` parsing
    (6-digit, 3-digit, alpha), `hexString` round-trip, `dynamicColor(light:dark:)` trait
    resolution, and the `String.localized` key fallback. `ThingyPeripheral`'s BLE logic remains
    untested (would require `CoreBluetooth` mocks); the UI test target is untouched.

### Ported from iOS-nRF-Blinky (2026-07-18)

A comparison with the sibling `iOS-nRF-Blinky` project (this app's original template) found two
fixes it had that this app lacked; both were ported:

14. **`hash` override paired with `isEqual`** (`ThingyPeripheral.swift`)
    `ThingyPeripheral` overrides `isEqual` (identity by `CBPeripheral.identifier`) but never
    overrode `hash`, violating the NSObject equality/hash contract. Added
    `override var hash: Int { basePeripheral.identifier.hashValue }` so peripherals behave
    correctly in `Set`/`Dictionary`/hashing contexts.

15. **Connection-failure handling** (`ThingyPeripheral.swift`, `ScannerTableViewController.swift`)
    `centralManager(_:didFailToConnect:error:)` was previously unimplemented, so a failed
    connection attempt left the Thingy screen stuck on "Scanning..." forever. The peripheral now
    logs the failure and notifies its delegate via `thingyDidDisconnect` (red disconnected UI),
    and the scanner forwards the event to `selectedPeripheral` (then clears it), consistent with
    the other central-manager event routing. Verified: simulator build and all 6 unit tests pass.

*Note: fixes were authored on a machine without full Xcode, so they were code-reviewed but not
compile-verified at the time of writing. Compile verification and partial runtime verification
were completed later the same day — see section 9.*

## 9. Test Status (2026-07-18)

Additional UI fixes verified this session (committed): the scanner's empty-state view was rebuilt
with proper Auto Layout constraints (labels previously overlapped and clipped on modern screens),
long hint labels now wrap, the scanning indicator hides when stopped, and the iOS 26 Liquid Glass
capsule behind the nav-bar indicator is suppressed via `hidesSharedBackground`.

### Verified ✅

**Toolchain / simulator (Xcode 26.3):**
- App builds cleanly for simulator and device; test bundles build with the new team (`7AVEYWK246`).
- All 6 unit tests pass on the iPhone 15 simulator.
- App runs on the iPhone 17 Pro simulator (iOS 26.3.1): empty-state layout renders correctly
  (centered, no overlap/clipping), no stray Liquid Glass capsule, spinner hidden while not
  scanning (simulator has no Bluetooth radio, so scanning never starts there).

**On device — "hardy Pond" (iPhone 13):**
- Install and launch succeed (both via `devicectl` and Xcode).
- Fresh install shows the Bluetooth permission prompt ("Allow nRFThingy52 to find Bluetooth
  devices?"); an overwrite install correctly does not re-prompt.
- After granting permission, scanning auto-starts from `centralManagerDidUpdateState` with no
  relaunch needed, and the white spinner animates in the nav bar while scanning.

### Pending — requires a physical Thingy:52 ⏳

1. Thingy:52 appears under "Nearby Devices" while advertising, with the RSSI icon strengthening
   as the phone moves closer (validates service-UUID scan filter and RSSI bucket fix).
2. Tapping the discovered device pushes the Thingy screen without crashing (segue-identifier fix).
3. LED switch toggles the physical LED both ways, and the label confirms ON/OFF via the
   read-back after write (characteristic write-callback fix).
4. Pressing/releasing the Thingy's button flips the label to PRESSED/RELEASED with a haptic tap
   (notification path).
5. Navigating back disconnects cleanly; re-selecting the device reconnects (viewWillDisappear
   lifecycle fix plus scanner-owned central-manager delegate forwarding).
6. Toggling Bluetooth off while on the Thingy screen shows the red disconnected state
   (state-change forwarding to the selected peripheral).
7. A failed connection attempt (e.g. powering the Thingy off right after tapping it) shows the
   red disconnected state instead of hanging on "Scanning..." (`didFailToConnect` port, item 15).

Re-run this checklist when a Thingy:52 is available and update this section with the results.

## 10. SwiftUI Migration (2026-07-19)

The app was migrated from UIKit/storyboards to SwiftUI on `main`, per `SwiftUIMigrationPlan.md`.
The UIKit implementation is archived on branch `nRFThingy52UIKit`. Deployment target moved from
iOS 14.5 to **iOS 17.0**.

**What changed:**
- `ThingyApp` (`@main`) + `ScannerView`/`ThingyRowView`/`ThingyDetailView` replaced the app/scene
  delegates, `Main.storyboard` (and its 16 `Main.strings` files), and all four view controllers.
- `ScannerModel` and `ThingyConnection` (`@MainActor @Observable`) replaced the view controllers'
  BLE-facing logic. `ThingyPeripheral` carried over unchanged apart from the `ThingyControlling`
  conformance (protocol seam for tests).
- All section-4 fixes survived the migration: sole-central-delegate forwarding (incl.
  `didFailToConnect`), 1 s row throttle, RSSI buckets (now the tested `RSSIBucket` enum),
  lazy manager creation preserving permission-prompt timing, connect-on-appear /
  disconnect-on-disappear lifecycle, optimistic LED write + read-back.
- **iOS 26 finding:** an opaque nav-bar background (via `UINavigationBarAppearance` or
  `.toolbarBackground`) paints over SwiftUI's large title on iOS 26 — verified by elimination on
  the iPhone 17 Pro (26.3.1) simulator. The app therefore uses the native Liquid Glass bar with a
  Nordic-blue tint instead of the UIKit app's opaque cyan bar. The old `hidesSharedBackground`
  workaround was deleted with the UIKit layer.

**Verified (SwiftUI build):**
- Simulator (iPhone 17 Pro, iOS 26.3.1): scanner + empty state render correctly in light and dark
  mode; large title and toolbar spinner behave; clean install works.
- Device (hardy Pond, iPhone 13): install/launch, large title, spinner animating while scanning,
  light/dark both fine (user-verified).
- 21 unit tests pass (6 utility + 15 new model tests: RSSI boundaries, scanner helpers,
  mock-driven `ThingyConnection` state machine).

**Still pending:** the section-9 hardware checklist (items 1–7) against a physical Thingy:52 —
all items re-apply unchanged to the SwiftUI build, plus one addition:

8. Back-swipe cancellation: `.onDisappear` fires later than `viewWillDisappear` did — verify a
   cancelled back-swipe followed by quick interaction doesn't race the reconnect logic.

## 11. Swift 6 Migration (2026-07-19)

The project moved from Swift 5 to **Swift 6 language mode** (all six build configurations), which
enforces strict concurrency as errors. Changes required:

- **`ThingyPeripheral` became `@MainActor`** with `@preconcurrency` conformances to
  `CBPeripheralDelegate`/`CBCentralManagerDelegate`. This is sound because the central manager is
  created with `queue: nil` (main-queue delivery); the `@preconcurrency` conformance adds a
  runtime main-thread assertion. Isolating the class also resolved the non-Sendable
  `static let CBUUID` properties (now MainActor-isolated).
- **NSObject `isEqual`/`hash`** are nonisolated requirements, so the overrides became
  `nonisolated` and compare a new `nonisolated let peripheralIdentifier: UUID` captured at init
  instead of touching the isolated `basePeripheral`.
- **`ThingyDelegate` and `ThingyControlling` became `@MainActor` protocols**, which deleted every
  `nonisolated` + `MainActor.assumeIsolated` bridge in `ThingyConnection`, and `ScannerModel`'s
  CB delegate methods became plainly isolated behind an `@preconcurrency` conformance — a net
  simplification (~40 lines of bridging removed).
- **Tests**: `MockThingy` became `@MainActor`; `ThingyConnectionTests` swapped its `setUp`
  override for a `makeSUT()` helper (a `@MainActor` test class cannot override the nonisolated
  `setUp`). The UI-test template methods gained `@MainActor` for `XCUIApplication` calls.

**Verified:** zero errors and zero Swift warnings across all three targets; all 21 unit tests
pass; simulator smoke test runs the CoreBluetooth startup path without tripping the runtime
assertions; device (hardy) build succeeds. On-device BLE interaction remains covered by the
section-9 checklist (unchanged).

## 12. CoreBluetoothMock Integration (2026-07-19)

Nordic's CoreBluetoothMock (SPM, up-to-next-major from 1.0.6 — the project's first and only
dependency; see `CoreBluetoothMockFeasibility.md` for the analysis) was integrated so the full
BLE pipeline is testable before the physical Thingy:52 arrives:

- `CoreBluetoothTypeAliases.swift` aliases `CBM*` types to CoreBluetooth names; app code is
  unchanged except `ScannerModel` now uses `CBCentralManagerFactory.instance(...)` (native on
  device, mock on simulator) and `ThingyPeripheral` compares peripherals by identifier
  (`CBMPeripheral` is a protocol, no `==`).
- `MockThingy52.swift` defines the simulated Thingy:52 (UI service `EF680300`, LED `0301`,
  Button `0302` with CCCD) plus the `ThingyMocks` facade (seeding, button press/release,
  power on/off, disconnect, LED state inspection). The app seeds it at launch on the simulator —
  the simulator app now discovers, connects to, and controls the mock Thingy interactively.
- `ThingyIntegrationTests.swift` — 7 end-to-end tests mapped to the §9 checklist: discovery
  (item 1), connect/discover pipeline (2), LED write + read-back (3), button notifications (4),
  on-demand disconnect (5), Bluetooth power-off (6), and peripheral-initiated disconnect
  (7 variant). One instructive failure during bring-up: tests that dropped the `ScannerModel`
  lost disconnect events — correct behavior, since the scanner is the sole central delegate and
  forwards those events; tests now hold it via `withExtendedLifetime`.

**Result: 28/28 tests pass** (6 utility + 15 model + 7 integration). Simulator and hardy device
builds both succeed. The §9 checklist now serves as hardware *confirmation* of behavior already
verified against the mock — items 1–7 have simulator-level coverage; item 8 (back-swipe timing)
remains UI-level.
