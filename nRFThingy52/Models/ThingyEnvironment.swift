//
//  ThingyEnvironment.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//
//  Thingy:52 Environment service (EF680200-...): characteristic UUIDs,
//  value parsing, and the reading type delivered to ThingyDelegate.
//  Wire formats per the Nordic Thingy:52 firmware documentation.
//

import Foundation

/// One decoded environment-sensor update.
enum EnvironmentReading: Equatable {
    case temperature(celsius: Double)
    case humidity(percent: Int)
    case pressure(hPa: Double)
    case airQuality(eco2: Int, tvoc: Int)
}

enum ThingyEnvironment {

    // MARK: - UUIDs

    @MainActor static let serviceUUID               = CBUUID(string: "EF680200-9B35-4933-9B10-52FFA9740042")
    @MainActor static let temperatureCharacteristicUUID = CBUUID(string: "EF680201-9B35-4933-9B10-52FFA9740042")
    @MainActor static let pressureCharacteristicUUID    = CBUUID(string: "EF680202-9B35-4933-9B10-52FFA9740042")
    @MainActor static let humidityCharacteristicUUID    = CBUUID(string: "EF680203-9B35-4933-9B10-52FFA9740042")
    @MainActor static let airQualityCharacteristicUUID  = CBUUID(string: "EF680204-9B35-4933-9B10-52FFA9740042")

    // MARK: - Parsing (pure, unit-tested)

    /// int8 integer part + uint8 hundredths → °C.
    nonisolated static func parseTemperature(_ data: Data) -> EnvironmentReading? {
        guard data.count >= 2 else { return nil }
        let integer = Int(Int8(bitPattern: data[data.startIndex]))
        let decimal = Int(data[data.startIndex + 1])
        let sign = integer < 0 ? -1.0 : 1.0
        return .temperature(celsius: Double(integer) + sign * Double(decimal) / 100.0)
    }

    /// int32 LE integer hPa + uint8 hundredths → hPa.
    nonisolated static func parsePressure(_ data: Data) -> EnvironmentReading? {
        guard data.count >= 5 else { return nil }
        let bytes = [UInt8](data)
        let integer = Int32(littleEndian: bytes.withUnsafeBytes { $0.load(as: Int32.self) })
        let decimal = Int(bytes[4])
        return .pressure(hPa: Double(integer) + Double(decimal) / 100.0)
    }

    /// uint8 %RH.
    nonisolated static func parseHumidity(_ data: Data) -> EnvironmentReading? {
        guard let first = data.first else { return nil }
        return .humidity(percent: Int(first))
    }

    /// uint16 LE eCO2 ppm + uint16 LE TVOC ppb.
    nonisolated static func parseAirQuality(_ data: Data) -> EnvironmentReading? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let eco2 = Int(bytes[0]) | (Int(bytes[1]) << 8)
        let tvoc = Int(bytes[2]) | (Int(bytes[3]) << 8)
        return .airQuality(eco2: eco2, tvoc: tvoc)
    }

    // MARK: - Encoding (used by the mock/simulator)

    nonisolated static func encodeTemperature(celsius: Double) -> Data {
        let integer = Int8(clamping: Int(celsius.rounded(.towardZero)))
        let decimal = UInt8(clamping: Int((abs(celsius) * 100).rounded()) % 100)
        return Data([UInt8(bitPattern: integer), decimal])
    }

    nonisolated static func encodePressure(hPa: Double) -> Data {
        var integer = Int32(hPa.rounded(.towardZero)).littleEndian
        let decimal = UInt8(clamping: Int((hPa * 100).rounded()) % 100)
        var data = withUnsafeBytes(of: &integer) { Data($0) }
        data.append(decimal)
        return data
    }

    nonisolated static func encodeHumidity(percent: Int) -> Data {
        Data([UInt8(clamping: percent)])
    }

    nonisolated static func encodeAirQuality(eco2: Int, tvoc: Int) -> Data {
        Data([UInt8(eco2 & 0xFF), UInt8((eco2 >> 8) & 0xFF),
              UInt8(tvoc & 0xFF), UInt8((tvoc >> 8) & 0xFF)])
    }
}
