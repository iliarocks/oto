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
        XCTAssertTrue(toggle.isHittable)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        attach(app, name: "Large Text Fixed Now Playing")
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
    }

    @MainActor func testFloatingPlayerAndModalDismissal() throws {
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
        XCTAssertTrue(app.buttons["now-playing-toggle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["now-playing-album"].exists)
        XCTAssertFalse(app.staticTexts["Opening song…"].exists)
        attach(app, name: "Artwork Accents in Now Playing")
        let toggle = app.buttons["now-playing-toggle"]
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
        app.navigationBars["Now Playing"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(app.staticTexts["library-summary"].waitForExistence(timeout: 10))
        app.buttons["album-Quiet Hours"].tap()
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
        app.navigationBars["Now Playing"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        app.buttons["album-Quiet Hours"].firstMatch.tap()
        app.buttons["track-Second Light"].tap()
        app.buttons["mini-player"].tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
    }

    @MainActor func testLongTitlesCarouselAndSheetDismisses() async throws {
        let title = "A Song With A Very Long Name That Continues Beyond The Edge Of Both Players"
        let albumName = "An Album With A Long Name That Also Needs To Stay On One Line"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = folder.appendingPathComponent(albumName)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: folder) }
        // Original silent PCM fixture; the filename/folder exercise untagged titles.
        let byteCount = 44_100 * 2 * 60
        func little(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var wav = Data("RIFF".utf8)
        wav.append(little(UInt32(byteCount + 36)))
        wav.append(Data("WAVEfmt ".utf8)); wav.append(little(16))
        wav.append(contentsOf: [1, 0, 1, 0]); wav.append(little(44_100)); wav.append(little(88_200))
        wav.append(contentsOf: [2, 0, 16, 0]); wav.append(Data("data".utf8)); wav.append(little(UInt32(byteCount)))
        wav.append(Data(count: byteCount))
        try wav.write(to: album.appendingPathComponent(title + ".wav"))
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = folder.path
        app.launchArguments = ["--reset-library"]
        app.launch()
        let row = app.buttons["album-" + albumName]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        app.buttons["play-album"].tap()
        let mini = app.buttons["mini-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        let miniBefore = mini.screenshot().pngRepresentation
        try await Task.sleep(for: .seconds(3))
        XCTAssertNotEqual(miniBefore, mini.screenshot().pngRepresentation, "The mini player's overflowing title must move")
        attach(app, name: "Padded Mini Player with Long Title")
        mini.tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(app.sliders["playback-position"].isHittable)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["Close"].exists)
        let label = app.staticTexts["now-playing-title"]
        XCTAssertEqual(label.label, title)
        let before = label.screenshot().pngRepresentation
        attach(app, name: "Fixed Now Playing Long Title Start")
        try await Task.sleep(for: .seconds(3))
        XCTAssertNotEqual(before, label.screenshot().pngRepresentation, "An overflowing title must move")
        attach(app, name: "Fixed Now Playing Long Title Moving")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        let scrubber = app.sliders["playback-position"]
        scrubber.adjust(toNormalizedSliderPosition: 0.5)
        let value = scrubber.value as? String ?? ""
        XCTAssertTrue((27...33).map { "0:\($0)" }.contains(value), "Seeking should move playback to the midpoint: \(value)")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(app.sliders["playback-position"].isHittable)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Fixed Landscape Now Playing"
        landscape.lifetime = .keepAlways
        add(landscape)
        XCUIDevice.shared.orientation = .portrait
        app.navigationBars["Now Playing"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
    }

    @MainActor func testLastSongClearsFloatingPlayer() throws {
        try checkLastSongClearsPlayer(largeText: false)
    }

    @MainActor func testLastSongClearsFloatingPlayerWithLargeText() throws {
        try checkLastSongClearsPlayer(largeText: true)
    }

    @MainActor private func checkLastSongClearsPlayer(largeText: Bool) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = XCUIApplication()
        defer { app.terminate(); try? FileManager.default.removeItem(at: folder) }
        let first = try XCTUnwrap(Bundle(for: OtoUITests.self).url(forResource: "01", withExtension: "flac"))
        let last = try XCTUnwrap(Bundle(for: OtoUITests.self).url(forResource: "02", withExtension: "flac"))
        for index in 1...12 {
            try FileManager.default.copyItem(at: first, to: folder.appendingPathComponent("\(index).flac"))
        }
        try FileManager.default.copyItem(at: last, to: folder.appendingPathComponent("last.flac"))
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = folder.path
        app.launchArguments = ["--reset-library"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let album = app.buttons["album-Quiet Hours"]
        XCTAssertTrue(album.waitForExistence(timeout: 20))
        album.tap()
        let toolbarTitle = app.navigationBars.staticTexts["Quiet Hours"]
        XCTAssertFalse(toolbarTitle.exists)
        attach(app, name: "Album Without Duplicate Toolbar Title")
        let play = app.buttons["play-album"]
        for _ in 0..<4 where !play.isHittable { app.swipeUp() }
        play.tap()
        let mini = app.buttons["mini-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        let finalSong = app.buttons["track-Second Light"]
        for _ in 0..<12 {
            if finalSong.exists && finalSong.frame.maxY < mini.frame.minY - 8 { break }
            app.swipeUp()
        }
        attach(app, name: largeText ? "Final Song Above Large Player" : "Final Song Above Player")
        XCTAssertTrue(toolbarTitle.exists, "The toolbar identifies the album after its main title scrolls away")
        XCTAssertTrue(finalSong.isHittable)
        XCTAssertLessThan(finalSong.frame.maxY, mini.frame.minY - 8, "The complete last row must clear the floating player")
        finalSong.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Second Light'"), evaluatedWith: mini)
        waitForExpectations(timeout: 10)
        mini.tap()
        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'Pause'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
        app.navigationBars["Now Playing"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        let mainTitle = app.staticTexts["album-main-title"]
        for _ in 0..<12 {
            if mainTitle.exists && mainTitle.frame.minY >= app.navigationBars.firstMatch.frame.maxY { break }
            app.swipeDown()
        }
        XCTAssertTrue(mainTitle.isHittable)
        XCTAssertFalse(toolbarTitle.exists, "Returning to the main album title hides the duplicate toolbar title")
        attach(app, name: "Main Album Title Restored After Scrolling Back")
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
