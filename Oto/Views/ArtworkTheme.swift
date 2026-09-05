import ImageIO
import SwiftUI

private struct AlbumAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    var albumAccent: Color {
        get { self[AlbumAccentKey.self] }
        set { self[AlbumAccentKey.self] = newValue }
    }
}

struct ArtworkTheme: ViewModifier {
    let key: String?
    let directory: URL
    @Environment(\.colorScheme) private var scheme
    @State private var palette: ArtworkColor?

    func body(content: Content) -> some View {
        let accent = palette?.color(dark: scheme == .dark) ?? Color.accentColor
        content.tint(accent)
            .environment(\.albumAccent, accent)
            .task(id: key) {
                palette = nil
                guard let key else { return }
                let color = await ArtworkPalette.shared.read(directory.appendingPathComponent(key))
                guard !Task.isCancelled else { return }
                palette = color
            }
    }
}

struct ArtworkColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    func adjusted(dark: Bool) -> (Double, Double, Double) {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        // Check dark accents against the elevated sheet surface as well as black,
        // so one palette remains readable in both the album and Now Playing.
        let background = dark ? linear(30.0 / 255.0) : 1.0
        let contrast = dark ? (luminance + 0.05) / (background + 0.05) : 1.05 / (luminance + 0.05)
        guard contrast >= 4.5 else { return dark ? (1, 1, 1) : (0, 0, 0) }
        return (red, green, blue)
    }

    func color(dark: Bool) -> Color {
        let (r, g, b) = adjusted(dark: dark)
        return Color(red: r, green: g, blue: b)
    }
}

actor ArtworkPalette {
    static let shared = ArtworkPalette()
    private var cache: [URL: ArtworkColor] = [:]

    func read(_ url: URL) -> ArtworkColor? {
        if let color = cache[url] { return color }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        var buckets: [Int: (score: Double, r: Double, g: Double, b: Double, count: Double)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let highest = max(r, g, b), lowest = min(r, g, b)
            guard highest > 0.12, lowest < 0.9 else { continue }
            let saturation = highest > 0 ? (highest - lowest) / highest : 0
            let key = Int(pixels[index] / 32) << 6 | Int(pixels[index + 1] / 32) << 3 | Int(pixels[index + 2] / 32)
            var bucket = buckets[key] ?? (0, 0, 0, 0, 0)
            bucket.score += 0.2 + saturation
            bucket.r += r; bucket.g += g; bucket.b += b; bucket.count += 1
            buckets[key] = bucket
        }
        let color: ArtworkColor
        if let winner = buckets.sorted(by: { $0.key < $1.key }).max(by: { $0.value.score < $1.value.score })?.value {
            color = ArtworkColor(red: winner.r / winner.count, green: winner.g / winner.count, blue: winner.b / winner.count)
        } else { color = ArtworkColor(red: 0, green: 0, blue: 0) }
        cache[url] = color
        return color
    }
}
