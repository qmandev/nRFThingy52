//
//  ScannerTableViewCell.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/26/21.
//

import UIKit

class ScannerTableViewCell: UITableViewCell {
    
    // MARK: - Outlets and Actions
    
    @IBOutlet weak var peripheralName : UILabel!
    @IBOutlet weak var peripheralRSSIIcon : UIImageView!

    // MARK: - Properties
    
    public static let reuseidentifer = "thingyPeripheralCell"
    
    private var lastUpdateTimestamp = Date()
    
    // MARK: - Implementation
    
    public func setupView(withPeripheral aPeripheral: ThingyPeripheral) {
        peripheralName.text = aPeripheral.advertisedName
        
        if aPeripheral.RSSI.decimalValue < -60 {
            peripheralRSSIIcon.image = #imageLiteral(resourceName: "rssi_2")
        } else if aPeripheral.RSSI.decimalValue < -50 {
            peripheralRSSIIcon.image = #imageLiteral(resourceName: "rssi_3")
        } else if aPeripheral.RSSI.decimalValue < -30 {
            peripheralRSSIIcon.image = #imageLiteral(resourceName: "rssi_4")
        } else {
            peripheralRSSIIcon.image = #imageLiteral(resourceName: "rssi_1")
        }
    }
    
    public func peripheralUpdatedAdvertisementData(_ aPeripheral: ThingyPeripheral) {
        
        if Date().timeIntervalSince(lastUpdateTimestamp) > 1.0 {
            lastUpdateTimestamp = Date()
            setupView(withPeripheral: aPeripheral)
        }
    }
    

}
