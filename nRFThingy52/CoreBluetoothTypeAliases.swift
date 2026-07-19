//
//  CoreBluetoothTypeAliases.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//
//  Aliases the CoreBluetoothMock types to their CoreBluetooth names, so the
//  rest of the app compiles against the mockable layer without renaming.
//  CBMCentralManagerFactory returns the native implementation on physical
//  devices and the mock on the simulator. Pattern follows Nordic's nRF Blinky
//  example in the CoreBluetoothMock repository.
//

import CoreBluetoothMock

typealias CBCentralManagerFactory   = CBMCentralManagerFactory
typealias CBUUID                    = CBMUUID
typealias CBError                   = CBMError
typealias CBManagerState            = CBMManagerState
typealias CBPeripheralState         = CBMPeripheralState
typealias CBCentralManager          = CBMCentralManager
typealias CBCentralManagerDelegate  = CBMCentralManagerDelegate
typealias CBPeripheral              = CBMPeripheral
typealias CBPeripheralDelegate      = CBMPeripheralDelegate
typealias CBService                 = CBMService
typealias CBCharacteristic          = CBMCharacteristic
typealias CBCharacteristicWriteType = CBMCharacteristicWriteType
typealias CBDescriptor              = CBMDescriptor

let CBCentralManagerScanOptionAllowDuplicatesKey = CBMCentralManagerScanOptionAllowDuplicatesKey
let CBAdvertisementDataLocalNameKey              = CBMAdvertisementDataLocalNameKey
let CBAdvertisementDataServiceUUIDsKey           = CBMAdvertisementDataServiceUUIDsKey
let CBAdvertisementDataIsConnectable             = CBMAdvertisementDataIsConnectable
