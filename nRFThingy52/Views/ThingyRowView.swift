//
//  ThingyRowView.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import SwiftUI

/// One scanner list row: peripheral name and RSSI signal-strength icon.
/// SwiftUI replacement for ScannerTableViewCell.
struct ThingyRowView: View {

    let thingy: DiscoveredThingy

    var body: some View {
        HStack {
            Text(thingy.name)
            Spacer()
            Image(thingy.rssiBucket.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
        }
    }
}
