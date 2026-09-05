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

    @MainActor func testLibraryPlaybackAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = try XCTUnwrap(Bundle(for: OtoUITests.self).resourceURL).path
        app.launchArguments = ["--reset-library"]
        app.launch()
        let album = app.buttons["album-Quiet Hours"]
        XCTAssertTrue(album.waitForExistence(timeout: 90))
        attach(app, name: "Library")
        album.tap()
        XCTAssertTrue(app.buttons["track-First Light"].waitForExistence(timeout: 10))
        attach(app, name: "Album")
        app.buttons["track-First Light"].tap()
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
        app.buttons["now-playing-next"].tap()
        XCTAssertTrue(app.staticTexts["Second Light"].waitForExistence(timeout: 10))
        expectation(for: playing, evaluatedWith: toggle)
        waitForExpectations(timeout: 15)
        toggle.tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "OTO_MUSIC_FOLDER")
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(album.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mini-player"].exists)
    }

    @MainActor func testLargeTextLibraryAndAlbum() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = try XCTUnwrap(Bundle(for: OtoUITests.self).resourceURL).path
        app.launchArguments = ["--reset-library", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let album = app.buttons["album-Quiet Hours"]
        XCTAssertTrue(album.waitForExistence(timeout: 20))
        attach(app, name: "Large Text Library")
        album.tap()
        let play = app.buttons["play-album"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        for _ in 0..<4 where !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.isHittable)
        attach(app, name: "Large Text Album")
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
