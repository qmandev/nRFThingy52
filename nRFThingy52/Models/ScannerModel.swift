//
//  ScannerModel.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import Foundation
import CoreBluetooth
import Observation
import os

/// Signal-strength buckets matching the rssi_1...rssi_4 scanner icons
/// (rssi_1 weakest, rssi_4 strongest).
enum RSSIBucket: String {
    case weakest = "rssi_1"
    case weak    = "rssi_2"
    case medium  = "rssi_3"
    case strong  = "rssi_4"

    init(rssi: Int) {
        switch rssi {
        case ..<(-80): self = .weakest
        case ..<(-60): self = .weak
        case ..<(-40): self = .medium
        default:       self = .strong
        }
    }

    var imageName: String { rawValue }
}

/// One discovered Thingy row for the scanner list.
struct DiscoveredThingy: Identifiable {
    let id: UUID
    let peripheral: ThingyPeripheral
    var name: String
    var rssiBucket: RSSIBucket
    var lastUpdated: Date
}

/// Observable scanner state for the SwiftUI UI. Owns the CBCentralManager,
/// remains its sole delegate for the app's lifetime, and forwards connection
/// events to the selected peripheral — the same event routing the UIKit
/// ScannerTableViewController uses.
@MainActor
@Observable
final class ScannerModel: NSObject {

    private(set) var discovered: [DiscoveredThingy] = []
    private(set) var isScanning = false
    private(set) var bluetoothReady = false

    /// The peripheral the user selected; central manager events are forwarded here.
    var selectedPeripheral: ThingyPeripheral?

    @ObservationIgnored
    private var centralManager: CBCentralManager?
    @ObservationIgnored
    private var wantsScan = false
    @ObservationIgnored
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nRFThingy52", category: "ScannerModel")

    /// Minimum interval between visible updates of a row (matches the UIKit cell throttle).
    private static let rowUpdateInterval: TimeInterval = 1.0

    // MARK: - Public API

    /// Starts scanning. The central manager is created lazily here so the
    /// Bluetooth permission prompt appears on the first scan request,
    /// matching the UIKit app's timing.
    func startScan() {
        wantsScan = true
        guard let centralManager = centralManager else {
            // Scanning starts from centralManagerDidUpdateState once powered on.
            centralManager = CBCentralManager(delegate: self, queue: nil)
            return
        }
        beginScanIfPossible(centralManager)
    }

    func stopScan() {
        wantsScan = false
        centralManager?.stopScan()
        isScanning = false
    }

    func clearDiscovered() {
        discovered.removeAll()
    }

    // MARK: - Implementation

    private func beginScanIfPossible(_ central: CBCentralManager) {
        guard wantsScan, central.state == .poweredOn, !isScanning else { return }
        central.scanForPeripherals(withServices: [ThingyPeripheral.nordicThingyServiceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    private func handleDiscovery(_ central: CBCentralManager, peripheral: CBPeripheral,
                                 advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown Device".localized
        let bucket = RSSIBucket(rssi: rssi.intValue)

        if let index = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            guard Date().timeIntervalSince(discovered[index].lastUpdated) > Self.rowUpdateInterval else { return }
            discovered[index].name = name
            discovered[index].rssiBucket = bucket
            discovered[index].lastUpdated = Date()
        } else {
            let thingy = ThingyPeripheral(withPeripheral: peripheral,
                                          advertisementData: advertisementData,
                                          andRSSI: rssi,
                                          using: central)
            discovered.append(DiscoveredThingy(id: peripheral.identifier,
                                               peripheral: thingy,
                                               name: name,
                                               rssiBucket: bucket,
                                               lastUpdated: Date()))
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ScannerModel: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetoothReady = central.state == .poweredOn
            selectedPeripheral?.centralManagerDidUpdateState(central)
            if central.state == .poweredOn {
                beginScanIfPossible(central)
            } else {
                logger.debug("Central is not powered on.")
                isScanning = false
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            handleDiscovery(central, peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            selectedPeripheral?.centralManager(central, didConnect: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            selectedPeripheral?.centralManager(central, didFailToConnect: peripheral, error: error)
            if selectedPeripheral?.isEqual(peripheral) == true {
                selectedPeripheral = nil
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            selectedPeripheral?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
            if selectedPeripheral?.isEqual(peripheral) == true {
                selectedPeripheral = nil
            }
        }
    }
}
