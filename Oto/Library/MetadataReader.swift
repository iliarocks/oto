import AVFoundation
import CryptoKit
import ImageIO
import UIKit

struct AudioMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?
    var artwork: Data?
    var duration: TimeInterval = 0
}

enum MetadataReader {
    static func read(_ url: URL) async throws -> AudioMetadata {
        var value = try await CoordinatedRead.perform(at: url) { readable in
            let file = try AVAudioFile(forReading: readable)
            var result = AudioMetadata()
            result.duration = Double(file.length) / file.fileFormat.sampleRate
            guard result.duration.isFinite, result.duration > 0 else { throw LibraryError.emptyFolder }
            if readable.pathExtension.lowercased() == "flac", let flac = try? FLACMetadata.read(from: readable) {
                result.title = flac.tags["TITLE"]
                result.artist = flac.tags["ARTIST"]
                result.album = flac.tags["ALBUM"]
                result.albumArtist = flac.tags["ALBUMARTIST"] ?? flac.tags["ALBUM ARTIST"]
                if result.albumArtist == nil, flac.tags["COMPILATION"] == "1" { result.albumArtist = "Various Artists" }
                result.trackNumber = number(flac.tags["TRACKNUMBER"])
                result.discNumber = number(flac.tags["DISCNUMBER"])
                result.artwork = flac.artwork
            }
            return result
        }
        // FLAC was handled above. For ID3 and MPEG-4 use the platform's tag reader.
        if url.pathExtension.lowercased() != "flac" {
            let asset = AVURLAsset(url: url)
            let metadata = (try? await asset.load(.metadata)) ?? []
            for item in metadata {
                try Task.checkCancellation()
                let identifier = item.identifier?.rawValue ?? ""
                let common = item.commonKey?.rawValue ?? ""
                if common == AVMetadataKey.commonKeyArtwork.rawValue {
                    value.artwork = try? await item.load(.dataValue)
                    continue
                }
                let string = try? await item.load(.stringValue)
                switch common {
                case AVMetadataKey.commonKeyTitle.rawValue: value.title = string
                case AVMetadataKey.commonKeyArtist.rawValue: value.artist = string
                case AVMetadataKey.commonKeyAlbumName.rawValue: value.album = string
                default: break
                }
                if identifier.hasSuffix("TPE2") || identifier.hasSuffix("aART") { value.albumArtist = string }
                if identifier.hasSuffix("TRCK") { value.trackNumber = number(string) }
                if identifier.hasSuffix("TPOS") { value.discNumber = number(string) }
                if identifier.hasSuffix("trkn") || identifier.hasSuffix("disk"),
                   let data = try? await item.load(.dataValue), data.count >= 4 {
                    let number = Int(data[2]) << 8 | Int(data[3])
                    if number > 0 {
                        if identifier.hasSuffix("trkn") { value.trackNumber = number }
                        else { value.discNumber = number }
                    }
                }
                if identifier.hasSuffix("cpil"), string == "1", value.albumArtist == nil { value.albumArtist = "Various Artists" }
            }
        }
        return value
    }

    static func number(_ string: String?) -> Int? {
        guard let part = string?.split(separator: "/").first,
              let number = Int(part.trimmingCharacters(in: .whitespaces)), number > 0 else { return nil }
        return number
    }

    static func clean(_ string: String?, fallback: String) -> String {
        let clean = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? fallback : clean
    }

    static func filenameNumber(_ url: URL) -> Int? {
        let prefix = url.deletingPathExtension().lastPathComponent.prefix(while: \.isNumber)
        return number(String(prefix))
    }
}

enum ArtworkCache {
    static func store(_ data: Data?, in directory: URL) throws -> String? {
        guard let data, data.count <= 24 * 1_024 * 1_024 else { return nil }
        // Album downloads often embed the same large image in every song.
        // Check the source digest before decoding and resizing it again.
        let key = "v1-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".jpg"
        let destination = directory.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: destination.path) { return key }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_000,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { return nil }
        try jpeg.write(to: destination, options: .atomic)
        return key
    }

    static func folderCover(at directory: URL) async -> Data? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { return nil }
        let names = ["cover.jpg", "cover.jpeg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "front.png"]
        for name in names {
            if let file = files.first(where: { $0.lastPathComponent.lowercased() == name }),
               let properties = try? file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
               properties.isSymbolicLink != true, (properties.fileSize ?? Int.max) <= 24 * 1_024 * 1_024 {
                return try? await CoordinatedRead.perform(at: file) { try Data(contentsOf: $0) }
            }
        }
        return nil
    }
}
