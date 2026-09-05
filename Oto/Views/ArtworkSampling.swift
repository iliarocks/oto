import Foundation

// Oklab conversion: Björn Ottosson's public-domain reference implementation.
// https://bottosson.github.io/posts/oklab/
private struct PerceptualColor {
    var lightness: Double
    var a: Double
    var b: Double
    var chroma: Double { hypot(a, b) }

    init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness; self.a = a; self.b = b
    }

    init(_ color: ArtworkColor) {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(color.red), g = linear(color.green), b = linear(color.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.init(lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                  a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                  b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    func distance(to other: Self) -> Double {
        let dl = lightness - other.lightness, da = a - other.a, db = b - other.b
        return dl * dl + da * da + db * db
    }
}

enum ArtworkSampling {
    private struct Sample {
        let color: ArtworkColor
        let perceptual: PerceptualColor
        let count: Double
    }

    static func palette(pixels: [UInt8]) -> ArtworkColors {
        // A fine histogram reduces work without fragmenting the final palette:
        // nearby bins are subsequently clustered in perceptual color space.
        var bins: [Int: (r: Double, g: Double, b: Double, count: Double)] = [:]
        for index in stride(from: 0, to: pixels.count - 3, by: 4) where pixels[index + 3] >= 250 {
            let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2]
            let key = Int(r / 8) << 10 | Int(g / 8) << 5 | Int(b / 8)
            var bin = bins[key] ?? (0, 0, 0, 0)
            bin.r += Double(r) / 255; bin.g += Double(g) / 255; bin.b += Double(b) / 255; bin.count += 1
            bins[key] = bin
        }
        let samples: [Sample] = bins.sorted { $0.key < $1.key }.compactMap { entry in
            let bin = entry.value
            let color = ArtworkColor(red: bin.r / bin.count, green: bin.g / bin.count, blue: bin.b / bin.count)
            let perceptual = PerceptualColor(color)
            // Neutral paper, black borders, and compression noise should not
            // displace an actual artwork color or tint a monochrome cover.
            guard perceptual.chroma >= 0.035, perceptual.lightness > 0.15 else { return nil }
            return Sample(color: color, perceptual: perceptual, count: bin.count)
        }
        guard let dominant = samples.max(by: { $0.count < $1.count }) else { return ArtworkColors(candidates: []) }

        // Deterministic, population-weighted seeds avoid flickering palettes on
        // repeated launches and give substantial secondary colors a fair start.
        var centers = [dominant.perceptual]
        while centers.count < min(8, samples.count) {
            let ranked = samples.map { sample in
                (sample, centers.map { $0.distance(to: sample.perceptual) }.min()! * sqrt(sample.count))
            }
            guard let next = ranked.max(by: { $0.1 < $1.1 }), next.1 > 0.0001 else { break }
            centers.append(next.0.perceptual)
        }
        var groups = [[Sample]]()
        for _ in 0..<12 {
            groups = Array(repeating: [], count: centers.count)
            for sample in samples {
                let index = centers.indices.min { centers[$0].distance(to: sample.perceptual) < centers[$1].distance(to: sample.perceptual) }!
                groups[index].append(sample)
            }
            var movement = 0.0
            for index in centers.indices where !groups[index].isEmpty {
                let group = groups[index], count = group.reduce(0) { $0 + $1.count }
                let center = PerceptualColor(
                    lightness: group.reduce(0) { $0 + $1.perceptual.lightness * $1.count } / count,
                    a: group.reduce(0) { $0 + $1.perceptual.a * $1.count } / count,
                    b: group.reduce(0) { $0 + $1.perceptual.b * $1.count } / count)
                movement += centers[index].distance(to: center)
                centers[index] = center
            }
            if movement < 0.000001 { break }
        }
        let minimumPopulation = max(12.0, Double(pixels.count / 4) * 0.005)
        let ranked = groups.enumerated().compactMap { index, group -> (index: Int, score: Double, group: [Sample])? in
            let population = group.reduce(0) { $0 + $1.count }
            guard population >= minimumPopulation else { return nil }
            return (index, population * (0.4 + min(centers[index].chroma / 0.2, 1)), group)
        }.sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }

        let candidates = ranked.flatMap { cluster in
            [false, true].compactMap { dark -> ArtworkColor? in
                let readable = cluster.group.filter { $0.color.hasContrast(dark: dark) }
                let count = readable.reduce(0) { $0 + $1.count }
                let population = cluster.group.reduce(0) { $0 + $1.count }
                guard count >= max(8, population * 0.02) else { return nil }
                // Select a representative shade from readable source pixels;
                // never darken/lighten an otherwise unsuitable cover color.
                let color = ArtworkColor(red: readable.reduce(0) { $0 + $1.color.red * $1.count } / count,
                                         green: readable.reduce(0) { $0 + $1.color.green * $1.count } / count,
                                         blue: readable.reduce(0) { $0 + $1.color.blue * $1.count } / count)
                if color.hasContrast(dark: dark) { return color }
                return readable.max(by: { $0.count < $1.count })?.color
            }
        }
        return ArtworkColors(candidates: candidates)
    }
}
