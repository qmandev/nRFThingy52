//
//  nRFThingy52UITests.swift
//  nRFThingy52UITests
//
//  Created by Qiang Ma on 7/25/21.
//

import XCTest

class nRFThingy52UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Drives the simulator app (with its mocked Thingy:52) from scanner to
    /// the detail screen and verifies the environment dashboard renders.
    @MainActor
    func testEnvironmentDashboardShows() throws {
        let app = XCUIApplication()
        app.launch()

        let mockRow = app.staticTexts["Thingy52 Mock"]
        XCTAssertTrue(mockRow.waitForExistence(timeout: 10), "Mock Thingy should be discovered")
        mockRow.tap()

        XCTAssertTrue(app.staticTexts["Temperature"].waitForExistence(timeout: 10),
                      "Environment dashboard should appear once readings stream")
        XCTAssertTrue(app.staticTexts["Humidity"].exists)
        XCTAssertTrue(app.staticTexts["Pressure"].exists)
        XCTAssertTrue(app.staticTexts["Air Quality"].exists)

        // Hold the screen briefly so an external screenshot can capture it.
        Thread.sleep(forTimeInterval: 8)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
