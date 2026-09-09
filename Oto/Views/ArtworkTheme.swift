import ImageIO
import SwiftUI

private struct AlbumAccentKey: EnvironmentKey {
    static let defaultValue = Color("AccentColor")
}

private struct AlbumAccentInkKey: EnvironmentKey {
    static let defaultValue = Color(uiColor: .systemBackground)
}

private struct AlbumTextAccentKey: EnvironmentKey {
    static let defaultValue = Color("AccentColor")
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
    var animatesChanges = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: ArtworkColors?

    func body(content: Content) -> some View {
        let sampled = palette?.accent(dark: scheme == .dark)
        let accent = sampled ?? ArtworkColor(uiColor: UIColor(named: "AccentColor") ?? .label, dark: scheme == .dark)
        let textAccent = sampled.map { $0.hasContrast(dark: scheme == .dark, minimum: 4.5) ? accent.color : Color.primary } ?? accent.color
        content
            .modifier(InterpolatedArtworkTint(color: accent))
            .environment(\.albumTextAccent, textAccent)
            .environment(\.albumAccentInk, sampled?.contrastingInk ?? Color(uiColor: .systemBackground))
            .animation(animatesChanges ? .easeInOut(duration: reduceMotion ? 0.15 : 0.28) : nil, value: accent)
            .task(id: key) {
                // Retain the old palette until the new one is ready, avoiding an
                // intermediate flash of the app's default accent.
                guard let key else { palette = nil; return }
                let color = await ArtworkPalette.shared.read(directory.appendingPathComponent(key))
                guard !Task.isCancelled else { return }
                palette = color
            }
    }
}

/// Native swipe actions otherwise template their symbols white, even on a white
/// artwork tint. Preserve the chosen ink in an original-rendering symbol image.
struct ArtworkSwipeAction: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void
    @Environment(\.albumAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = ArtworkColor(uiColor: UIColor(accent), dark: scheme == .dark)
        Button(role: role, action: action) {
            if let symbol = UIImage(systemName: systemImage) {
                Image(uiImage: symbol.withTintColor(UIColor(fill.contrastingInk), renderingMode: .alwaysOriginal))
            }
        }
        .tint(accent)
        .accessibilityLabel(title)
    }
}

/// Interpolate the environment color itself so UIKit's slider and route picker
/// receive the same intermediate colors as SwiftUI's tinted controls.
private struct InterpolatedArtworkTint: AnimatableModifier {
    var color: ArtworkColor

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(color.red, AnimatablePair(color.green, color.blue)) }
        set { color = ArtworkColor(red: newValue.first, green: newValue.second.first, blue: newValue.second.second) }
    }

    func body(content: Content) -> some View {
        content.tint(color.color).environment(\.albumAccent, color.color)
    }
}

struct ArtworkColor: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    init(uiColor: UIColor, dark: Bool) {
        let resolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue))
    }

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
