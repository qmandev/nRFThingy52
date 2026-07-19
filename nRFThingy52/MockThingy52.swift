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
    @MainActor static let thingyEnvService        = CBMUUID(string: "EF680200-9B35-4933-9B10-52FFA9740042")
    @MainActor static let thingyTemperature       = CBMUUID(string: "EF680201-9B35-4933-9B10-52FFA9740042")
    @MainActor static let thingyPressure          = CBMUUID(string: "EF680202-9B35-4933-9B10-52FFA9740042")
    @MainActor static let thingyHumidity          = CBMUUID(string: "EF680203-9B35-4933-9B10-52FFA9740042")
    @MainActor static let thingyAirQuality        = CBMUUID(string: "EF680204-9B35-4933-9B10-52FFA9740042")
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
    @MainActor static let thingyTemperature = CBMCharacteristicMock(
        type: .thingyTemperature,
        properties: [.notify],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )
    @MainActor static let thingyPressure = CBMCharacteristicMock(
        type: .thingyPressure,
        properties: [.notify],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )
    @MainActor static let thingyHumidity = CBMCharacteristicMock(
        type: .thingyHumidity,
        properties: [.notify],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )
    @MainActor static let thingyAirQuality = CBMCharacteristicMock(
        type: .thingyAirQuality,
        properties: [.notify],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )
}

private extension CBMServiceMock {
    @MainActor static let thingyUI = CBMServiceMock(
        type: .thingyUIService, primary: true,
        characteristics: .thingyButton, .thingyLED
    )
    @MainActor static let thingyEnvironment = CBMServiceMock(
        type: .thingyEnvService, primary: true,
        characteristics: .thingyTemperature, .thingyPressure, .thingyHumidity, .thingyAirQuality
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
            services: [.thingyUI, .thingyEnvironment],
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

    // MARK: Environment simulation

    /// Pushes one full set of environment readings as notifications.
    static func simulateEnvironment(temperature: Double, humidity: Int, pressure: Double,
                                    eco2: Int, tvoc: Int) {
        thingy52.simulateValueUpdate(ThingyEnvironment.encodeTemperature(celsius: temperature),
                                     for: .thingyTemperature)
        thingy52.simulateValueUpdate(ThingyEnvironment.encodeHumidity(percent: humidity),
                                     for: .thingyHumidity)
        thingy52.simulateValueUpdate(ThingyEnvironment.encodePressure(hPa: pressure),
                                     for: .thingyPressure)
        thingy52.simulateValueUpdate(ThingyEnvironment.encodeAirQuality(eco2: eco2, tvoc: tvoc),
                                     for: .thingyAirQuality)
    }

    private static var demoTimer: Timer?

    /// Drifting demo readings so the simulator dashboard is alive.
    static func startEnvironmentDemo() {
        guard demoTimer == nil else { return }
        var temp = 22.5, hum = 45.0, press = 1013.2, eco2 = 480.0, tvoc = 18.0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                temp  = min(30, max(15, temp + Double.random(in: -0.3...0.3)))
                hum   = min(70, max(25, hum + Double.random(in: -1...1)))
                press = min(1040, max(980, press + Double.random(in: -0.5...0.5)))
                eco2  = min(1200, max(400, eco2 + Double.random(in: -20...20)))
                tvoc  = min(120, max(0, tvoc + Double.random(in: -4...4)))
                simulateEnvironment(temperature: temp, humidity: Int(hum), pressure: press,
                                    eco2: Int(eco2), tvoc: Int(tvoc))
            }
        }
    }
}
