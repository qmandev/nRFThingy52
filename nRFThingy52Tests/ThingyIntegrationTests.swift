//
//  ThingyIntegrationTests.swift
//  nRFThingy52Tests
//
//  Created by Qiang Ma on 7/19/26.
//
//  End-to-end BLE pipeline tests against the simulated Thingy:52
//  (CoreBluetoothMock). These run only on the simulator, where the
//  CBCentralManagerFactory returns the mock implementation.
//

import XCTest
@testable import nRFThingy52

@MainActor
final class ThingyIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Polls the condition on the main actor until it is true or the timeout expires.
    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 5,
                           condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for: \(description)")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Scans until the mock Thingy is discovered; returns the scanner and row.
    private func discoverThingy() async throws -> (ScannerModel, DiscoveredThingy) {
        ThingyMocks.setUpSimulation()
        ThingyMocks.powerOn()
        let scanner = ScannerModel()
        scanner.startScan()
        try await waitUntil("mock Thingy discovered") { !scanner.discovered.isEmpty }
        let row = scanner.discovered[0]
        return (scanner, row)
    }

    /// Discovers, selects, and connects; returns scanner + connection in connected state.
    private func connectToThingy() async throws -> (ScannerModel, ThingyConnection) {
        let (scanner, row) = try await discoverThingy()
        scanner.stopScan()
        scanner.selectedPeripheral = row.peripheral
        let connection = ThingyConnection(peripheral: row.peripheral)
        connection.connect()
        try await waitUntil("connection established") { connection.state == .connected }
        return (scanner, connection)
    }

    // MARK: - §9 checklist items

    /// Item 1: discovery via the UI-service scan filter, with advertised name.
    func testDiscoveryFindsAdvertisingThingy() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, row) = try await discoverThingy()
        XCTAssertEqual(row.name, ThingyMocks.mockName)
        XCTAssertTrue(scanner.isScanning)
        scanner.stopScan()
    }

    /// Item 2: select → connect runs the full discover/notify/read pipeline.
    func testConnectDiscoversLEDAndButton() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, connection) = try await connectToThingy()
        XCTAssertTrue(connection.ledSupported)
        XCTAssertTrue(connection.buttonSupported)
        connection.disconnect()
        withExtendedLifetime(scanner) {}
    }

    /// Item 3: LED write reaches the simulated firmware and is confirmed by read-back.
    func testLEDToggleWritesAndReadsBack() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, connection) = try await connectToThingy()

        connection.setLED(on: true)
        try await waitUntil("firmware LED on") { ThingyMocks.ledIsOn }
        XCTAssertTrue(connection.ledIsOn)

        connection.setLED(on: false)
        try await waitUntil("firmware LED off") { !ThingyMocks.ledIsOn }
        XCTAssertFalse(connection.ledIsOn)
        connection.disconnect()
        withExtendedLifetime(scanner) {}
    }

    /// Item 4: button notifications propagate to observable state.
    func testButtonPressAndReleaseNotify() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, connection) = try await connectToThingy()

        ThingyMocks.pressButton()
        try await waitUntil("button pressed") { connection.buttonPressed }

        ThingyMocks.releaseButton()
        try await waitUntil("button released") { !connection.buttonPressed }
        connection.disconnect()
        withExtendedLifetime(scanner) {}
    }

    /// Item 5: on-demand disconnect (navigate away) reaches disconnected state.
    func testDisconnectOnDemand() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, connection) = try await connectToThingy()
        connection.disconnect()
        try await waitUntil("disconnected") { connection.state == .disconnected }
        withExtendedLifetime(scanner) {}
    }

    /// Item 6: Bluetooth powering off surfaces the disconnected state.
    func testPowerOffDisconnects() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, connection) = try await connectToThingy()
        ThingyMocks.powerOff()
        try await waitUntil("disconnected after power off") { connection.state == .disconnected }
        ThingyMocks.powerOn()
        withExtendedLifetime(scanner) {}
    }

    /// Item 7 (variant): peripheral-initiated disconnection surfaces the
    /// disconnected state via the scanner's forwarding.
    func testPeripheralInitiatedDisconnect() async throws {
        try XCTSkipUnless(isSimulator, "Mock manager exists only on the simulator")
        let (scanner, connection) = try await connectToThingy()
        ThingyMocks.disconnectThingy()
        try await waitUntil("disconnected after device reset") { connection.state == .disconnected }
        withExtendedLifetime(scanner) {}
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
