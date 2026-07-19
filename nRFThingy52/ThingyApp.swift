//
//  ThingyApp.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import SwiftUI

@main
struct ThingyApp: App {

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
