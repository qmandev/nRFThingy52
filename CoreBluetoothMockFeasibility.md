# CoreBluetoothMock Feasibility Analysis — nRFThingy52

*2026-07-19. Analyzed local clone at `/Users/armstrongllc/Desktop/BLE/IOS-CoreBluetooth-Mock`
(nordicsemi/IOS-CoreBluetooth-Mock, v1.0.6, BSD-3-Clause).*

## Verdict: highly feasible — near-purpose-built for this app

The library's bundled example app **is nRF Blinky** — the exact codebase nRFThingy52 was adapted
from. It ships a `BlinkyCBMPeripheralSpecDelegate` that simulates precisely our interaction
surface (LED read/write, button notifications), and even an advertising-only "Thingy:52" spec.
Adapting the Blinky spec to the Thingy:52 UI service UUIDs (`EF6803xx`) is mechanical.

## How the library works

- Drop-in `CBM*` types (`CBMCentralManager`, `CBMPeripheral`, …) mirror the CoreBluetooth API.
  `CBMCentralManagerFactory.instance(delegate:queue:forceMock:)` returns a **native passthrough**
  on physical devices and a **mock** on the simulator — same app binary, real BLE on hardware.
- The example's `CoreBluetoothTypeAliases.swift` pattern (`typealias CBCentralManager =
  CBMCentralManager`, …) means app code keeps CoreBluetooth names; only the import and the
  manager construction change.
- Mock peripherals are declared as `CBMPeripheralSpec`s (advertisement, services,
  characteristics) plus a `CBMPeripheralSpecDelegate` that answers read/write/notify requests —
  i.e., a tiny simulated firmware.
- Simulation controls: `simulatePeripherals`, `simulatePowerOn/Off`, `simulateConnection`,
  `simulateDisconnection(withError:)`, `simulateValueUpdate` (notifications),
  `simulateProximityChange` (RSSI!), `simulateReset`, `tearDownSimulation`.
- Callbacks are delivered on the queue passed at creation (default main) — **our `@MainActor` +
  `@preconcurrency` architecture stays sound unchanged**.

## Integration cost (small)

1. **Add the dependency** — SPM package on the **app target** (required: `ThingyPeripheral`/
   `ScannerModel` compile against the CB types, and on-device builds need the native
   passthrough). This is the one policy decision: the project is deliberately zero-dependency
   (CLAUDE.md), so this needs sign-off. Mitigations: it's Nordic first-party, BSD-3, actively
   maintained, has a privacy manifest, and the alternative — vendoring the ~20 source files into
   the project — is viable if we prefer to stay SPM-free.
2. **`CoreBluetoothTypeAliases.swift`** — copy from the example (~40 lines of typealiases).
3. **Two construction changes** — `ScannerModel.startScan()` uses
   `CBCentralManagerFactory.instance(delegate: self, queue: nil)`; nothing else in the models
   changes names thanks to the aliases.
4. **`MockThingy52.swift`** — a `CBMPeripheralSpec` for the Thingy:52 UI service modeled on the
   example's Blinky spec (~100 lines): advertises `nordicThingyServiceUUID`, LED characteristic
   (read/write), button characteristic (notify), spec delegate holding LED/button state.
5. **Swift 6 note** — the package declares `swiftLanguageVersions: [.v5]`, so it compiles in
   Swift 5 mode (dependencies build in their own language mode; no strict-concurrency errors
   from it). Our code consuming it keeps the existing `@preconcurrency` conformance pattern
   against the `CBM` delegate protocols.

## What it unlocks (maps to status doc §9 checklist)

| §9 item | Mock capability |
|---|---|
| 1. Discovery + RSSI icons | `simulatePeripherals` + `simulateProximityChange` (near/immediate/far → RSSI buckets) |
| 2. Tap → push → connect | connectable spec; full connect → discover → notify → read pipeline runs for real |
| 3. LED toggle + read-back | spec delegate `didReceiveWriteRequestFor`/`didReceiveReadRequestFor` |
| 4. Button PRESSED/RELEASED | `simulateValueUpdate` on the button characteristic |
| 5. Back-nav disconnect / re-select reconnect | `simulateDisconnection`, reconnect flow |
| 6. Bluetooth off → red state | `simulatePowerOff` |
| 7. Connection failure | out-of-range proximity / `simulateReset` during connect |
| 8. Back-swipe timing | exercisable in simulator UI tests against the mock |

Concretely: an XCTest integration suite driving `ScannerModel` + `ThingyConnection` +
`ThingyPeripheral` end-to-end against the simulated Thingy — the entire BLE pipeline that
currently has zero coverage — runs on the simulator in CI. The hardware pass in §9 remains
worthwhile as final radio-level truth, but stops being the only verification path.

## Risks / caveats

- **Dependency policy** — the only real blocker; needs an explicit decision (SPM vs. vendoring).
- The mock replaces CoreBluetooth *in the app target*; on devices it passes through to native
  CB, but the passthrough layer is now in the production code path (Nordic uses this in shipping
  apps; still worth noting).
- `CBMCentralManagerMock` state is process-global (`simulatePeripherals` /
  `tearDownSimulation`) — integration tests must set up/tear down carefully to stay isolated.
- Unit tests currently instantiate nothing CB-backed; after integration, tests on the simulator
  get the mock automatically (factory returns mock on simulator), which is exactly what we want.

## Recommended next steps

1. Decide SPM vs. vendoring (recommendation: **SPM**, pinned to `1.0.6`).
2. Integrate aliases + factory swap; verify app still builds/runs on simulator and hardy.
3. Write `MockThingy52` spec + an integration test suite covering §9 items 1–7.
4. Record results in `nRFThingy52BLEStatus.md`; keep §9 as the hardware-confirmation pass.
