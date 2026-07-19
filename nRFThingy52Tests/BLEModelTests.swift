//
//  BLEModelTests.swift
//  nRFThingy52Tests
//
//  Created by Qiang Ma on 7/19/26.
//

import XCTest
import CoreBluetooth
@testable import nRFThingy52

// MARK: - Mock peripheral

/// Records calls and lets tests drive ThingyDelegate callbacks without CoreBluetooth.
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

// MARK: - ThingyConnection

@MainActor
final class ThingyConnectionTests: XCTestCase {

    private var mock: MockThingy!
    private var connection: ThingyConnection!

    override func setUp() {
        super.setUp()
        mock = MockThingy()
        connection = ThingyConnection(peripheral: mock)
    }

    func testInitBecomesPeripheralDelegateAndStartsConnecting() {
        XCTAssertTrue(mock.delegate === connection)
        XCTAssertEqual(connection.state, .connecting)
    }

    func testConnectCallsPeripheralWhenDisconnected() {
        connection.connect()
        XCTAssertEqual(mock.connectCalls, 1)
    }

    func testConnectSkipsWhenAlreadyConnected() {
        mock.isConnected = true
        connection.connect()
        XCTAssertEqual(mock.connectCalls, 0)
    }

    func testDidConnectPublishesSupportFlags() {
        connection.thingyDidConnect(ledSupported: true, buttonSupported: true)
        XCTAssertEqual(connection.state, .connected)
        XCTAssertTrue(connection.ledSupported)
        XCTAssertTrue(connection.buttonSupported)
        XCTAssertEqual(mock.disconnectCalls, 0)
    }

    func testDidConnectWithNoSupportedFeaturesDisconnects() {
        connection.thingyDidConnect(ledSupported: false, buttonSupported: false)
        XCTAssertEqual(mock.disconnectCalls, 1)
    }

    func testDidDisconnectPublishesDisconnectedState() {
        connection.thingyDidConnect(ledSupported: true, buttonSupported: true)
        connection.thingyDidDisconnect()
        XCTAssertEqual(connection.state, .disconnected)
    }

    func testLEDStateChangesArePublished() {
        connection.ledStateChanged(isOn: true)
        XCTAssertTrue(connection.ledIsOn)
        connection.ledStateChanged(isOn: false)
        XCTAssertFalse(connection.ledIsOn)
    }

    func testButtonStateChangesArePublished() {
        connection.buttonStateChanged(isPressed: true)
        XCTAssertTrue(connection.buttonPressed)
        connection.buttonStateChanged(isPressed: false)
        XCTAssertFalse(connection.buttonPressed)
    }

    func testSetLEDIsOptimisticAndForwards() {
        connection.setLED(on: true)
        XCTAssertTrue(connection.ledIsOn)
        XCTAssertEqual(mock.turnOnCalls, 1)

        connection.setLED(on: false)
        XCTAssertFalse(connection.ledIsOn)
        XCTAssertEqual(mock.turnOffCalls, 1)
    }

    func testNameFallsBackWhenPeripheralHasNoName() {
        XCTAssertEqual(connection.name, "Mock Thingy")
        mock.advertisedName = nil
        XCTAssertEqual(connection.name, "Unknown Device".localized)
    }
}
