//
//  ThingyConnection.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import Foundation
import Observation

/// The subset of ThingyPeripheral that ThingyConnection depends on.
/// A protocol seam so connection-state logic is testable with a mock —
/// CBPeripheral (and therefore ThingyPeripheral) cannot be instantiated
/// in unit tests.
@MainActor
protocol ThingyControlling: AnyObject {
    var advertisedName: String? { get }
    var isConnected: Bool { get }
    var delegate: ThingyDelegate? { get set }
    func connect()
    func disconnect()
    func turnOnLED()
    func turnOffLED()
}

extension ThingyPeripheral: ThingyControlling {}

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

    let peripheral: any ThingyControlling

    private(set) var state: ConnectionState = .connecting
    private(set) var ledSupported = false
    private(set) var buttonSupported = false
    private(set) var ledIsOn = false
    private(set) var buttonPressed = false

    var name: String { peripheral.advertisedName ?? "Unknown Device".localized }

    init(peripheral: any ThingyControlling) {
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

    func thingyDidConnect(ledSupported: Bool, buttonSupported: Bool) {
        state = .connected
        self.ledSupported = ledSupported
        self.buttonSupported = buttonSupported

        // Device supports neither LED nor button: nothing to show, disconnect.
        if !ledSupported && !buttonSupported {
            peripheral.disconnect()
        }
    }

    func thingyDidDisconnect() {
        state = .disconnected
    }

    func buttonStateChanged(isPressed: Bool) {
        buttonPressed = isPressed
    }

    func ledStateChanged(isOn: Bool) {
        ledIsOn = isOn
    }
}
