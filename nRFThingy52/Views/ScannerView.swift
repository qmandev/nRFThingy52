//
//  ScannerView.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import SwiftUI

/// The scanner screen: lists nearby Thingys advertising the UI service,
/// with a scanning indicator and an empty-state view. SwiftUI replacement
/// for ScannerTableViewController.
struct ScannerView: View {

    @State private var scanner = ScannerModel()
    @State private var selection: ThingyConnection?

    var body: some View {
        NavigationStack {
            List {
                if !scanner.discovered.isEmpty {
                    Section("Nearby Devices") {
                        ForEach(scanner.discovered) { thingy in
                            Button {
                                select(thingy)
                            } label: {
                                ThingyRowView(thingy: thingy)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .overlay {
                if scanner.discovered.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("Thingy52")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if scanner.isScanning {
                        ProgressView()
                    }
                }
            }
            .navigationDestination(item: $selection) { connection in
                ThingyDetailView(connection: connection)
            }
            .onAppear {
                scanner.clearDiscovered()
                scanner.startScan()
            }
        }
    }

    private func select(_ thingy: DiscoveredThingy) {
        scanner.stopScan()
        scanner.selectedPeripheral = thingy.peripheral
        selection = ThingyConnection(peripheral: thingy.peripheral)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("CAN'T SEE YOUR THINGY?")
            } icon: {
                Image("scanning")
            }
        } description: {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Make sure it's switched on.")
                Text("Toggle the switch next to the micro USB port to switch it on.")
                    .font(.caption2)
                Text("2. Make sure the coin cell battery has power.")
                    .padding(.top, 6)
                Text("If not, connect it to a PC or a charger using a micro USB cable. Coin cell battery is on the bottom side of the dev kit.")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
}

#Preview {
    ScannerView()
}
