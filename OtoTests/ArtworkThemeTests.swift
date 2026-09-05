import UIKit
import XCTest
@testable import Oto

final class ArtworkThemeTests: XCTestCase {
    @MainActor func testArtworkSelectsDominantColorAndHandlesMissingImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let palette = ArtworkPalette()
        for (name, dominant) in [("red", UIColor.red), ("blue", UIColor.blue)] {
            let data = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).pngData { context in
                dominant.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 32))
            }
            let url = directory.appendingPathComponent(name + ".png")
            try data.write(to: url)
            let result = await palette.read(url)
            let color = try XCTUnwrap(result)
            if name == "red" {
                XCTAssertGreaterThan(color.red, 0.9)
                XCTAssertLessThan(color.blue, 0.1)
            } else {
                XCTAssertGreaterThan(color.blue, 0.9)
                XCTAssertLessThan(color.red, 0.1)
            }
        }
        let missing = await palette.read(directory.appendingPathComponent("missing.png"))
        XCTAssertNil(missing)
    }

    func testLowContrastColorsFallBackToBlackOrWhite() {
        let bright = ArtworkColor(red: 1, green: 0.95, blue: 0.3)
        let dark = ArtworkColor(red: 0.03, green: 0.02, blue: 0.1)
        let lightFallback = bright.adjusted(dark: false)
        XCTAssertEqual(lightFallback.0, 0)
        XCTAssertEqual(lightFallback.1, 0)
        XCTAssertEqual(lightFallback.2, 0)
        let darkFallback = dark.adjusted(dark: true)
        XCTAssertEqual(darkFallback.0, 1)
        XCTAssertEqual(darkFallback.1, 1)
        XCTAssertEqual(darkFallback.2, 1)
        // Mid-gray passes against pure black, but fails against an elevated sheet.
        let elevatedFallback = ArtworkColor(red: 0.47, green: 0.47, blue: 0.47).adjusted(dark: true)
        XCTAssertEqual(elevatedFallback.0, 1)
        XCTAssertEqual(elevatedFallback.1, 1)
        XCTAssertEqual(elevatedFallback.2, 1)
        let brightOnDark = bright.adjusted(dark: true)
        XCTAssertEqual(brightOnDark.0, bright.red)
        XCTAssertEqual(brightOnDark.1, bright.green)
        XCTAssertEqual(brightOnDark.2, bright.blue)
        let darkOnLight = dark.adjusted(dark: false)
        XCTAssertEqual(darkOnLight.0, dark.red)
        XCTAssertEqual(darkOnLight.1, dark.green)
        XCTAssertEqual(darkOnLight.2, dark.blue)
    }
}
