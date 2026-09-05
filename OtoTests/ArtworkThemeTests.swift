import UIKit
import XCTest
@testable import Oto

final class ArtworkThemeTests: XCTestCase {
    private let black = ArtworkColor(red: 0, green: 0, blue: 0)
    private let white = ArtworkColor(red: 1, green: 1, blue: 1)

    private func pixels(_ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        (0..<64).flatMap { y in
            (0..<64).flatMap { x -> [UInt8] in
                let (r, g, b, a) = pixel(x, y)
                return [r, g, b, a]
            }
        }
    }

    @MainActor func testImageDecodingAndMissingArtwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let url = directory.appendingPathComponent("red.png")
        try data.write(to: url)
        let loader = ArtworkPalette()
        let result = await loader.read(url)
        let color = try XCTUnwrap(result).accent(dark: false)
        XCTAssertGreaterThan(color.red, 0.9)
        XCTAssertLessThan(color.blue, 0.1)
        let cached = await loader.read(url)
        XCTAssertEqual(cached?.candidates, result?.candidates)
        let missing = await loader.read(directory.appendingPathComponent("missing.png"))
        XCTAssertNil(missing)
    }

    func testGradientRemainsDominantOverSmallColorfulDetail() {
        let image = pixels { x, y in
            if x < 10 && y < 10 { return (20, 70, 220, 255) }
            return (UInt8(205 + x / 2), UInt8(20 + y / 2), 55, 255)
        }
        let palette = ArtworkSampling.palette(pixels: image)
        for dark in [false, true] {
            let accent = palette.accent(dark: dark)
            XCTAssertGreaterThan(accent.red, accent.blue * 2)
            XCTAssertGreaterThan(accent.red, accent.green * 2)
            XCTAssertTrue(accent.hasContrast(dark: dark))
        }
        XCTAssertEqual(palette.candidates, ArtworkSampling.palette(pixels: image).candidates)
    }

    func testPaleBackgroundDoesNotHideReadableSecondaryColor() {
        let image = pixels { x, _ in x < 12 ? (40, 85, 165, 255) : (247, 237, 225, 255) }
        let accent = ArtworkSampling.palette(pixels: image).accent(dark: false)
        XCTAssertGreaterThan(accent.blue, accent.red * 2)
        XCTAssertTrue(accent.hasContrast(dark: false))
    }

    func testNeutralAndTransparentArtworkUsesMonochrome() {
        for image in [pixels { x, _ in let value = UInt8(x * 4); return (value, value, value, 255) },
                      pixels { _, _ in (255, 0, 0, 0) }] {
            let palette = ArtworkSampling.palette(pixels: image)
            XCTAssertEqual(palette.accent(dark: false), black)
            XCTAssertEqual(palette.accent(dark: true), white)
        }
    }

    func testLowContrastColorsFallBackForEachAppearance() {
        let bright = ArtworkColor(red: 1, green: 0.95, blue: 0.3)
        let dark = ArtworkColor(red: 0.15, green: 0.03, blue: 0.1)
        XCTAssertEqual(ArtworkColors(candidates: [bright]).accent(dark: false), black)
        XCTAssertEqual(ArtworkColors(candidates: [bright]).accent(dark: true), bright)
        XCTAssertEqual(ArtworkColors(candidates: [dark]).accent(dark: false), dark)
        XCTAssertEqual(ArtworkColors(candidates: [dark]).accent(dark: true), white)
        // Check against the elevated dark sheet, not just pure black.
        XCTAssertFalse(ArtworkColor(red: 0.36, green: 0.36, blue: 0.36).hasContrast(dark: true))
    }

    func testControlsAndTextHaveSeparateContrastRequirements() {
        let red = ArtworkColor(red: 0.93, green: 0.15, blue: 0.26)
        XCTAssertTrue(red.hasContrast(dark: false))
        XCTAssertFalse(red.hasContrast(dark: false, minimum: 4.5))
        XCTAssertEqual(red.contrastingInk, .black)
        XCTAssertEqual(black.contrastingInk, .white)
        XCTAssertEqual(white.contrastingInk, .black)
    }
}
