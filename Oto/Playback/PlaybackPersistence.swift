import Foundation

/// The existing JSON format is retained across upgrades.
struct SavedPlayback: Codable {
    let queue: PlaybackQueue
    let folderPath: String?
    let elapsed: TimeInterval
}

struct PlaybackPersistence {
    let directory: URL
    private var url: URL { directory.appendingPathComponent("playback.json") }

    func load() -> SavedPlayback? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(SavedPlayback.self, from: data),
              saved.queue.isValid else { return nil }
        return saved
    }

    func save(_ state: SavedPlayback) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
