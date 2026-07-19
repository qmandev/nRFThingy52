//
//  ThingyApp.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import SwiftUI

@main
struct ThingyApp: App {

    init() {
        #if targetEnvironment(simulator)
        // The simulator has no Bluetooth radio; seed a simulated Thingy:52
        // so the app (and integration tests) exercise the full BLE flow.
        ThingyMocks.setUpSimulation()
        // Live demo readings for interactive use only — under XCTest the
        // integration tests drive the sensor values themselves.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            ThingyMocks.startEnvironmentDemo()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ScannerView()
                // Nordic brand color as the global accent. The iOS 26 bar
                // keeps its native Liquid Glass look: an opaque colored bar
                // (the UIKit app's style) obscures SwiftUI's large title.
                .tint(.nordicBlue)
        }
    }
}
