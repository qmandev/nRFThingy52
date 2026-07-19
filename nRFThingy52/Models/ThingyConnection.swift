//
//  ThingyConnection.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import Foundation
import Observation

/// Observable connection state for one Thingy, for the SwiftUI detail screen.
/// Adopts ThingyDelegate and republishes the callbacks as observable
/// properties, replacing the UIKit ThingyViewController's delegate methods
/// and their DispatchQueue.main.async hops.
@MainActor
@Observable
final class ThingyConnection {

    enum ConnectionState {
        case connecting
        case connected
        case disconnected
    }

    let peripheral: ThingyPeripheral

    private(set) var state: ConnectionState = .connecting
    private(set) var ledSupported = false
    private(set) var buttonSupported = false
    private(set) var ledIsOn = false
    private(set) var buttonPressed = false

    var name: String { peripheral.advertisedName ?? "Unknown Device".localized }

    init(peripheral: ThingyPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
    }

    // MARK: - Public API

    func connect() {
        guard !peripheral.isConnected else { return }
        state = .connecting
        peripheral.connect()
    }

    func disconnect() {
        peripheral.disconnect()
    }

    /// Sets the LED optimistically; the value is confirmed (or corrected)
    /// by the read-back that arrives via ledStateChanged.
    func setLED(on: Bool) {
        ledIsOn = on
        on ? peripheral.turnOnLED() : peripheral.turnOffLED()
    }
}

// MARK: - Hashable (identity-based, for navigationDestination(item:))

extension ThingyConnection: Hashable {

    nonisolated static func == (lhs: ThingyConnection, rhs: ThingyConnection) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: - ThingyDelegate

extension ThingyConnection: ThingyDelegate {

    nonisolated func thingyDidConnect(ledSupported: Bool, buttonSupported: Bool) {
        MainActor.assumeIsolated {
            state = .connected
            self.ledSupported = ledSupported
            self.buttonSupported = buttonSupported

            // Device supports neither LED nor button: nothing to show, disconnect.
            if !ledSupported && !buttonSupported {
                peripheral.disconnect()
            }
        }
    }

    nonisolated func thingyDidDisconnect() {
        MainActor.assumeIsolated {
            state = .disconnected
        }
    }

    nonisolated func buttonStateChanged(isPressed: Bool) {
        MainActor.assumeIsolated {
            buttonPressed = isPressed
        }
    }

    nonisolated func ledStateChanged(isOn: Bool) {
        MainActor.assumeIsolated {
            ledIsOn = isOn
        }
    }
}
