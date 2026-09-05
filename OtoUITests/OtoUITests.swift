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
        play.tap()
        let miniPlayer = app.buttons["mini-player"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10))
        XCTAssertTrue(miniPlayer.isHittable)
        attach(app, name: "Large Text Floating Player")
        miniPlayer.tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
    }

    @MainActor func testFloatingPlayerAndLinkBackToAlbum() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = try XCTUnwrap(Bundle(for: OtoUITests.self).resourceURL).path
        app.launchArguments = ["--reset-library"]
        app.launch()
        XCTAssertTrue(app.buttons["album-Quiet Hours"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Library"].exists)
        XCTAssertEqual(app.staticTexts["library-summary"].label, "1 album · 2 songs")
        app.buttons["album-Quiet Hours"].tap()
        app.buttons["track-Second Light"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        attach(app, name: "Floating Player on Album")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["library-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mini-player"].isHittable)
        attach(app, name: "Simplified Library with Floating Player")
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

    @MainActor func testUnavailableSongCanRetryFromLibraryAndNowPlaying() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: folder) }
        let sources = try ["01", "02"].map { name in
            try XCTUnwrap(Bundle(for: OtoUITests.self).url(forResource: name, withExtension: "flac"))
        }
        let destinations = ["01.flac", "02.flac"].map { folder.appendingPathComponent($0) }
        for (source, destination) in zip(sources, destinations) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = folder.path
        app.launchArguments = ["--reset-library"]
        app.launch()
        let album = app.buttons["album-Quiet Hours"]
        XCTAssertTrue(album.waitForExistence(timeout: 20))
        try FileManager.default.removeItem(at: destinations[0])
        album.tap()
        app.buttons["track-First Light"].tap()
        XCTAssertTrue(app.alerts["Couldn't Play"].waitForExistence(timeout: 10))
        attach(app, name: "Retry Missing Song")
        try FileManager.default.copyItem(at: sources[0], to: destinations[0])
        app.alerts.buttons["Try Again"].tap()
        app.buttons["mini-player"].tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
        try FileManager.default.removeItem(at: destinations[1])
        app.buttons["now-playing-next"].tap()
        XCTAssertTrue(app.alerts["Couldn't Play"].waitForExistence(timeout: 10))
        attach(app, name: "Retry from Now Playing")
        try FileManager.default.copyItem(at: sources[1], to: destinations[1])
        app.alerts.buttons["Try Again"].tap()
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["Second Light"].exists)
        toggle.tap()
    }

    @MainActor func testLargerFolderBrowsingAndPlayback() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: folder) }
        let sources = try ["01", "02"].map {
            try XCTUnwrap(Bundle(for: OtoUITests.self).url(forResource: $0, withExtension: "flac"))
        }
        for number in 1...200 {
            let album = folder.appendingPathComponent("Album \(number)")
            try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
            for source in sources {
                try FileManager.default.copyItem(at: source, to: album.appendingPathComponent(source.lastPathComponent))
            }
        }
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = folder.path
        app.launchArguments = ["--reset-library"]
        app.launch()
        XCTAssertTrue(app.staticTexts["200 albums · 400 songs"].waitForExistence(timeout: 60))
        app.swipeUp()
        app.swipeDown()
        app.buttons["album-Quiet Hours"].firstMatch.tap()
        app.buttons["track-Second Light"].tap()
        app.buttons["mini-player"].tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
