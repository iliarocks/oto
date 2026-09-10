import XCTest

final class AppStoreCaptureTests: XCTestCase {
    @MainActor func testCaptureFourPages() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = "/Users/shmilia/Library/Mobile Documents/com~apple~CloudDocs/music"
        app.launchArguments = ["--reset-library"]
        app.launch()
        let album = app.buttons["album-Modal Soul"]
        XCTAssertTrue(album.waitForExistence(timeout: 180))
        album.tap()
        let feather = app.buttons["track-Feather"]
        XCTAssertTrue(feather.waitForExistence(timeout: 15))
        feather.tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 15))
        // Capture the same real collection and selected album across all pages.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(album.waitForExistence(timeout: 10))
        capture("01-library")
        album.tap()
        XCTAssertTrue(feather.waitForExistence(timeout: 10))
        capture("02-album")
        // Two manual additions make the queue's purpose visible.
        for title in ["reflection eternal", "Luv(sic.) pt3"] {
            let row = app.buttons["track-\(title)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            for _ in 0..<6 {
                let frame = row.frame
                if row.isHittable && frame.minY > 130 && frame.maxY < app.frame.height - 170 { break }
                let list = app.collectionViews.firstMatch
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let end = start.withOffset(CGVector(dx: 0, dy: frame.minY < 130 ? 180 : -180))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            row.swipeLeft()
            let add = app.buttons["Add to Queue"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
        }
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["now-playing-toggle"].waitForExistence(timeout: 10))
        let slider = app.sliders["playback-position"]
        if slider.waitForExistence(timeout: 5) { slider.adjust(toNormalizedSliderPosition: 0.35) }
        capture("03-now-playing")
        app.buttons["queue-toggle"].tap()
        XCTAssertTrue(app.staticTexts["Queued"].waitForExistence(timeout: 10))
        capture("04-queue")
        app.terminate()
    }
    @MainActor func testCaptureWebsiteDark() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OTO_UI_TEST"] = "1"
        app.launchEnvironment["OTO_MUSIC_FOLDER"] = "/Users/shmilia/Library/Mobile Documents/com~apple~CloudDocs/music"
        app.launchArguments = ["--reset-library"]
        app.launch()
        let album = app.buttons["album-Modal Soul"]
        XCTAssertTrue(album.waitForExistence(timeout: 180))
        album.tap()
        let feather = app.buttons["track-Feather"]
        XCTAssertTrue(feather.waitForExistence(timeout: 15))
        feather.tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(album.waitForExistence(timeout: 10))
        capture("hero-dark")
        app.terminate()
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
