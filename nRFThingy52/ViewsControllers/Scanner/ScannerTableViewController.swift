//
//  ScannerTableViewController.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/26/21.
//

import UIKit
import CoreBluetooth
import os

class ScannerTableViewController: UITableViewController, CBCentralManagerDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nRFThingy52", category: "Scanner")
    
    // MARK: - IBActions, IBOutlets
    @IBOutlet weak var activityIndicator : UIActivityIndicatorView!
    @IBOutlet weak var emptyPeripheralsView : UIView!
    
    
    // MARK: - Properties
    
    private var centralManager : CBCentralManager!
    private var discoveredPeripherals = [ThingyPeripheral]()

    /// The peripheral the user selected. The scanner stays the central manager's
    /// delegate for the whole app lifetime and forwards connection events here.
    private var selectedPeripheral : ThingyPeripheral?

    // MARK: - ViewController Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Keep the scanning indicator free-floating on the nav bar instead of
        // inside the Liquid Glass capsule iOS 26 draws behind bar button items.
        if #available(iOS 26.0, *) {
            navigationItem.rightBarButtonItem?.hidesSharedBackground = true
        }

        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        discoveredPeripherals.removeAll()
        tableView.reloadData()
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        navigationController?.navigationBar.barTintColor = UIColor.nordicBlue

        if centralManager.state == .poweredOn {
            activityIndicator.startAnimating()
            centralManager.scanForPeripherals(withServices: [ThingyPeripheral.nordicThingyServiceUUID],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
    }
    
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if view.subviews.contains(emptyPeripheralsView) {
            coordinator.animate(alongsideTransition: { (context) in
                let width = self.emptyPeripheralsView.frame.width
                let height = self.emptyPeripheralsView.frame.height
                if context.containerView.frame.height > context.containerView.frame.width {
                    self.emptyPeripheralsView.frame = CGRect(x: 0,
                                                             y: (context.containerView.frame.height / 2) - 180,
                                                             width: width,
                                                             height: height)
                } else {
                    self.emptyPeripheralsView.frame = CGRect(x: 0,
                                                             y: 16,
                                                             width: width,
                                                             height: height)
                }
            })
        }
    }

     // MARK: - Navigation and Segue
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "PushThingyView" {
            if let peripheral = sender as? ThingyPeripheral {
                if let destinViewController = segue.destination as? ThingyViewController {
                    destinViewController.setPeripheral(peripheral)
                }
            }
        }
     }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return identifier == "PushThingyView"
    }
    
    // MARK: - Implementation
    
    private func showEmptyPeripheralsView() {
        if !view.subviews.contains(emptyPeripheralsView) {
            view.addSubview(emptyPeripheralsView)
            emptyPeripheralsView.alpha = 0
            emptyPeripheralsView.frame = CGRect(x: 0,
                                                y: (view.frame.height / 2) - 180,
                                                width: view.frame.width,
                                                height: emptyPeripheralsView.frame.height)
            view.bringSubviewToFront(emptyPeripheralsView)
            UIView.animate(withDuration: 0.5, animations: {
                self.emptyPeripheralsView.alpha = 1
            })
        }
    }
    
    private func hideEmptyPeripheralsView() {
        if view.subviews.contains(emptyPeripheralsView) {
            UIView.animate(withDuration: 0.5, animations: {
                self.emptyPeripheralsView.alpha = 0
            }, completion: { completed in
                self.emptyPeripheralsView.removeFromSuperview()
            })
        }
    }

}


// MARK: - UITableViewDelegate, UITableViewDataSource delegate methods

extension ScannerTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {

        if discoveredPeripherals.count > 0 {
            hideEmptyPeripheralsView()
        } else {
            showEmptyPeripheralsView()
        }
        return discoveredPeripherals.count > 0 ? 1 : 0
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return discoveredPeripherals.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ScannerTableViewCell.reuseIdentifier,
                                                 for: indexPath) as! ScannerTableViewCell
        
        cell.setupView(withPeripheral: discoveredPeripherals[indexPath.row])
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Nearby Devices".localized
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        centralManager.stopScan()
        activityIndicator.stopAnimating()
        
        tableView.deselectRow(at: indexPath, animated: true)
        selectedPeripheral = discoveredPeripherals[indexPath.row]
        performSegue(withIdentifier: "PushThingyView", sender: selectedPeripheral)
    }
    
}


// MARK: - CentralManagerDelegate methods

extension ScannerTableViewController {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        selectedPeripheral?.centralManagerDidUpdateState(central)

        if central.state != .poweredOn {
            logger.debug("Central is not powered on.")
        } else if view.window != nil {
            // Only scan while the scanner is on screen; viewDidAppear
            // restarts the scan when the user comes back.
            activityIndicator.startAnimating()
            centralManager.scanForPeripherals(withServices: [ThingyPeripheral.nordicThingyServiceUUID],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        selectedPeripheral?.centralManager(central, didConnect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        selectedPeripheral?.centralManager(central, didFailToConnect: peripheral, error: error)
        if selectedPeripheral?.isEqual(peripheral) == true {
            selectedPeripheral = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        selectedPeripheral?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
        if selectedPeripheral?.isEqual(peripheral) == true {
            selectedPeripheral = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        let newPeripheral = ThingyPeripheral(withPeripheral: peripheral, advertisementData: advertisementData, andRSSI: RSSI, using: centralManager)
        if !discoveredPeripherals.contains(newPeripheral) {
            discoveredPeripherals.append(newPeripheral)
            tableView.beginUpdates()
            if discoveredPeripherals.count == 1 {
                tableView.insertSections(IndexSet(integer: 0), with: .fade)
            }
            tableView.insertRows(at: [IndexPath(row: discoveredPeripherals.count - 1, section: 0)], with: .fade)
            tableView.endUpdates()
        } else {
            if let index = discoveredPeripherals.firstIndex(of: newPeripheral) {
                if let aCell = tableView.cellForRow(at: [0, index]) as? ScannerTableViewCell {
                    aCell.peripheralUpdatedAdvertisementData(newPeripheral)
                }
            }
        }

    }
}

