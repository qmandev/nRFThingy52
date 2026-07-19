//
//  ThingyDetailView.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import SwiftUI

/// The Thingy detail screen: LED toggle and live button state.
/// SwiftUI replacement for ThingyViewController.
struct ThingyDetailView: View {

    let connection: ThingyConnection

    var body: some View {
        List {
            Section {
                Toggle(isOn: ledBinding) {
                    HStack {
                        Image("ic_lightbulb_outline_48pt")
                            .renderingMode(.template)
                        Text(ledStateText)
                    }
                }
                .disabled(!ledEnabled)
                .tint(connection.state == .disconnected ? Color.nordicRed : nil)
            } header: {
                Text("LED")
            } footer: {
                Text("Toggling the switch will cause the LED on the Thingy to turn ON or OFF.")
            }

            Section {
                HStack {
                    Image("ic_radio_button_checked")
                        .renderingMode(.template)
                    Text(buttonStateText)
                }
            } header: {
                Text("Button")
            } footer: {
                Text("Pressing and releasing the button on the Thingy will update the state here.")
            }
        }
        .navigationTitle(connection.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .heavy), trigger: connection.buttonPressed) { _, isPressed in
            isPressed
        }
        .onAppear {
            connection.connect()
        }
        .onDisappear {
            connection.disconnect()
        }
    }

    // MARK: - Derived state

    private var ledEnabled: Bool {
        connection.state == .connected && connection.ledSupported
    }

    private var ledBinding: Binding<Bool> {
        Binding(
            get: { connection.ledIsOn },
            set: { connection.setLED(on: $0) }
        )
    }

    private var ledStateText: LocalizedStringKey {
        switch connection.state {
        case .connecting:   return "Scanning..."
        case .disconnected: return "DISCONNECTED"
        case .connected:    return connection.ledIsOn ? "ON" : "OFF"
        }
    }

    private var buttonStateText: LocalizedStringKey {
        switch connection.state {
        case .connecting:   return "Scanning..."
        case .disconnected: return "DISCONNECTED"
        case .connected:    return connection.buttonPressed ? "PRESSED" : "RELEASED"
        }
    }
}
