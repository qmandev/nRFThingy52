# nRFThingy52 — BLE Code Analysis & Status

*Analysis date: 2026-07-18. Reflects the current working tree (uncommitted changes included), on branch `main`.*

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

1. Fix the segue identifier mismatch (crash on device selection).
2. Move `disConnect()` out of `viewDidAppear` into `viewWillDisappear`.
3. Replace the descriptor-write callback with the characteristic-write overload.
4. Make `ThingyDelegate` class-bound with a `weak` delegate.
5. Reorder RSSI buckets; localize `"Nearby Devices"`.
6. Delete dead code; replace deprecated `scanHexInt32`; adopt `os.Logger`.
