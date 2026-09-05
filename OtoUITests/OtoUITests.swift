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
        XCTAssertEqual(toggle.label, "Play")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
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

    @MainActor func testSearchPlaysSongDirectlyAndLinksBackToAlbum() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = try XCTUnwrap(Bundle(for: OtoUITests.self).resourceURL).path
        app.launchArguments = ["--reset-library"]
        app.launch()
        XCTAssertTrue(app.buttons["album-Quiet Hours"].waitForExistence(timeout: 20))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Second Light")
        let song = app.buttons["search-song-Second Light"]
        XCTAssertTrue(song.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["album-Quiet Hours"].exists)
        attach(app, name: "Direct Song Search")
        song.tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["now-playing-album"].waitForExistence(timeout: 10))
        let toggle = app.buttons["now-playing-toggle"]
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
        app.buttons["now-playing-album"].tap()
        XCTAssertTrue(app.buttons["track-Second Light"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["track-Second Light"].value as? String, "Paused")
        attach(app, name: "Return to Playing Album")
    }

    @MainActor func testSkippedFileIsDiscoverableAndFolderCanBeChanged() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: folder) }
        let source = try XCTUnwrap(Bundle(for: OtoUITests.self).url(forResource: "01", withExtension: "flac"))
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("01.flac"))
        try Data("incomplete audio file".utf8).write(to: folder.appendingPathComponent("broken.flac"))
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = folder.path
        app.launchArguments = ["--reset-library"]
        app.launch()
        let issue = app.buttons["library-issues"]
        XCTAssertTrue(issue.waitForExistence(timeout: 20))
        attach(app, name: "Library with Skipped File")
        issue.tap()
        XCTAssertTrue(app.staticTexts["broken.flac"].waitForExistence(timeout: 10))
        app.buttons["choose-another-folder"].tap()
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 10) || app.navigationBars["Browse"].exists)
    }

    @MainActor func testEmptySelectedFolderOffersRefreshAndRecovers() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: folder) }
        let source = try XCTUnwrap(Bundle(for: OtoUITests.self).url(forResource: "01", withExtension: "flac"))
        let destination = folder.appendingPathComponent("01.flac")
        try FileManager.default.copyItem(at: source, to: destination)
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = folder.path
        app.launchArguments = ["--reset-library"]
        app.launch()
        let album = app.buttons["album-Quiet Hours"]
        XCTAssertTrue(album.waitForExistence(timeout: 20))
        try FileManager.default.removeItem(at: destination)
        app.buttons["library-options"].tap()
        app.buttons["Refresh Library"].tap()
        let refresh = app.buttons["refresh-empty-library"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        attach(app, name: "Empty Selected Folder")
        try FileManager.default.copyItem(at: source, to: destination)
        refresh.tap()
        XCTAssertTrue(album.waitForExistence(timeout: 10))
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
