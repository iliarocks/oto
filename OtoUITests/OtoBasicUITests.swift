import XCTest

/// Covers the native setup flow without sharing files across app sandboxes.
final class OtoBasicUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testEmptyLibraryAndNativeFolderPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchArguments = ["--reset-library"]
        app.launch()
        XCTAssertTrue(app.buttons["choose-folder"].waitForExistence(timeout: 10))
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.isHittable)
        XCTAssertLessThan(settings.frame.midX, app.frame.midX)
        XCTAssertFalse(app.buttons["library-options"].exists)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.links["settings-privacy"].exists)
        XCTAssertTrue(app.links["settings-support"].exists)
        app.buttons["settings-choose-folder"].tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 10) || app.buttons["Browse"].exists)
    }

}
