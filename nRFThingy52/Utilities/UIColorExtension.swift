//
//  UIColorExtension.swift
//  nRFThingy52
//
//  Created by Qiang Ma on 7/25/21.
//

import UIKit

extension UIColor {
    
    static let nordicBlue = #colorLiteral(red: 0, green: 0.7181802392, blue: 0.8448022008, alpha: 1)
    
    static let nordicSky = #colorLiteral(red: 0.4773202538, green: 0.8505803943, blue: 0.9124827981, alpha: 1)
    
    static let nordicLake = #colorLiteral(red: 0, green: 0.5483048558, blue: 0.8252354264, alpha: 1)
    
    static let nordicLakeDark = #colorLiteral(red: 0, green: 0.4745001793, blue: 0.7173394561, alpha: 1)
    
    static let nordicBlueslate = #colorLiteral(red: 0, green: 0.2858072221, blue: 0.6897063851, alpha: 1)
    
    static let nordicLightGray = #colorLiteral(red: 0.8790807724, green: 0.9051030278, blue: 0.9087315202, alpha: 1)
    
    static let nordicMediumGray = #colorLiteral(red: 0.5353743434, green: 0.5965531468, blue: 0.6396299005, alpha: 1)
    
    static let nordicDarkGray = #colorLiteral(red: 0.2590435743, green: 0.3151275516, blue: 0.353839159, alpha: 1)
    
    static let nordicGrass = #colorLiteral(red: 0.8486783504, green: 0.8850693107, blue: 0, alpha: 1)
    
    static let nordicSun = #colorLiteral(red: 1, green: 0.8319787979, blue: 0, alpha: 1)
    
    static let nordicRed = #colorLiteral(red: 0.9567440152, green: 0.2853084803, blue: 0.3770255744, alpha: 1)
    
    static let nordicFall = #colorLiteral(red: 0.9759463668, green: 0.5845184922, blue: 0.1595045924, alpha: 1)
    
    static let error = nordicRed
    
    convenience init(hexString: String, alpha: Double = 1.0) {
        let hex = hexString.trimmingCharacters(in: NSCharacterSet.alphanumerics.inverted)
        let intVal = UInt32(hex, radix: 16) ?? 0
        let r, g, b: UInt32
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((intVal >> 8) * 17, (intVal >> 4 & 0xF) * 17, (intVal & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (intVal >> 16, intVal >> 8 & 0xFF, intVal & 0xFF)
        default:
            (r, g, b) = (1, 1, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(255 * alpha) / 255)
    }
    
    static func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
        if #available(iOS 13.0, *) {
            return UIColor { (traitCollection) -> UIColor in
                return traitCollection.userInterfaceStyle == .light ? light : dark
            }
        } else {
            return light
        }
    }
    
    static var random: UIColor {
        let randomRed:   CGFloat = CGFloat(arc4random()) / CGFloat(UInt32.max)
        let randomGreen: CGFloat = CGFloat(arc4random()) / CGFloat(UInt32.max)
        let randomBlue:  CGFloat = CGFloat(arc4random()) / CGFloat(UInt32.max)
        return UIColor(red: randomRed, green: randomGreen, blue: randomBlue, alpha: 1.0)
    }
    
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(red) * 255), lroundf(Float(green) * 255), lroundf(Float(blue) * 255))
    }
    
}
