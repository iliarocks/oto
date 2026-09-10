import Foundation

struct Track: Codable, Hashable, Identifiable, Sendable {
    var id: String { relativePath }
    let relativePath: String
    let title: String
    let artist: String
    let albumTitle: String
    let albumArtist: String
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval
    let artworkKey: String?
    let fileSize: Int64
    let modifiedAt: Date?

    var fileExtension: String { URL(fileURLWithPath: relativePath).pathExtension.uppercased() }
    var folder: String { (relativePath as NSString).deletingLastPathComponent }
    var albumID: String {
        // Folder identity keeps different editions (and untagged folders) separate.
        // Disc subfolders collapse into their parent, while distinct artists may
        // share one album through ALBUMARTIST, as on compilations.
        let parts = folder.split(separator: "/").map(String.init)
        let last = parts.last ?? ""
        let isDisc = last.range(of: #"^(cd|disc|disk)[\s._-]*\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
        let base = isDisc ? parts.dropLast().joined(separator: "/") : folder
        return [base, albumTitle, albumArtist].joined(separator: "\u{001F}")
    }

    static func ordered(_ lhs: Track, _ rhs: Track) -> Bool {
        if (lhs.discNumber ?? 1) != (rhs.discNumber ?? 1) { return (lhs.discNumber ?? 1) < (rhs.discNumber ?? 1) }
        if lhs.trackNumber != rhs.trackNumber { return (lhs.trackNumber ?? Int.max) < (rhs.trackNumber ?? Int.max) }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
}

struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]
    var artworkKey: String? { tracks.compactMap(\.artworkKey).first }
    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }

    static func grouped(_ tracks: [Track]) -> [Album] {
        Dictionary(grouping: tracks, by: \.albumID).map { id, tracks in
            let ordered = tracks.sorted(by: Track.ordered)
            return Album(id: id, title: ordered[0].albumTitle, artist: ordered[0].albumArtist, tracks: ordered)
        }.sorted(by: orderedByTitle)
    }

    static func orderedByTitle(_ lhs: Album, _ rhs: Album) -> Bool {
        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
        let artistComparison = lhs.artist.localizedStandardCompare(rhs.artist)
        if artistComparison != .orderedSame { return artistComparison == .orderedAscending }
        return lhs.id < rhs.id
    }
}

struct LibrarySnapshot: Codable, Sendable {
    var version = 1
    let folderName: String
    let bookmark: Data
    let tracks: [Track]
    let scannedAt: Date
    let issues: [ScanIssue]
}

struct ScanIssue: Codable, Hashable, Identifiable, Sendable {
    var id: String { path + message }
    let path: String
    let message: String
}

enum LibraryError: LocalizedError {
    case fileNotDownloaded, inaccessibleFolder, unreadableIndex, invalidPath, emptyFolder, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .fileNotDownloaded: #"Use "Keep Downloaded" on the folder, then refresh your library."#
        case .inaccessibleFolder: "This folder is unavailable. Make sure it is downloaded in Files, then choose it again."
        case .unreadableIndex: "The saved library could not be read. Choose your music folder again to rebuild it. Your music is unchanged."
        case .invalidPath: "This file is outside the selected music folder."
        case .emptyFolder: "No playable songs were found. Choose a folder containing FLAC, MP3, M4A, AAC, WAV, or AIFF files."
        case .unsupportedVersion: "This library was saved by a newer version of Oto. Update the app or choose your folder again."
        }
    }
}

enum MusicPath {
    static let supportedExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf"]

    static func relative(_ file: URL, to root: URL) throws -> String {
        let prefix = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let path = file.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else { throw LibraryError.invalidPath }
        return String(path.dropFirst(prefix.count))
    }

    static func resolve(_ path: String, in root: URL) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw LibraryError.invalidPath }
        // Canonicalize the existing root first. On a device, resolving a missing
        // child can otherwise leave /var and /private/var prefixes mismatched.
        let result = root.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(path)
        _ = try relative(result, to: root)
        return result
    }
}

enum MusicTime {
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, min(seconds, 86_400_000))) : 0
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }
    static func summary(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds.isFinite ? seconds : 0) / 60)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(max(1, minutes)) min"
    }
}
