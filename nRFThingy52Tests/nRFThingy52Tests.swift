//
//  nRFThingy52Tests.swift
//  nRFThingy52Tests
//
//  Created by Qiang Ma on 7/25/21.
//

import XCTest
@testable import nRFThingy52

class nRFThingy52Tests: XCTestCase {

    // MARK: - UIColor hex parsing

    func testHexInit6Digit() throws {
        let color = UIColor(hexString: "#FF0000")
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 1.0, accuracy: 0.001)
        XCTAssertEqual(green, 0.0, accuracy: 0.001)
        XCTAssertEqual(blue, 0.0, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)
    }

    func testHexInit3Digit() throws {
        let color = UIColor(hexString: "#0F0")
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 0.0, accuracy: 0.001)
        XCTAssertEqual(green, 1.0, accuracy: 0.001)
        XCTAssertEqual(blue, 0.0, accuracy: 0.001)
    }

    func testHexInitAlpha() throws {
        let color = UIColor(hexString: "336699", alpha: 0.5)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 0.5, accuracy: 0.01)
    }

    func testHexStringRoundTrip() throws {
        XCTAssertEqual(UIColor(hexString: "#336699").hexString, "#336699")
        XCTAssertEqual(UIColor(red: 1, green: 1, blue: 1, alpha: 1).hexString, "#FFFFFF")
        XCTAssertEqual(UIColor(red: 0, green: 0, blue: 0, alpha: 1).hexString, "#000000")
    }

    func testDynamicColorResolvesPerStyle() throws {
        let dynamic = UIColor.dynamicColor(light: .white, dark: .black)
        let light = dynamic.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = dynamic.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }

    // MARK: - String localization

    func testLocalizedReturnsKeyForUnknownString() throws {
        // NSLocalizedString falls back to the key when no translation exists.
        XCTAssertEqual("THIS_KEY_DOES_NOT_EXIST".localized, "THIS_KEY_DOES_NOT_EXIST")
    }

}
