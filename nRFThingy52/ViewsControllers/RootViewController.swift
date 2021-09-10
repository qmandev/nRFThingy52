//
//  RootViewController.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/25/21.
//

import UIKit

class RootViewController: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //view.backgroundColor = .systemRed
        
        let navBarAppearance = UINavigationBarAppearance()
        
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.dynamicColor(light: .nordicBlue, dark: .black)
        navBarAppearance.titleTextAttributes = [.foregroundColor : UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor : UIColor.white]
        navigationBar.standardAppearance = navBarAppearance
        navigationBar.scrollEdgeAppearance = navBarAppearance
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        UIStatusBarStyle.lightContent
    }
    
    


}

