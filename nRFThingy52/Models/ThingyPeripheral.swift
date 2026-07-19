//
//  ThingyPeripheral.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/25/21.
//

import UIKit
import os

@MainActor
protocol ThingyDelegate: AnyObject {
    func thingyDidConnect(ledSupported: Bool, buttonSupported: Bool)
    func thingyDidDisconnect()
    func buttonStateChanged(isPressed: Bool)
    func ledStateChanged(isOn: Bool)
    func environmentDidUpdate(_ reading: EnvironmentReading)
}

extension ThingyDelegate {
    // Environment updates are optional for delegates that only care about LED/button.
    func environmentDidUpdate(_ reading: EnvironmentReading) {}
}

/// Main-actor isolated: the central manager is created with `queue: nil`, so
/// every CoreBluetooth callback arrives on the main queue. The
/// @preconcurrency conformances let the isolated methods satisfy the
/// nonisolated delegate requirements, with a runtime main-thread assertion.
@MainActor
class ThingyPeripheral: NSObject, @preconcurrency CBPeripheralDelegate, @preconcurrency CBCentralManagerDelegate {
    
    // MARK: - Thingy services and charcteristics Identifiers

    // Thingy:52 User Interface service (base UUID EF68xxxx-9B35-4933-9B10-52FFA9740042)
    public static let nordicThingyServiceUUID  = CBUUID.init(string: "EF680300-9B35-4933-9B10-52FFA9740042")
    public static let buttonCharacteristicUUID = CBUUID.init(string: "EF680302-9B35-4933-9B10-52FFA9740042")
    public static let ledCharacteristicUUID    = CBUUID.init(string: "EF680301-9B35-4933-9B10-52FFA9740042")

    // MARK: - Properties

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nRFThingy52", category: "ThingyPeripheral")
    private var logger : Logger { ThingyPeripheral.logger }
    
    private let centralManager                : CBCentralManager
    private let basePeripheral                : CBPeripheral
    /// Nonisolated copy of the peripheral identifier so the NSObject
    /// isEqual/hash overrides (nonisolated requirements) can use it.
    nonisolated let peripheralIdentifier      : UUID
    public private(set) var advertisedName    : String?
    public private(set) var RSSI              : NSNumber
    
    public weak var delegate: ThingyDelegate?
    
    
    // MARK: - Computed Properties
    
    public var isConnected : Bool {
        return self.basePeripheral.state == .connected
    }
    
    
    // MARK: - Characteristic Properties
    
    private var buttonCharacteristic : CBCharacteristic?
    private var ledCharacteristic : CBCharacteristic?
    
    
    // MARK: - Public API
    /// Creates the ThingyPeripheral based on the received peripheral and advertisign data.
    /// The device name is obtaied from the advertising data, not from CBPeripheral object
    /// to avoid caching problems.
    init(withPeripheral peripheral: CBPeripheral, advertisementData advertisementDictionary: [String : Any], andRSSI currentRSSI: NSNumber, using manager: CBCentralManager) {
        
        basePeripheral = peripheral
        peripheralIdentifier = peripheral.identifier
        centralManager = manager
        RSSI = currentRSSI
        super.init()
        
        advertisedName = parseAdvertisementData(advertisementDictionary)
        basePeripheral.delegate = self
    }
    
    /// Connects to the Thingy 52 device.
    /// The scanner remains the central manager's delegate and forwards
    /// connection events to this object.
    public func connect() {
        logger.debug("Connecting to Thingy 52 device ...")
        centralManager.connect(basePeripheral, options: nil)
    }
    
    /// Disconnects from the Thingy 52 device.
    public func disconnect() {
        logger.debug("Cancelling connection to Thingy 52 device ...")
        centralManager.cancelPeripheralConnection(basePeripheral)
    }
    
    // MARK: Thingy API
    
    /// Reads value of LED Characteristic. If such characteristic was not
    /// found, this method does nothing. If it was found, but does not have
    /// read property, the delegate will be notified with isOn = false.
    public func readLEDValue() {
        if let ledCharacteristic = ledCharacteristic {
            if ledCharacteristic.properties.contains(.read) {
                logger.debug("Reading LED characteristics ...")
                basePeripheral.readValue(for: ledCharacteristic)
            } else {
                logger.debug("can't read LED state")
                delegate?.ledStateChanged(isOn: false)
            }
        }
    }
    
    /// Reads value of Button Characteristic. If such characteristic was not
    /// found, this method does nothing. If it was found, but does not have
    /// read property, the delegate will be notified with isPressed = false.
    public func readButtonValue() {
        if let buttonCharacteristic = buttonCharacteristic {
            if buttonCharacteristic.properties.contains(.read) {
                logger.debug("Reading Button characteristics ...")
                basePeripheral.readValue(for: buttonCharacteristic)
            } else {
                logger.debug("can't read Button state")
                delegate?.buttonStateChanged(isPressed: false)
            }
        }
    }
    
    /// Sends a request to turn the LED on.
    public func turnOnLED() {
        writeLEDCharacteristic(withValue: Data([0x1]))
    }
    
    /// Sends a request to turn the LED off.
    func turnOffLED() {
        writeLEDCharacteristic(withValue: Data([0x0]))
    }
    
    
    // MARK: Implementation
    
    private func discoverThingyServices() {
        logger.debug("Discovering Thingy UI and Environment services ...")
        basePeripheral.delegate = self

        basePeripheral.discoverServices([ThingyPeripheral.nordicThingyServiceUUID,
                                         ThingyEnvironment.serviceUUID])
    }
    
    private func parseAdvertisementData(_ advertisementDictionary: [String : Any]) -> String? {
        var advertisedName = String()
        
        if let name = advertisementDictionary[CBAdvertisementDataLocalNameKey] as? String {
            advertisedName = name
        } else {
            return "Unknown Device".localized
        }
        
        return advertisedName
    }
    
    private func discoverCharacteristicsForThingyService(_ service: CBService) {
        logger.debug("Discovering Thingy 52 Characteristics: Button and LED (maybe more)")
        basePeripheral.discoverCharacteristics([ThingyPeripheral.ledCharacteristicUUID, ThingyPeripheral.buttonCharacteristicUUID],
                                               for: service)
    }
    
    /// Enables notification for given characteristic.
    /// If the characteristic does not have notify property, this method will
    /// call delegate's thingyDidConnect method and try to read values
    /// of LED and Button.
    private func enableNotifications(for characteristic: CBCharacteristic) {
        if characteristic.properties.contains(.notify) {
            logger.debug("Enabling characteristic for notification ...")
            basePeripheral.setNotifyValue(true, for: characteristic)
        } else {
            delegate?.thingyDidConnect(ledSupported: ledCharacteristic != nil, buttonSupported: true)
            readButtonValue()
            readLEDValue()
        }
    }
    
    /// Writes the value to the LED characteristic. Acceptable value
    /// is 1-byte long, with 0x00 to disable and 0x01 to enable the LED.
    /// If there is no LED characteristic, this method does nothing.
    /// If the characteristic does not have any of write properties
    /// this method also does nothing.
    private func writeLEDCharacteristic(withValue value: Data) {
        if let LEDCharcateristic = ledCharacteristic {
            if LEDCharcateristic.properties.contains(.write) {
                logger.debug("Writing LED value (With response) ...")
                basePeripheral.writeValue(value, for: LEDCharcateristic, type: .withResponse)
            } else if LEDCharcateristic.properties.contains(.writeWithoutResponse){
                logger.debug("Writing LED value (Without response) ...")
                basePeripheral.writeValue(value, for: LEDCharcateristic, type: .withoutResponse)
                
                // peripheral(_:didWriteValueFor,error) will not be called after write without response
                // we are caling the delegate here
                didWriteValueToLED(value)
            } else {
                logger.debug("LED Characteristic is not writable.")
            }
        }
    }
    
    /// A callback called when the LED value has been written.
    private func didWriteValueToLED(_ value: Data) {
        logger.debug("LED value written : \(value)")
        delegate?.ledStateChanged(isOn: value[0] == 0x1)
    }
    
    /// A callback called when the Button characteristic value has changed.
    private func didReceiveButtonNotification(withValue value: Data) {
        logger.debug("Button value changed to : \(value[0])")
        delegate?.buttonStateChanged(isPressed: value[0] == 0x1)
    }
    
    
}



// MARK: NSObject protocols

extension ThingyPeripheral {
    
    nonisolated override func isEqual(_ object: Any?) -> Bool {
        if let peripheralObject = object as? ThingyPeripheral {
            return peripheralObject.peripheralIdentifier == peripheralIdentifier
        } else if let peripheralObject = object as? CBPeripheral {
            return peripheralObject.identifier == peripheralIdentifier
        } else {
            return false
        }
    }

    nonisolated override var hash: Int {
        return peripheralIdentifier.hashValue
    }
}



// MARK: Delegates for CBCentralManagerDelegate

extension ThingyPeripheral {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            logger.debug("Central Manager state changed to \(central.state.rawValue)")
            
            delegate?.thingyDidDisconnect()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral.identifier == peripheralIdentifier {
            logger.debug("Connected to Thingy 52.")
            
            discoverThingyServices()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == peripheralIdentifier {
            logger.debug("Failed to connect to Thingy 52: \(error?.localizedDescription ?? "unknown error")")
            delegate?.thingyDidDisconnect()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == peripheralIdentifier {
            logger.debug("Thingy 52 disconnected.")

            delegate?.thingyDidDisconnect()
        }
    }
}

// MARK: Delegates for CBPeripheralDelegate

extension ThingyPeripheral {
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == ThingyPeripheral.ledCharacteristicUUID {
            if let value = characteristic.value {
                didWriteValueToLED(value)
            }

        } else if characteristic.uuid == ThingyPeripheral.buttonCharacteristicUUID {
            if let value = characteristic.value {
                didReceiveButtonNotification(withValue: value)
            }
        } else if let value = characteristic.value,
                  let reading = environmentReading(for: characteristic.uuid, data: value) {
            delegate?.environmentDidUpdate(reading)
        }
    }

    /// Decodes an Environment-service characteristic value, or nil for other UUIDs.
    private func environmentReading(for uuid: CBUUID, data: Data) -> EnvironmentReading? {
        switch uuid {
        case ThingyEnvironment.temperatureCharacteristicUUID:
            return ThingyEnvironment.parseTemperature(data)
        case ThingyEnvironment.pressureCharacteristicUUID:
            return ThingyEnvironment.parsePressure(data)
        case ThingyEnvironment.humidityCharacteristicUUID:
            return ThingyEnvironment.parseHumidity(data)
        case ThingyEnvironment.airQualityCharacteristicUUID:
            return ThingyEnvironment.parseAirQuality(data)
        default:
            return nil
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == ThingyPeripheral.buttonCharacteristicUUID {
            logger.debug("Button notification enabled.")
            
            delegate?.thingyDidConnect(ledSupported: ledCharacteristic != nil,
                                       buttonSupported: buttonCharacteristic != nil)
            
            readButtonValue()
            readLEDValue()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                if service.uuid == ThingyPeripheral.nordicThingyServiceUUID {
                    logger.debug("Thingy 52 UI Service found")
                    discoverCharacteristicsForThingyService(service)
                } else if service.uuid == ThingyEnvironment.serviceUUID {
                    logger.debug("Thingy 52 Environment Service found")
                    basePeripheral.discoverCharacteristics([ThingyEnvironment.temperatureCharacteristicUUID,
                                                            ThingyEnvironment.pressureCharacteristicUUID,
                                                            ThingyEnvironment.humidityCharacteristicUUID,
                                                            ThingyEnvironment.airQualityCharacteristicUUID],
                                                           for: service)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if service.uuid == ThingyEnvironment.serviceUUID {
            // Subscribe to every environment sensor; values stream via notifications.
            for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.notify) {
                basePeripheral.setNotifyValue(true, for: characteristic)
            }
            return
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == ThingyPeripheral.ledCharacteristicUUID {
                    logger.debug("LED Characteristic found")
                    ledCharacteristic = characteristic
                } else if characteristic.uuid == ThingyPeripheral.buttonCharacteristicUUID {
                    buttonCharacteristic = characteristic
                }
            }
        }

        // if Button Characteristic found, try to enable notifications on it
        if let buttonCharacteristic = buttonCharacteristic {
            enableNotifications(for: buttonCharacteristic)
        } else {
            // else, notify the delegate and try to read LED state
            delegate?.thingyDidConnect(ledSupported: ledCharacteristic != nil, buttonSupported: false)

            // if LED Characteristics is not found, this method will not do anything
            readLEDValue()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // LED value has been written, let's read it to confirm
        if characteristic.uuid == ThingyPeripheral.ledCharacteristicUUID {
            readLEDValue()
        }
    }
}
