//
//  BLEModelTests.swift
//  nRFThingy52Tests
//
//  Created by Qiang Ma on 7/19/26.
//

import XCTest
@testable import nRFThingy52

// MARK: - Mock peripheral

/// Records calls and lets tests drive ThingyDelegate callbacks without CoreBluetooth.
@MainActor
final class MockThingy: ThingyControlling {
    var advertisedName: String? = "Mock Thingy"
    var isConnected = false
    weak var delegate: ThingyDelegate?

    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0
    private(set) var turnOnCalls = 0
    private(set) var turnOffCalls = 0

    func connect() { connectCalls += 1 }
    func disconnect() { disconnectCalls += 1 }
    func turnOnLED() { turnOnCalls += 1 }
    func turnOffLED() { turnOffCalls += 1 }
}

// MARK: - RSSIBucket

final class RSSIBucketTests: XCTestCase {

    func testBucketsAreMonotonicAcrossThresholds() {
        XCTAssertEqual(RSSIBucket(rssi: -100), .weakest)
        XCTAssertEqual(RSSIBucket(rssi: -81), .weakest)
        XCTAssertEqual(RSSIBucket(rssi: -80), .weak)
        XCTAssertEqual(RSSIBucket(rssi: -61), .weak)
        XCTAssertEqual(RSSIBucket(rssi: -60), .medium)
        XCTAssertEqual(RSSIBucket(rssi: -41), .medium)
        XCTAssertEqual(RSSIBucket(rssi: -40), .strong)
        XCTAssertEqual(RSSIBucket(rssi: -20), .strong)
    }

    func testImageNamesMatchAssets() {
        XCTAssertEqual(RSSIBucket.weakest.imageName, "rssi_1")
        XCTAssertEqual(RSSIBucket.weak.imageName, "rssi_2")
        XCTAssertEqual(RSSIBucket.medium.imageName, "rssi_3")
        XCTAssertEqual(RSSIBucket.strong.imageName, "rssi_4")
    }
}

// MARK: - ScannerModel helpers

final class ScannerModelHelperTests: XCTestCase {

    func testAdvertisedNameUsesLocalNameKey() {
        let name = ScannerModel.advertisedName(from: [CBAdvertisementDataLocalNameKey: "My Thingy"])
        XCTAssertEqual(name, "My Thingy")
    }

    func testAdvertisedNameFallsBackForMissingName() {
        XCTAssertEqual(ScannerModel.advertisedName(from: [:]), "Unknown Device".localized)
    }

    func testRowRefreshThrottle() {
        let now = Date()
        XCTAssertFalse(ScannerModel.shouldRefreshRow(lastUpdated: now.addingTimeInterval(-0.5), now: now))
        XCTAssertTrue(ScannerModel.shouldRefreshRow(lastUpdated: now.addingTimeInterval(-1.5), now: now))
    }
}

// MARK: - Environment parsing

final class ThingyEnvironmentTests: XCTestCase {

    func testTemperatureParsingPositiveAndNegative() {
        XCTAssertEqual(ThingyEnvironment.parseTemperature(Data([22, 50])),
                       .temperature(celsius: 22.5))
        XCTAssertEqual(ThingyEnvironment.parseTemperature(Data([UInt8(bitPattern: -5), 25])),
                       .temperature(celsius: -5.25))
        XCTAssertNil(ThingyEnvironment.parseTemperature(Data([1])))
    }

    func testPressureParsing() {
        XCTAssertEqual(ThingyEnvironment.parsePressure(ThingyEnvironment.encodePressure(hPa: 1013.25)),
                       .pressure(hPa: 1013.25))
        XCTAssertNil(ThingyEnvironment.parsePressure(Data([0, 0, 0])))
    }

    func testHumidityParsing() {
        XCTAssertEqual(ThingyEnvironment.parseHumidity(Data([47])), .humidity(percent: 47))
        XCTAssertNil(ThingyEnvironment.parseHumidity(Data()))
    }

    func testAirQualityParsing() {
        XCTAssertEqual(ThingyEnvironment.parseAirQuality(ThingyEnvironment.encodeAirQuality(eco2: 450, tvoc: 1200)),
                       .airQuality(eco2: 450, tvoc: 1200))
        XCTAssertNil(ThingyEnvironment.parseAirQuality(Data([1, 2])))
    }

    func testTemperatureEncodingRoundTrip() {
        XCTAssertEqual(ThingyEnvironment.parseTemperature(ThingyEnvironment.encodeTemperature(celsius: 22.5)),
                       .temperature(celsius: 22.5))
    }
}

// MARK: - ThingyConnection

@MainActor
final class ThingyConnectionTests: XCTestCase {

    private func makeSUT() -> (mock: MockThingy, connection: ThingyConnection) {
        let mock = MockThingy()
        return (mock, ThingyConnection(peripheral: mock))
    }

    func testInitBecomesPeripheralDelegateAndStartsConnecting() {
        let (mock, connection) = makeSUT()
        XCTAssertTrue(mock.delegate === connection)
        XCTAssertEqual(connection.state, .connecting)
    }

    func testConnectCallsPeripheralWhenDisconnected() {
        let (mock, connection) = makeSUT()
        connection.connect()
        XCTAssertEqual(mock.connectCalls, 1)
    }

    func testConnectSkipsWhenAlreadyConnected() {
        let (mock, connection) = makeSUT()
        mock.isConnected = true
        connection.connect()
        XCTAssertEqual(mock.connectCalls, 0)
    }

    func testDidConnectPublishesSupportFlags() {
        let (mock, connection) = makeSUT()
        connection.thingyDidConnect(ledSupported: true, buttonSupported: true)
        XCTAssertEqual(connection.state, .connected)
        XCTAssertTrue(connection.ledSupported)
        XCTAssertTrue(connection.buttonSupported)
        XCTAssertEqual(mock.disconnectCalls, 0)
    }

    func testDidConnectWithNoSupportedFeaturesDisconnects() {
        let (mock, connection) = makeSUT()
        connection.thingyDidConnect(ledSupported: false, buttonSupported: false)
        XCTAssertEqual(mock.disconnectCalls, 1)
    }

    func testDidDisconnectPublishesDisconnectedState() {
        let (_, connection) = makeSUT()
        connection.thingyDidConnect(ledSupported: true, buttonSupported: true)
        connection.thingyDidDisconnect()
        XCTAssertEqual(connection.state, .disconnected)
    }

    func testLEDStateChangesArePublished() {
        let (_, connection) = makeSUT()
        connection.ledStateChanged(isOn: true)
        XCTAssertTrue(connection.ledIsOn)
        connection.ledStateChanged(isOn: false)
        XCTAssertFalse(connection.ledIsOn)
    }

    func testButtonStateChangesArePublished() {
        let (_, connection) = makeSUT()
        connection.buttonStateChanged(isPressed: true)
        XCTAssertTrue(connection.buttonPressed)
        connection.buttonStateChanged(isPressed: false)
        XCTAssertFalse(connection.buttonPressed)
    }

    func testSetLEDIsOptimisticAndForwards() {
        let (mock, connection) = makeSUT()
        connection.setLED(on: true)
        XCTAssertTrue(connection.ledIsOn)
        XCTAssertEqual(mock.turnOnCalls, 1)

        connection.setLED(on: false)
        XCTAssertFalse(connection.ledIsOn)
        XCTAssertEqual(mock.turnOffCalls, 1)
    }

    func testNameFallsBackWhenPeripheralHasNoName() {
        let (mock, connection) = makeSUT()
        XCTAssertEqual(connection.name, "Mock Thingy")
        mock.advertisedName = nil
        XCTAssertEqual(connection.name, "Unknown Device".localized)
    }
}
