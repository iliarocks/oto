import Observation
import Foundation

@MainActor @Observable final class LibraryStore {
    private(set) var snapshot: LibrarySnapshot?
    private(set) var albums: [Album] = []
    private(set) var isScanning = false
    private(set) var progress: ScanProgress?
    var errorMessage: String?
    let persistence: LibraryPersistence
    private let scanner: LibraryScanner
    private var scanTask: Task<Void, Never>?
    var tracks: [Track] { snapshot?.tracks ?? [] }

    init(persistence: LibraryPersistence = .live) {
        self.persistence = persistence
        scanner = LibraryScanner(persistence: persistence)
        do {
            snapshot = try persistence.load()
            albums = Album.grouped(snapshot?.tracks ?? [])
        } catch { errorMessage = error.localizedDescription }
    }

    func choose(_ url: URL) {
        guard !isScanning else { return }
        // Start access synchronously while the picker grant is alive.
        let access = FolderAccess(url: url)
        startScan(access: access)
    }

    func refresh() {
        guard !isScanning, let snapshot else { return }
        do { startScan(access: try FolderAccess(bookmark: snapshot.bookmark)) }
        catch { errorMessage = LibraryError.inaccessibleFolder.localizedDescription }
    }

    func cancelScan() { scanTask?.cancel() }

    private func startScan(access: FolderAccess) {
        isScanning = true
        progress = nil
        scanTask = Task {
            defer {
                isScanning = false
                progress = nil
                scanTask = nil
                withExtendedLifetime(access) {}
            }
            do {
                let newSnapshot = try await scanner.scan(folder: access.url) { [weak self] value in
                    await self?.setProgress(value)
                }
                try Task.checkCancellation()
                guard !newSnapshot.tracks.isEmpty else { throw LibraryError.emptyFolder }
                // A partial refresh must not quietly drop previously indexed songs.
                // Individual unreadable songs are retained for the same folder;
                // genuine removals disappear on a successful directory traversal.
                var committed = newSnapshot
                if let previous = snapshot,
                   let oldAccess = try? FolderAccess(bookmark: previous.bookmark),
                   oldAccess.url.standardizedFileURL == access.url.standardizedFileURL {
                    let failedPaths = Set(newSnapshot.issues.map(\.path))
                    let retained = previous.tracks.filter { failedPaths.contains($0.relativePath) }
                    committed = LibrarySnapshot(folderName: newSnapshot.folderName, bookmark: newSnapshot.bookmark,
                        tracks: newSnapshot.tracks + retained, scannedAt: newSnapshot.scannedAt, issues: newSnapshot.issues)
                }
                try persistence.save(committed)
                snapshot = committed
                albums = Album.grouped(committed.tracks)
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func setProgress(_ value: ScanProgress) { progress = value }
}
