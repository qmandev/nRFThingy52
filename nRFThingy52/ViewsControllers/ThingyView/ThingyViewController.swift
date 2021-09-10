//
//  ThingyViewController.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/26/21.
//

import UIKit
import CoreBluetooth

class ThingyViewController: UITableViewController, ThingyDelegate {
    
    // MARK: IBOutlets and IBActions
    @IBOutlet weak var ledStateLabel : UILabel!
    @IBOutlet weak var ledToggleSwitch : UISwitch!
    @IBOutlet weak var buttonStateLabel : UILabel!
    
    @IBAction func ledToggleSwitchDidChange(_ sender: Any) {
        handleSwitchValueChange(newValue: ledToggleSwitch.isOn)
    }
    
    // MARK: - Properties
    
    private var hapticGenerator : NSObject?
    private var thingyPeripheral : ThingyPeripheral!
    private var centralManager : CBCentralManager!
    
    
    // MARK: - Public API
    
    public func setPeripheral(_ peripheral : ThingyPeripheral) {
        thingyPeripheral = peripheral
        title = thingyPeripheral?.advertisedName
        peripheral.delegate = self
    }
    
    
    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !thingyPeripheral.isConnected else {
            // View is coming back from a swipe, everything is already setup
            return
        }
        
        prepareHaptics()
        thingyPeripheral.connect()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        thingyPeripheral.disConnect()
        super.viewDidAppear(animated)
    }
    
    
    // MARK: - Implementations
    
    /// This will run on iOS 10 or above
    /// and will generate a tap feedback when the button is tapped on the Dev kit.
    private func prepareHaptics() {
        hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
        (hapticGenerator as? UIImpactFeedbackGenerator)?.prepare()
    }
    
    private func handleSwitchValueChange(newValue isOn: Bool) {
        if isOn {
            thingyPeripheral.turnOnLED()
            self.ledStateLabel.text = "ON".localized
        } else {
            thingyPeripheral.turnOffLED()
            self.ledStateLabel.text = "OFF".localized
        }
    }
    
    /// Generates a tap feedback
    func buttonTapHapticFeedback() {
        (hapticGenerator as? UIImpactFeedbackGenerator)?.impactOccurred()
    }
    
}



// MARK: - ThingyDelegate methods

extension ThingyViewController {
    
    func thingyDidConnect(ledSupported: Bool, buttonSupported: Bool) {
        
        DispatchQueue.main.async {
            self.ledToggleSwitch?.isOn = ledSupported
            
            if buttonSupported {
                self.buttonStateLabel.text = "Scanning...".localized
            } else if ledSupported {
                self.ledStateLabel.text = "Scanning...".localized
            }
        }
        
        // If Not supported device, not support both led/button ,then disconnect the peripheral
        if !buttonSupported && !ledSupported {
            thingyPeripheral.disConnect()
        }
    }
    
    func thingyDidDisconnect() {
        
        DispatchQueue.main.async {
            self.navigationController?.navigationBar.tintColor = UIColor.nordicRed
            self.ledToggleSwitch.onTintColor = UIColor.nordicRed
            self.ledToggleSwitch.isEnabled = false
        }
    }
    
    func buttonStateChanged(isPressed: Bool) {
        
        DispatchQueue.main.async {
            if isPressed {
                self.buttonStateLabel.text = "PRESSED".localized
            } else {
                self.buttonStateLabel.text = "RELEASED".localized
            }
            
            self.buttonTapHapticFeedback()
        }
    }
    
    func ledStateChanged(isOn: Bool) {
        
        DispatchQueue.main.async {
            if isOn {
                self.ledStateLabel.text = "ON".localized
                self.ledToggleSwitch.setOn(true, animated: true)
            } else {
                self.ledStateLabel.text = "OFF".localized
                self.ledToggleSwitch.setOn(false, animated: true)
            }
        }
    }
}
