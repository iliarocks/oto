import XCTest

final class OtoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testEmptyLibraryAndNativeFolderPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchArguments = ["--reset-library"]
        app.launch()
        XCTAssertTrue(app.buttons["choose-folder"].waitForExistence(timeout: 10))
        app.buttons["choose-folder"].tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 10) || app.buttons["Browse"].exists)
    }

    @MainActor func testRealLibraryPlaybackAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = "/Users/shmilia/Library/Mobile Documents/com~apple~CloudDocs/music"
        app.launchArguments = ["--reset-library"]
        app.launch()
        let album = app.buttons["album-Fake It Flowers"]
        XCTAssertTrue(album.waitForExistence(timeout: 90))
        attach(app, name: "Library")
        album.tap()
        XCTAssertTrue(app.buttons["track-Care"].waitForExistence(timeout: 10))
        attach(app, name: "Album")
        app.buttons["track-Care"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        app.buttons["mini-player"].tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let playing = NSPredicate(format: "label == 'Pause'")
        expectation(for: playing, evaluatedWith: toggle)
        waitForExpectations(timeout: 15)
        attach(app, name: "Now Playing")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        app.buttons["Next Song"].tap()
        XCTAssertTrue(app.staticTexts["Worth It"].waitForExistence(timeout: 10))
        toggle.tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "OTO_MUSIC_FOLDER")
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(album.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mini-player"].exists)
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
