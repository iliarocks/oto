import Foundation

struct ScanProgress: Sendable {
    let completed: Int
    let total: Int
    let filename: String
}

actor LibraryScanner {
    let persistence: LibraryPersistence
    init(persistence: LibraryPersistence) { self.persistence = persistence }

    func scan(folder: URL, progress: @Sendable (ScanProgress) async -> Void) async throws -> LibrarySnapshot {
        let access = FolderAccess(url: folder)
        defer { withExtendedLifetime(access) {} }
        try persistence.prepare()
        let bookmark = try access.bookmark()
        let candidates = try await enumerate(folder)
        var tracks: [Track] = []
        var issues: [ScanIssue] = []
        var undownloadedCount = 0
        var covers: [String: String] = [:]
        var coverDirectories = Set<String>()
        for (index, url) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress(ScanProgress(completed: index, total: candidates.count, filename: url.lastPathComponent))
            let relative = try MusicPath.relative(url, to: folder)
            do {
                let tags = try await MetadataReader.read(url)
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let parent = url.deletingLastPathComponent()
                let artist = MetadataReader.clean(tags.artist, fallback: "Unknown Artist")
                let folderName = parent.lastPathComponent
                let discFolder = folderName.range(of: #"^(cd|disc|disk)[\s._-]*\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
                let albumFolder = discFolder && parent != folder ? parent.deletingLastPathComponent() : parent
                var artworkKey = try ArtworkCache.store(tags.artwork, in: persistence.artworkDirectory)
                if artworkKey == nil {
                    for directory in [parent, albumFolder] where artworkKey == nil {
                        if coverDirectories.insert(directory.path).inserted {
                            covers[directory.path] = try await ArtworkCache.store(ArtworkCache.folderCover(at: directory), in: persistence.artworkDirectory)
                        }
                        artworkKey = covers[directory.path]
                    }
                }
                let discFallback = discFolder ? Int(folderName.filter(\.isNumber)) : nil
                tracks.append(Track(relativePath: relative,
                                    title: MetadataReader.clean(tags.title, fallback: url.deletingPathExtension().lastPathComponent),
                                    artist: artist,
                                    albumTitle: MetadataReader.clean(tags.album, fallback: albumFolder.lastPathComponent),
                                    albumArtist: MetadataReader.clean(tags.albumArtist, fallback: artist),
                                    trackNumber: tags.trackNumber ?? MetadataReader.filenameNumber(url),
                                    discNumber: tags.discNumber ?? discFallback,
                                    duration: tags.duration, artworkKey: artworkKey,
                                    fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate))
            } catch is CancellationError { throw CancellationError() }
            catch LibraryError.fileNotDownloaded {
                undownloadedCount += 1
                issues.append(ScanIssue(path: relative, message: LibraryError.fileNotDownloaded.localizedDescription))
            }
            catch { issues.append(ScanIssue(path: relative, message: "Couldn't read this audio file. Make sure it is downloaded and plays in Files.")) }
        }
        try Task.checkCancellation()
        await progress(ScanProgress(completed: candidates.count, total: candidates.count, filename: ""))
        if !candidates.isEmpty, undownloadedCount == candidates.count { throw LibraryError.fileNotDownloaded }
        return LibrarySnapshot(folderName: folder.lastPathComponent, bookmark: bookmark,
                               tracks: tracks.sorted(by: Track.ordered), scannedAt: Date(), issues: issues)
    }

    func pruneArtwork(keeping tracks: [Track]) {
        do {
            try ArtworkCache.prune(in: persistence.artworkDirectory, keeping: Set(tracks.compactMap(\.artworkKey)))
        } catch {
            // A cache cleanup failure must never undo a successfully saved library.
            NSLog("Oto could not clean artwork cache: %@", error.localizedDescription)
        }
    }

    private func enumerate(_ folder: URL) async throws -> [URL] {
        try await CoordinatedRead.perform(at: folder, metadataOnly: true) { readable in
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            var failure: Error?
            guard let enumerator = FileManager.default.enumerator(at: readable, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
                        failure = error
                        return false
                    }) else { throw LibraryError.inaccessibleFolder }
            var files: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let values = try (url as NSURL).promisedItemResourceValues(forKeys: keys)
                if values[.isSymbolicLinkKey] as? Bool == true { enumerator.skipDescendants(); continue }
                if values[.isRegularFileKey] as? Bool == true && MusicPath.supportedExtensions.contains(url.pathExtension.lowercased()) { files.append(url) }
            }
            if let failure { throw failure }
            return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }
}
