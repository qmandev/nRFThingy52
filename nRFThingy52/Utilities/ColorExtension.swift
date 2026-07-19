//
//  ColorExtension.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/19/26.
//

import SwiftUI

/// SwiftUI bridge for the Nordic palette defined in UIColorExtension.swift,
/// which remains the single source of truth for the color values.
extension Color {

    static let nordicBlue = Color(UIColor.nordicBlue)
    static let nordicSky = Color(UIColor.nordicSky)
    static let nordicLake = Color(UIColor.nordicLake)
    static let nordicRed = Color(UIColor.nordicRed)
    static let nordicSun = Color(UIColor.nordicSun)
    static let nordicFall = Color(UIColor.nordicFall)

    // Nav bar styling lives in ThingyApp.init via UINavigationBarAppearance.
}
