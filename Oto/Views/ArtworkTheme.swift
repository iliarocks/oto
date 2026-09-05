import ImageIO
import SwiftUI

private struct AlbumAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

private struct AlbumAccentInkKey: EnvironmentKey {
    static let defaultValue = Color(uiColor: .systemBackground)
}

private struct AlbumTextAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    var albumAccentInk: Color {
        get { self[AlbumAccentInkKey.self] }
        set { self[AlbumAccentInkKey.self] = newValue }
    }
    var albumTextAccent: Color {
        get { self[AlbumTextAccentKey.self] }
        set { self[AlbumTextAccentKey.self] = newValue }
    }

    var albumAccent: Color {
        get { self[AlbumAccentKey.self] }
        set { self[AlbumAccentKey.self] = newValue }
    }
}

struct ArtworkTheme: ViewModifier {
    let key: String?
    let directory: URL
    @Environment(\.colorScheme) private var scheme
    @State private var palette: ArtworkColors?

    func body(content: Content) -> some View {
        let sampled = palette?.accent(dark: scheme == .dark)
        let accent = sampled?.color ?? Color.accentColor
        let textAccent = sampled.map { $0.hasContrast(dark: scheme == .dark, minimum: 4.5) ? accent : Color.primary } ?? accent
        content.tint(accent)
            .environment(\.albumAccent, accent)
            .environment(\.albumTextAccent, textAccent)
            .environment(\.albumAccentInk, sampled?.contrastingInk ?? Color(uiColor: .systemBackground))
            .task(id: key) {
                palette = nil
                guard let key else { return }
                let color = await ArtworkPalette.shared.read(directory.appendingPathComponent(key))
                guard !Task.isCancelled else { return }
                palette = color
            }
    }
}

struct ArtworkColor: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private var luminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    func hasContrast(dark: Bool, minimum: Double = 3) -> Bool {
        // Check dark accents against the elevated sheet surface as well as black,
        // so one palette remains readable in both the album and Now Playing.
        let background = dark ? Self.linear(30.0 / 255.0) : 1.0
        let contrast = dark ? (luminance + 0.05) / (background + 0.05) : 1.05 / (luminance + 0.05)
        return contrast >= minimum
    }

    var contrastingInk: Color {
        (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
}

struct ArtworkColors: Sendable {
    // Keep the prominent swatches so appearance changes can select a readable
    // artwork color before resorting to a monochrome fallback.
    let candidates: [ArtworkColor]

    func accent(dark: Bool) -> ArtworkColor {
        candidates.first { $0.hasContrast(dark: dark) }
            ?? ArtworkColor(red: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0)
    }

    func color(dark: Bool) -> Color { accent(dark: dark).color }
}

actor ArtworkPalette {
    static let shared = ArtworkPalette()
    private var cache: [URL: ArtworkColors] = [:]

    func read(_ url: URL) -> ArtworkColors? {
        if let color = cache[url] { return color }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        let palette = ArtworkSampling.palette(pixels: pixels)
        cache[url] = palette
        return palette
    }
}
