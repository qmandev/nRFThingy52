# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

nRFThingy52 is an iOS app (Swift, UIKit, storyboards) that scans for and connects to a Nordic Thingy:52 BLE
development kit, and lets the user toggle its LED and observe its button state. There are no external
dependencies (no CocoaPods/Carthage/SPM) — everything is built on `CoreBluetooth` and `UIKit` directly.

- Bundle ID: `com.armstrongmobile.nRFThingy52`
- Deployment target: iOS 14.5, Swift 5.0
- No package manager: do not add a Podfile/Cartfile/Package.swift without discussing it first — the project
  intentionally has zero third-party dependencies.

## Commands

Building/testing requires a full Xcode install (not just Command Line Tools) since this is a `.xcodeproj`,
not SPM.

```bash
# Build the app for the simulator
xcodebuild -project nRFThingy52.xcodeproj -scheme nRFThingy52 \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run all tests (unit + UI test targets)
xcodebuild -project nRFThingy52.xcodeproj -scheme nRFThingy52 \
  -destination 'platform=iOS Simulator,name=iPhone 15' test

# Run a single test method
xcodebuild -project nRFThingy52.xcodeproj -scheme nRFThingy52 \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:nRFThingy52Tests/nRFThingy52Tests/testExample test
```

There is no shared `.xcscheme` checked into the repo, so the `nRFThingy52` scheme must be present/enabled in
your local Xcode user data (Xcode auto-generates it on first open) before `xcodebuild -list` or the commands
above will find it. Real BLE hardware (a physical Thingy:52) is required to exercise the connect/LED/button
flow — the simulator has no Bluetooth radio.

## Architecture

The app is a two-screen flow driven by a storyboard (`Base.lproj/Main.storyboard`) with segue
`PushThingyViewController`, wrapped in a single `UINavigationController` (`RootViewController`):

1. **`ScannerTableViewController`** — owns a `CBCentralManager`, scans for peripherals advertising
   `ThingyPeripheral.nordicThingyServiceUUID`, and lists them in a table (`ScannerTableViewCell`, showing name
   + RSSI bucket icon). Selecting a row stops the scan and segues to the Thingy detail screen, passing the
   selected `ThingyPeripheral`.
2. **`ThingyViewController`** — receives a `ThingyPeripheral` via `setPeripheral(_:)`, connects to it on
   `viewWillAppear`, and disconnects on `viewDidAppear` (the peripheral has already been used to display
   state by then — see note below), sets itself as the peripheral's `ThingyDelegate`, and reflects LED/button
   state in the UI. Toggling the LED switch calls `thingyPeripheral.turnOnLED()`/`turnOffLED()`.

**`ThingyPeripheral` (Models/ThingyPeripheral.swift)** is the core abstraction: it wraps a `CBPeripheral` +
`CBCentralManager` pair and implements both `CBCentralManagerDelegate` and `CBPeripheralDelegate` itself,
exposing a much simpler `ThingyDelegate` protocol (`thingyDidConnect`, `thingyDidDisconnect`,
`buttonStateChanged`, `ledStateChanged`) to its own delegate (the view controller). It hard-codes the Thingy:52
UI service/characteristic UUIDs (`EF680300`/`301`/`302`-family) and drives the connect → discover services →
discover characteristics → enable notifications → read initial values sequence. Equality (`isEqual`) is by
peripheral `identifier`, which `ScannerTableViewController` relies on to dedupe repeated advertisement
callbacks and instead push RSSI/name updates into the existing table cell (`peripheralUpdatedAdvertisementData`).

**Utilities**: `StringExtension.swift` adds `.localized`; `UIColorExtension.swift` defines the Nordic brand
color palette (`nordicBlue`, `nordicRed`, etc.) plus a light/dark `dynamicColor(light:dark:)` helper used by
`RootViewController` for the nav bar appearance.

**Localization**: strings live in per-locale `.strings` files under `Utilities/<lang>.lproj/Localizable.strings`
and storyboard strings under `<lang>.lproj/Main.strings` at the top level — over a dozen languages are
supported. When adding user-facing text, add the base English key and mirror it (or leave it for translation)
across the other locale files rather than hardcoding strings in view controllers.
