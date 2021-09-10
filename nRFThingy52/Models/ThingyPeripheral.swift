//
//  ThingyPeripheral.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/25/21.
//

import UIKit
import CoreBluetooth

protocol ThingyDelegate {
    func thingyDidConnect(ledSupported: Bool, buttonSupported: Bool)
    func thingyDidDisconnect()
    func buttonStateChanged(isPressed: Bool)
    func ledStateChanged(isOn: Bool)
}

class ThingyPeripheral: NSObject, CBPeripheralDelegate, CBCentralManagerDelegate {
    
    // MARK: - Blinky services and charcteristics Identifiers
    
    // TODO: will need to find the correct ServiceUUID for Thingy52
    // public static let nordicThingyServiceUUID  = CBUUID.init(string: "00001523-1212-EFDE-1523-785FEABCD123")
    // public static let buttonCharacteristicUUID = CBUUID.init(string: "00001524-1212-EFDE-1523-785FEABCD123")
    // public static let ledCharacteristicUUID    = CBUUID.init(string: "00001525-1212-EFDE-1523-785FEABCD123")
    
    public static let nordicThingyServiceUUID  = CBUUID.init(string: "EF680300-9B35-4933-9B10-52FFA9740042")
    public static let buttonCharacteristicUUID = CBUUID.init(string: "EF680302-9B35-4933-9B10-52FFA9740042")
    public static let ledCharacteristicUUID    = CBUUID.init(string: "EF680301-9B35-4933-9B10-52FFA9740042")
    
    //MARK: - Base Identifier formats
    let baseUUIDFormat  : String = "EF68%@-9B35-4933-9B10-52FFA9740042"
    
    //MARK: - UserInterfaceService UUIDs
    func getUIServiceUUID() -> CBUUID {
        return getUUIDString(withBaseFormat: baseUUIDFormat, andIdentifier: "0300")
    }

    func getLEDCharacteristicUUID() -> CBUUID {
        return getUUIDString(withBaseFormat: baseUUIDFormat, andIdentifier: "0301")
    }

    func getButtonCharacteristicUUID() -> CBUUID {
        return getUUIDString(withBaseFormat: baseUUIDFormat, andIdentifier: "0302")
    }
    
    //MARK: - UUID generation helper
    fileprivate func getUUIDString(withBaseFormat aBaseFormat: String, andIdentifier anIdentifier: String) -> CBUUID {
        let uuidString = String(format: aBaseFormat, anIdentifier)
        return CBUUID(string: uuidString)
    }
    
    // MARK: - Properties
    
    private let centralManager                : CBCentralManager
    private let basePeripheral                : CBPeripheral
    public private(set) var advertisedName    : String?
    public private(set) var RSSI              : NSNumber
    
    public var delegate: ThingyDelegate?
    
    
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
        centralManager = manager
        RSSI = currentRSSI
        super.init()
        
        advertisedName = parseAdvertisementData(advertisementDictionary)
        basePeripheral.delegate = self
    }
    
    /// Connects to the Thingy 52 device.
    public func connect() {
        centralManager.delegate = self
        print("Connecting to Thingy 52 device ...")
        centralManager.connect(basePeripheral, options: nil)
    }
    
    /// Disconnects to the Thingy 52 device.
    public func disConnect() {
        print("Cancelling connection to Thingy 52 device ...")
        centralManager.cancelPeripheralConnection(basePeripheral)
    }
    
    // MARK: Thingy API
    
    /// Reads value of LED Characteristic. If such characteristic was not
    /// found, this method does nothing. If it was found, but does not have
    /// read property, the delegate will be notified with isOn = false.
    public func readLEDValue() {
        if let ledCharacteristic = ledCharacteristic {
            if ledCharacteristic.properties.contains(.read) {
                print("Reading LED characteristics ...")
                basePeripheral.readValue(for: ledCharacteristic)
            } else {
                print("can't read LED state")
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
                print("Reading Button characteristics ...")
                basePeripheral.readValue(for: buttonCharacteristic)
            } else {
                print("can't read Button state")
                delegate?.buttonStateChanged(isPressed: false)
            }
        }
    }
    
    /// Sends a request to turn the LED on.
    public func turnOnLED() {
        writeLEDCharcateristic(withValue: Data([0x1]))
    }
    
    /// Sends a request to turn the LED off.
    func turnOffLED() {
        writeLEDCharcateristic(withValue: Data([0x0]))
    }
    
    
    // MARK: Implementation
    
    private func discoverThingyServices() {
        print("Discovering LED Button (up to change) Service ...")
        basePeripheral.delegate = self
        
        basePeripheral.discoverServices([ThingyPeripheral.nordicThingyServiceUUID]) // 1523 for Blinky
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
        print("Discovering Thingy 52 Characteristics: Button and LED (maybe more)")
        basePeripheral.discoverCharacteristics([ThingyPeripheral.ledCharacteristicUUID, ThingyPeripheral.buttonCharacteristicUUID],
                                               for: service)
    }
    
    /// Enables notification for given characteristic.
    /// If the characteristic does not have notify property, this method will
    /// call delegate's thingyDidConnect method and try to read values
    /// of LED and Button.
    private func enableNotifications(for characteristic: CBCharacteristic) {
        if characteristic.properties.contains(.notify) {
            print("Enabling characteristic for notification ...")
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
    private func writeLEDCharcateristic(withValue value: Data) {
        if let LEDCharcateristic = ledCharacteristic {
            if LEDCharcateristic.properties.contains(.write) {
                print("Writing LED value (With response) ...")
                basePeripheral.writeValue(value, for: LEDCharcateristic, type: .withResponse)
            } else if LEDCharcateristic.properties.contains(.writeWithoutResponse){
                print("Writing LED value (Without response) ...")
                basePeripheral.writeValue(value, for: LEDCharcateristic, type: .withoutResponse)
                
                // peripheral(_:didWriteValueFor,error) will not be called after write without response
                // we are caling the delegate here
                didWriteValueToLED(value)
            } else {
                print("LED Characteristic is not writable.")
            }
        }
    }
    
    /// A callback called when the LED value has been written.
    private func didWriteValueToLED(_ value: Data) {
        print("LED value written : \(value)")
        delegate?.ledStateChanged(isOn: value[0] == 0x1)
    }
    
    /// A callback called when the Button characteristic value has changed.
    private func didReceiveButtonNotification(withValue value: Data) {
        print("Button value changed to : \(value[0])")
        delegate?.buttonStateChanged(isPressed: value[0] == 0x1)
    }
    
    
}



// MARK: NSObject protocols

extension ThingyPeripheral {
    
    override func isEqual(_ object: Any?) -> Bool {
        if object is ThingyPeripheral {
            let peripheralObject = object as! ThingyPeripheral
            return peripheralObject.basePeripheral.identifier == basePeripheral.identifier
        } else if object is CBPeripheral {
            let peripheralObject = object as! CBPeripheral
            return peripheralObject.identifier == basePeripheral.identifier
        } else {
            return false
        }
    }
}



// MARK: Delegates for CBCentralManagerDelegate

extension ThingyPeripheral {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("Central Manager state changed to \(central.state)")
            
            delegate?.thingyDidDisconnect()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if ( peripheral == basePeripheral) {
            print("Connected to Thingy 52.")
            
            discoverThingyServices()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == basePeripheral {
            print("Thingy 52 disconnected.")
            
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
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == ThingyPeripheral.buttonCharacteristicUUID {
            print("Button notification enabled.")
            
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
                    print("Thingy 52 Service found")
                    
                    // Capture and discover all characteristics for Thingy service
                    discoverCharacteristicsForThingyService(service)
                    return
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == ThingyPeripheral.ledCharacteristicUUID {
                    print("LED Characteristic found")
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
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        // LED value has been written, let's read it to confirm
        readLEDValue()
    }
}
