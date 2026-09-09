import XCTest
@testable import Oto

final class PlaybackQueueTests: XCTestCase {
    private func tracks(_ count: Int = 3, album: String = "Album") -> [Track] {
        (1...count).map {
            Track(relativePath: "\(album)/\($0).flac", title: "\(album) \($0)", artist: "Artist", albumTitle: album,
                  albumArtist: "Artist", trackNumber: $0, discNumber: 1, duration: 60,
                  artworkKey: nil, fileSize: 1, modifiedAt: nil)
        }
    }

    func testSelectedSongPreviousUsesSourceOrderEvenIfUnheard() {
        let songs = tracks()
        var queue = PlaybackQueue()
        queue.start(songs, at: songs[2])
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current?.track, songs[1])
        XCTAssertEqual(queue.sourceUpcoming.map(\.track), [songs[2]])
        XCTAssertTrue(queue.previous())
        XCTAssertFalse(queue.previous())
        XCTAssertEqual(queue.current?.track, songs[0])
    }

    func testManualItemsTakePriorityAndDisappearFromPreviousAndRepeat() {
        let songs = tracks(), additions = tracks(2, album: "Detour")
        var queue = PlaybackQueue()
        queue.start(songs)
        queue.append(additions)
        let consumedIDs = queue.queued.map(\.id)
        XCTAssertEqual(queue.upcoming.map(\.track), additions + Array(songs.dropFirst()))
        queue.advance()
        XCTAssertEqual(queue.current?.track, additions[0])
        queue.advance(automatically: true)
        XCTAssertEqual(queue.current?.track, additions[1])
        queue.advance(automatically: true)
        XCTAssertEqual(queue.current?.track, songs[1])
        XCTAssertTrue(queue.queued.isEmpty)
        queue.previous()
        XCTAssertEqual(queue.current?.track, songs[0])
        queue.advance()
        XCTAssertEqual(queue.current?.track, songs[1])
        queue.repeatMode = .all
        for _ in 0..<12 {
            queue.advance(automatically: true)
            XCTAssertFalse(consumedIDs.contains(queue.currentID!))
            XCTAssertTrue(queue.isValid)
        }
    }

    func testPreviousFromManualReturnsToAnchorAndPreservesPendingAdditions() {
        let songs = tracks(), additions = tracks(2, album: "Detour")
        var queue = PlaybackQueue()
        queue.start(songs, at: songs[1])
        queue.append(additions)
        queue.advance()
        let consumed = queue.currentID
        queue.repeatMode = .one
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current?.track, songs[1])
        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertEqual(queue.queued.map(\.track), [additions[1]])
        queue.advance()
        XCTAssertNotEqual(queue.currentID, consumed)
        XCTAssertEqual(queue.current?.track, additions[1])
    }

    func testStartingAnotherSourcePreservesOnlyPendingManualItems() {
        var queue = PlaybackQueue()
        let additions = tracks(2, album: "Detour"), replacement = tracks(2, album: "New Album")
        queue.start(tracks())
        queue.append(additions)
        queue.advance()
        queue.start(replacement)
        XCTAssertEqual(queue.sourceAlbumID, replacement[0].albumID)
        XCTAssertEqual(queue.current?.track, replacement[0])
        XCTAssertEqual(queue.upcoming.map(\.track), [additions[1], replacement[1]])
        queue.advance()
        XCTAssertEqual(queue.sourceAlbumID, replacement[0].albumID, "A queued song does not replace the source")
        queue.advance()
        XCTAssertEqual(queue.current?.track, replacement[1])
    }

    func testClearOnlyRemovesPendingManualItems() {
        var queue = PlaybackQueue()
        let songs = tracks(), additions = tracks(2, album: "Detour")
        queue.start(songs)
        queue.append(additions)
        queue.advance()
        queue.clearUpcoming()
        XCTAssertEqual(queue.current?.track, additions[0])
        XCTAssertEqual(queue.upcoming.map(\.track), Array(songs.dropFirst()))
        queue.advance()
        XCTAssertEqual(queue.current?.track, songs[1])
    }

    func testRepeatOneRepeatsManualSongButNextConsumesItAndEnablesRepeatAll() {
        var queue = PlaybackQueue()
        let songs = tracks(2), addition = tracks(1, album: "Detour")
        queue.start(songs)
        queue.append(addition)
        queue.advance()
        let manualID = queue.currentID
        queue.repeatMode = .one
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.currentID, manualID)
        XCTAssertEqual(queue.repeatMode, .one)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.track, songs[1])
        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.current?.track, songs[0])
    }

    func testRepeatOneNextWrapsSourceAndNoPreviousKeepsMode() {
        var queue = PlaybackQueue()
        let songs = tracks(2)
        queue.start(songs, at: songs[1])
        queue.repeatMode = .one
        XCTAssertTrue(queue.canAdvance)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.track, songs[0])
        XCTAssertEqual(queue.repeatMode, .all)
        queue.repeatMode = .one
        XCTAssertFalse(queue.previous())
        XCTAssertEqual(queue.repeatMode, .one)
    }

    func testStandaloneManualQueueDoesNotRepeatAllOrCreateSourceHistory() {
        var queue = PlaybackQueue()
        let songs = tracks(2)
        queue.append(songs)
        queue.repeatMode = .all
        XCTAssertNil(queue.sourceAlbumID)
        XCTAssertFalse(queue.previous())
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.track, songs[1])
        XCTAssertFalse(queue.advance(automatically: true))
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isValid)
    }

    func testSourceEndOffStopsAndManualDetourAfterLastIsConsumed() {
        var queue = PlaybackQueue()
        let songs = tracks(1)
        queue.start(songs)
        XCTAssertFalse(queue.advance(automatically: true))
        XCTAssertEqual(queue.current?.track, songs[0])
        queue.append(tracks(1, album: "Detour"))
        XCTAssertTrue(queue.advance())
        XCTAssertFalse(queue.advance(automatically: true))
        XCTAssertNil(queue.current)
    }

    func testDuplicateManualEntriesHaveIndependentIdentity() {
        var queue = PlaybackQueue()
        let song = tracks(1)[0]
        queue.start([song])
        queue.append([song, song])
        let ids = queue.queued.map(\.id)
        XCTAssertNotEqual(ids[0], ids[1])
        queue.remove([ids[0]])
        XCTAssertEqual(queue.queued.map(\.id), [ids[1]])
        XCTAssertEqual(queue.source.count, 1)
        XCTAssertTrue(queue.isValid)
    }

    func testReorderAndRemoveStayWithinTheirRespectiveSections() {
        var queue = PlaybackQueue()
        let songs = tracks(4), additions = tracks(3, album: "Detour")
        queue.start(songs)
        queue.append(additions)
        queue.moveQueued(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(queue.queued.map(\.track), [additions[2], additions[0], additions[1]])
        queue.moveSourceUpcoming(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(queue.sourceUpcoming.map(\.track), [songs[3], songs[1], songs[2]])
        queue.remove([queue.sourceUpcoming[1].id])
        queue.clearUpcoming()
        queue.repeatMode = .all
        var played: [Track] = []
        for _ in 0..<6 { queue.advance(); played.append(queue.current!.track) }
        XCTAssertEqual(played, [songs[3], songs[2], songs[0], songs[3], songs[2], songs[0]])
    }

    func testJumpConsumesPassedManualItemsAndPreviousUsesAdjacentSourceTrack() {
        var queue = PlaybackQueue()
        let songs = tracks(4), additions = tracks(3, album: "Detour")
        queue.start(songs)
        queue.append(additions)
        queue.repeatMode = .one
        XCTAssertTrue(queue.jump(to: queue.queued[1].id))
        XCTAssertEqual(queue.current?.track, additions[1])
        XCTAssertEqual(queue.queued.map(\.track), [additions[2]])
        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertTrue(queue.jump(to: queue.sourceUpcoming[1].id))
        XCTAssertTrue(queue.queued.isEmpty)
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current?.track, songs[1])
    }

    func testRefreshDuringDetourRetainsCorrectSourceResumePoint() {
        var queue = PlaybackQueue()
        let songs = tracks(4), additions = tracks(2, album: "Detour")
        queue.start(songs, at: songs[1])
        queue.append(additions)
        queue.advance()
        queue.reconcile(with: [songs[0], songs[2], songs[3]] + additions)
        XCTAssertTrue(queue.isValid)
        queue.advance()
        queue.advance()
        XCTAssertEqual(queue.current?.track, songs[2])
        queue.reconcile(with: [songs[3]])
        XCTAssertEqual(queue.current?.track, songs[3])
        XCTAssertTrue(queue.isValid)
        queue.reconcile(with: [])
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isValid)
    }

    func testRestorationPreservesSourceAnchorAndManualIdentity() throws {
        var queue = PlaybackQueue()
        queue.start(tracks())
        queue.append(tracks(3, album: "Detour"))
        queue.advance()
        queue.moveQueued(from: IndexSet(integer: 1), to: 0)
        queue.repeatMode = .one
        let saved = SavedPlayback(queue: queue, folderPath: "/Music", elapsed: 23.5)
        let restored = try JSONDecoder().decode(SavedPlayback.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.queue.source, queue.source)
        XCTAssertEqual(restored.queue.queued, queue.queued)
        XCTAssertEqual(restored.queue.sourcePosition, queue.sourcePosition)
        XCTAssertEqual(restored.queue.current, queue.current)
        XCTAssertEqual(restored.queue.repeatMode, .one)
        XCTAssertEqual(restored.elapsed, 23.5)
        XCTAssertTrue(restored.queue.isValid)
    }

    func testLegacyFlatQueuePreservesCurrentAndUpcomingOrder() throws {
        let entries = tracks(4).map(QueueEntry.init)
        let encodedEntries = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entries))
        let legacy: [String: Any] = ["entries": encodedEntries, "currentID": entries[1].id.uuidString,
                                   "upcomingIDs": [entries[3].id.uuidString, entries[2].id.uuidString],
                                   "repeatMode": "all", "history": [entries[0].id.uuidString], "isShuffled": true]
        let queue = try JSONDecoder().decode(PlaybackQueue.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(queue.current, entries[1])
        XCTAssertEqual(queue.sourceUpcoming, [entries[3], entries[2]])
        XCTAssertTrue(queue.queued.isEmpty)
        XCTAssertTrue(queue.isValid)
        let roundTrip = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(roundTrip.upcoming, queue.upcoming)
    }

    func testInvalidRestoredSourceCursorIsRejected() throws {
        var queue = PlaybackQueue()
        queue.start(tracks())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)) as? [String: Any])
        json["sourcePosition"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(PlaybackQueue.self, from: JSONSerialization.data(withJSONObject: json)))
    }
}
