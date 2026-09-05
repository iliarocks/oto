import Foundation

struct LibraryPersistence: Sendable {
    let directory: URL
    var indexURL: URL { directory.appendingPathComponent("library.json") }
    var artworkDirectory: URL { directory.appendingPathComponent("Artwork", isDirectory: true) }

    static var live: LibraryPersistence {
        LibraryPersistence(directory: URL.applicationSupportDirectory.appendingPathComponent("Oto", isDirectory: true))
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    func load() throws -> LibrarySnapshot? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: indexURL))
            guard snapshot.version == 1 else { throw LibraryError.unsupportedVersion }
            return snapshot
        } catch let error as LibraryError { throw error }
        catch { throw LibraryError.unreadableIndex }
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        try prepare()
        try JSONEncoder().encode(snapshot).write(to: indexURL, options: .atomic)
    }
}

// Retain one scope for every operation that outlives a picker callback, including
// playback. Balanced independently, so a refresh cannot revoke the player's scope.
final class FolderAccess {
    let url: URL
    private let scoped: Bool

    init(url: URL) {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
    }

    convenience init(bookmark: Data) throws {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        self.init(url: url)
    }

    func bookmark() throws -> Data {
        try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

enum CoordinatedRead {
    static func perform<T: Sendable>(at url: URL, _ body: @Sendable (URL) throws -> T) async throws -> T {
        let operation = FileReadOperation()
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let result = try operation.read(at: url, body)
                try Task.checkCancellation()
                return result
            } catch {
                // A user cancellation takes precedence over a provider's error.
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

// A coordinator is used by one read. Only cancel() crosses threads, which
// NSFileCoordinator explicitly supports. A running accessor must still finish.
private final class FileReadOperation: @unchecked Sendable {
    private let coordinator = NSFileCoordinator()

    func cancel() { coordinator.cancel() }

    func read<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readable in
            result = Result {
                try Task.checkCancellation()
                return try body(readable)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw LibraryError.inaccessibleFolder }
        return try result.get()
    }
}
