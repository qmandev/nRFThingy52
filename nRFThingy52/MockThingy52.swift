//
//  MockThingy52.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//
//  A simulated Thingy:52 for the CoreBluetoothMock layer, modeled on the
//  Blinky spec in Nordic's example. Active only where the mock manager is
//  used (the simulator); physical devices talk to real CoreBluetooth.
//

import Foundation
import CoreBluetoothMock

// MARK: - UUIDs (same values ThingyPeripheral scans for)

private extension CBMUUID {
    @MainActor static let thingyUIService         = CBMUUID(string: "EF680300-9B35-4933-9B10-52FFA9740042")
    @MainActor static let thingyLEDCharacteristic = CBMUUID(string: "EF680301-9B35-4933-9B10-52FFA9740042")
    @MainActor static let thingyButtonCharacteristic = CBMUUID(string: "EF680302-9B35-4933-9B10-52FFA9740042")
}

private extension CBMCharacteristicMock {
    @MainActor static let thingyLED = CBMCharacteristicMock(
        type: .thingyLEDCharacteristic,
        properties: [.write, .read]
    )
    @MainActor static let thingyButton = CBMCharacteristicMock(
        type: .thingyButtonCharacteristic,
        properties: [.notify, .read],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )
}

private extension CBMServiceMock {
    @MainActor static let thingyUI = CBMServiceMock(
        type: .thingyUIService, primary: true,
        characteristics: .thingyButton, .thingyLED
    )
}

// MARK: - Simulated firmware

/// Answers GATT requests like a Thingy:52's UI service would.
/// Main-actor isolated: the mock delivers spec callbacks on the manager's
/// queue, which is the main queue in this app.
@MainActor
private final class ThingyCBMPeripheralSpecDelegate: @preconcurrency CBMPeripheralSpecDelegate {
    private(set) var ledEnabled = false
    private(set) var buttonPressed = false

    private var ledData: Data { Data([ledEnabled ? 0x01 : 0x00]) }
    private var buttonData: Data { Data([buttonPressed ? 0x01 : 0x00]) }

    func reset() {
        ledEnabled = false
        buttonPressed = false
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveReadRequestFor characteristic: CBMCharacteristicMock)
            -> Result<Data, Error> {
        if characteristic.uuid == .thingyLEDCharacteristic {
            return .success(ledData)
        } else {
            return .success(buttonData)
        }
    }

    func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveWriteRequestFor characteristic: CBMCharacteristicMock,
                    data: Data) -> Result<Void, Error> {
        if characteristic.uuid == .thingyLEDCharacteristic, data.count > 0 {
            ledEnabled = data[0] != 0x00
        }
        return .success(())
    }
}

// MARK: - Facade

/// Seeds and drives the simulated Thingy:52. Also used by the integration
/// tests (via @testable import) so the test target does not need to link
/// CoreBluetoothMock itself.
@MainActor
enum ThingyMocks {

    static let mockName = "Thingy52 Mock"

    private static let specDelegate = ThingyCBMPeripheralSpecDelegate()

    static let thingy52: CBMPeripheralSpec = CBMPeripheralSpec
        .simulatePeripheral(proximity: .near)
        .advertising(
            advertisementData: [
                CBMAdvertisementDataLocalNameKey    : mockName,
                CBMAdvertisementDataServiceUUIDsKey : [CBMUUID.thingyUIService],
                CBMAdvertisementDataIsConnectable   : true as NSNumber
            ],
            withInterval: 0.250)
        .connectable(
            name: mockName,
            services: [.thingyUI],
            delegate: specDelegate,
            connectionInterval: 0.045,
            mtu: 23)
        .build()

    private static var seeded = false

    /// Registers the simulated Thingy and powers the mock manager on.
    /// Idempotent; called from app launch (simulator only) and test setup.
    static func setUpSimulation() {
        guard !seeded else { return }
        seeded = true
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        CBMCentralManagerMock.simulatePeripherals([thingy52])
    }

    // MARK: Test controls

    /// The LED state held by the simulated firmware.
    static var ledIsOn: Bool { specDelegate.ledEnabled }

    static func pressButton() {
        thingy52.simulateValueUpdate(Data([0x01]), for: .thingyButton)
    }

    static func releaseButton() {
        thingy52.simulateValueUpdate(Data([0x00]), for: .thingyButton)
    }

    static func powerOff() {
        CBMCentralManagerMock.simulatePowerOff()
    }

    static func powerOn() {
        CBMCentralManagerMock.simulatePowerOn()
    }

    static func disconnectThingy() {
        thingy52.simulateDisconnection()
    }
}
