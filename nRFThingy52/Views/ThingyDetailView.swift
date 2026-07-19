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

            if connection.hasEnvironmentData {
                Section {
                    sensorRow(symbol: "thermometer.medium", label: "Temperature",
                              value: connection.temperature.map { String(format: "%.1f °C", $0) })
                    sensorRow(symbol: "humidity", label: "Humidity",
                              value: connection.humidity.map { "\($0) %" })
                    sensorRow(symbol: "gauge.with.dots.needle.bottom.50percent", label: "Pressure",
                              value: connection.pressure.map { String(format: "%.1f hPa", $0) })
                    sensorRow(symbol: "aqi.medium", label: "Air Quality",
                              value: airQualityText)
                } header: {
                    Text("Environment")
                } footer: {
                    Text("Live sensor readings streamed from the Thingy.")
                }
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

    // MARK: - Environment rows

    private func sensorRow(symbol: String, label: LocalizedStringKey, value: String?) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(label)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var airQualityText: String? {
        guard let eco2 = connection.eco2, let tvoc = connection.tvoc else { return nil }
        return "\(eco2) ppm · \(tvoc) ppb"
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
