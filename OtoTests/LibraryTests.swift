import AVFoundation
import MediaPlayer
import XCTest
@testable import Oto

final class LibraryTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: LibraryTests.self).url(forResource: name, withExtension: ext))
    }
    private func copyFixture(_ name: String, _ ext: String, into directory: URL, as filename: String? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture(name, ext), to: directory.appendingPathComponent(filename ?? "\(name).\(ext)"))
    }
    private func track(_ path: String, number: Int? = nil, disc: Int? = nil, artist: String = "Artist", albumArtist: String = "Artist") -> Track {
        Track(relativePath: path, title: path, artist: artist, albumTitle: "Album", albumArtist: albumArtist,
              trackNumber: number, discNumber: disc, duration: 60, artworkKey: nil, fileSize: 1, modifiedAt: nil)
    }

    func testDiscOrderingAndSeparateEditions() {
        let tracks = [track("Album/CD2/01.flac", number: 1, disc: 2), track("Album/CD1/10.flac", number: 10),
                      track("Album/CD1/02.flac", number: 2), track("Deluxe/01.flac", number: 1)]
        let albums = Album.grouped(tracks)
        XCTAssertEqual(albums.count, 2)
        let original = albums.first { $0.tracks.count == 3 }!
        XCTAssertEqual(original.tracks.map(\.trackNumber), [2, 10, 1])
    }

    func testCompilationUsesAlbumArtistAndNaturalFilenameOrder() {
        let tracks = [track("Mix/10.flac", artist: "A", albumArtist: "Various Artists"),
                      track("Mix/2.flac", artist: "B", albumArtist: "Various Artists")]
        let albums = Album.grouped(tracks)
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].tracks.first?.relativePath, "Mix/2.flac")
    }

    func testPathContainmentRejectsTraversalAndSymlinks() throws {
        let root = temporary.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try MusicPath.resolve("../secret.flac", in: root))
        XCTAssertThrowsError(try MusicPath.resolve("/secret.flac", in: root))
        let outside = temporary.appendingPathComponent("outside.flac")
        try Data().write(to: outside)
        let link = root.appendingPathComponent("link.flac")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try MusicPath.resolve("link.flac", in: root))
        XCTAssertEqual(try MusicPath.resolve("Artist/01.flac", in: root).lastPathComponent, "01.flac")
    }

    func testFLACTagsAndEmbeddedArtwork() throws {
        let tags = try FLACMetadata.read(from: fixture("01", "flac"))
        XCTAssertEqual(tags.tags["TITLE"], "First Light")
        XCTAssertEqual(tags.tags["ALBUM"], "Quiet Hours")
        XCTAssertEqual(MetadataReader.number(tags.tags["TRACKNUMBER"]), 1)
        XCTAssertNotNil(tags.artwork)
        XCTAssertNotNil(UIImage(data: tags.artwork!))
    }

    func testMalformedFLACMetadataIsBounded() throws {
        XCTAssertThrowsError(try FLACMetadata.comments(Data([255, 255, 255, 255])))
        XCTAssertThrowsError(try FLACMetadata.picture(Data(repeating: 0, count: 7)))
        let bad = temporary.appendingPathComponent("bad.flac")
        try Data("fLaC".utf8).write(to: bad)
        XCTAssertThrowsError(try FLACMetadata.read(from: bad))
        for length in 0..<100 {
            XCTAssertNoThrow(try? FLACMetadata.comments(Data(repeating: 255, count: length)))
        }
    }

    func testAllSupportedFixturesDecodeAndPrepareForPlayback() async throws {
        for (name, ext) in [("01", "flac"), ("alac", "m4a"), ("aac", "m4a"), ("song", "mp3"), ("untagged", "wav"), ("untagged", "aiff"), ("raw", "aac")] {
            let url = try fixture(name, ext)
            let metadata = try await MetadataReader.read(url)
            XCTAssertGreaterThan(metadata.duration, 7, "\(name).\(ext)")
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.volume = 0
            XCTAssertTrue(audio.prepareToPlay(), "\(name).\(ext)")
            XCTAssertGreaterThan(audio.duration, 7)
            if name == "alac" || name == "song" {
                XCTAssertEqual(metadata.albumArtist, "Album Artist")
                XCTAssertEqual(metadata.discNumber, 2)
                XCTAssertEqual(metadata.trackNumber, name == "alac" ? 2 : 3)
            }
        }
    }

    func testScanRecursiveFolderSkipsBadFilesAndPreservesOriginals() async throws {
        let music = temporary.appendingPathComponent("Music")
        let album = music.appendingPathComponent("Quiet Hours")
        try copyFixture("01", "flac", into: album)
        try copyFixture("02", "flac", into: album)
        try copyFixture("cover", "jpg", into: album)
        try copyFixture("01", "flac", into: music.appendingPathComponent(".hidden"))
        try Data("not audio".utf8).write(to: album.appendingPathComponent("broken.flac"))
        let before = try Data(contentsOf: album.appendingPathComponent("01.flac"))
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let result = try await LibraryScanner(persistence: persistence).scan(folder: music) { _ in }
        XCTAssertEqual(result.tracks.map(\.title), ["First Light", "Second Light"])
        XCTAssertEqual(Album.grouped(result.tracks).count, 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.tracks.allSatisfy { $0.artworkKey != nil })
        XCTAssertEqual(try Data(contentsOf: album.appendingPathComponent("01.flac")), before)
        try persistence.save(result)
        XCTAssertEqual(try persistence.load()?.tracks, result.tracks)
        let restored = try FolderAccess(bookmark: result.bookmark)
        XCTAssertEqual(restored.url.standardizedFileURL, music.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: MusicPath.resolve(result.tracks[0].relativePath, in: restored.url)), before)
    }

    func testCorruptIndexIsNotSilentlyOverwritten() throws {
        let persistence = LibraryPersistence(directory: temporary)
        let original = Data("bad json".utf8)
        try original.write(to: persistence.indexURL)
        XCTAssertThrowsError(try persistence.load())
        XCTAssertEqual(try Data(contentsOf: persistence.indexURL), original)
    }

    func testNumberParsingAndTimeClamping() {
        XCTAssertEqual(MetadataReader.number("03/12"), 3)
        XCTAssertNil(MetadataReader.number("-1"))
        XCTAssertNil(MetadataReader.number("abc"))
        XCTAssertEqual(MusicTime.clock(.nan), "0:00")
        XCTAssertEqual(MusicTime.clock(-100), "0:00")
        XCTAssertEqual(MusicTime.clock(192), "3:12")
    }

    func testSongSearchReturnsPlayableTracksSeparatelyFromAlbums() {
        let tracks = [track("Album/Café.flac", number: 1), track("Album/Other.flac", number: 2)]
        let albums = Album.grouped(tracks)
        let search = LibrarySearch(query: "  cafe  ", albums: albums)
        XCTAssertTrue(search.isActive)
        XCTAssertTrue(search.albums.isEmpty)
        XCTAssertEqual(search.tracks.map(\.id), ["Album/Café.flac"])
        XCTAssertEqual(LibrarySearch(query: "Artist", albums: albums).tracks.count, 2)
        XCTAssertEqual(LibrarySearch(query: "Album", albums: albums).albums.count, 1)
        let empty = LibrarySearch(query: " \n ", albums: albums)
        XCTAssertFalse(empty.isActive)
        XCTAssertEqual(empty.albums, albums)
        XCTAssertTrue(empty.tracks.isEmpty)
    }

    @MainActor func testPlaybackPauseSeekNextAndEndOfAlbum() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        try copyFixture("02", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let snapshot = try await LibraryScanner(persistence: persistence).scan(folder: music) { _ in }
        let controller = PlaybackController(artworkDirectory: persistence.artworkDirectory)
        defer { controller.stop() }
        controller.play(snapshot.tracks, bookmark: snapshot.bookmark)
        try await waitUntil { controller.isPlaying }
        XCTAssertEqual(controller.currentTrack?.title, "First Light")
        controller.pause()
        XCTAssertFalse(controller.isPlaying)
        controller.seek(to: 4)
        XCTAssertEqual(controller.elapsed, 4, accuracy: 0.1)
        controller.previous()
        XCTAssertEqual(controller.elapsed, 0, accuracy: 0.1)
        controller.next()
        try await waitUntil { !controller.isLoading && controller.currentTrack?.title == "Second Light" }
        XCTAssertFalse(controller.isPlaying, "Skipping from pause must not unexpectedly start audio")
        XCTAssertFalse(controller.hasNext)
        controller.resume()
        try await waitUntil { controller.isPlaying }
        controller.seek(to: 7.6)
        try await waitUntil { !controller.isPlaying }
        XCTAssertEqual(controller.currentTrack?.title, "Second Light")
        controller.resume()
        try await waitUntil { controller.isPlaying }
        XCTAssertLessThan(controller.elapsed, 1)
    }

    @MainActor func testPreviousAndRapidSkippingRespectPause() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        try copyFixture("02", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let snapshot = try await LibraryScanner(persistence: persistence).scan(folder: music) { _ in }
        let player = PlaybackController(artworkDirectory: persistence.artworkDirectory)
        defer { player.stop() }
        player.play(snapshot.tracks, bookmark: snapshot.bookmark)
        try await waitUntil { player.isPlaying }
        player.pause()
        player.next()
        player.previous()
        try await waitUntil { !player.isLoading }
        XCTAssertEqual(player.currentTrack?.title, "First Light")
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.elapsed, 0, accuracy: 0.1)
    }

    @MainActor func testFailedFolderReplacementKeepsLibrary() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let store = LibraryStore(persistence: persistence)
        store.choose(music)
        try await waitUntil { !store.isScanning }
        XCTAssertEqual(store.tracks.count, 1)
        let originalIndex = try Data(contentsOf: persistence.indexURL)
        let empty = temporary.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        store.choose(empty)
        try await waitUntil { !store.isScanning }
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: persistence.indexURL), originalIndex)
    }

    @MainActor func testRefreshRetainsUnreadableTracksButRemovesDeletedTracks() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        try copyFixture("02", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let store = LibraryStore(persistence: persistence)
        store.choose(music)
        try await waitUntil { !store.isScanning }
        try Data("incomplete download".utf8).write(to: music.appendingPathComponent("01.flac"))
        store.refresh()
        try await waitUntil { !store.isScanning }
        XCTAssertEqual(store.tracks.count, 2)
        XCTAssertEqual(store.snapshot?.issues.count, 1)
        try FileManager.default.removeItem(at: music.appendingPathComponent("01.flac"))
        try FileManager.default.removeItem(at: music.appendingPathComponent("02.flac"))
        store.refresh()
        try await waitUntil { !store.isScanning }
        XCTAssertEqual(store.tracks.count, 0)
        XCTAssertEqual(try persistence.load()?.tracks.count, 0)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor func testCancelledReplacementDoesNotCommit() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let store = LibraryStore(persistence: persistence)
        store.choose(music)
        try await waitUntil { !store.isScanning }
        let original = try Data(contentsOf: persistence.indexURL)
        let replacement = temporary.appendingPathComponent("Replacement")
        try copyFixture("02", "flac", into: replacement)
        store.choose(replacement)
        store.cancelScan()
        try await waitUntil { !store.isScanning }
        XCTAssertEqual(store.tracks.first?.title, "First Light")
        XCTAssertEqual(try Data(contentsOf: persistence.indexURL), original)
    }

    @MainActor func testAutomaticAdvanceAndInterruptionPolicy() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        try copyFixture("02", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let snapshot = try await LibraryScanner(persistence: persistence).scan(folder: music) { _ in }
        let player = PlaybackController(artworkDirectory: persistence.artworkDirectory)
        defer { player.stop() }
        player.play(snapshot.tracks, bookmark: snapshot.bookmark)
        try await waitUntil { player.isPlaying }
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "First Light")
        player.seek(to: 7.7)
        try await waitUntil { player.isPlaying && player.currentTrack?.title == "Second Light" }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await waitUntil { !player.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await waitUntil { player.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await waitUntil { !player.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100))
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(player.isPlaying, "A previously paused track must stay paused after an interruption")
    }

    @MainActor func testStopCancelsPendingPlayback() async throws {
        let music = temporary.appendingPathComponent("Music")
        try copyFixture("01", "flac", into: music)
        let persistence = LibraryPersistence(directory: temporary.appendingPathComponent("Index"))
        let snapshot = try await LibraryScanner(persistence: persistence).scan(folder: music) { _ in }
        let player = PlaybackController(artworkDirectory: persistence.artworkDirectory)
        player.play(snapshot.tracks, bookmark: snapshot.bookmark)
        player.stop()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "Timed out waiting for state change")
    }
}
