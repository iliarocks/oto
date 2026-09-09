import XCTest
@testable import Oto

final class PlaybackQueueTests: XCTestCase {
    private func tracks(_ count: Int = 5) -> [Track] {
        (1...count).map {
            Track(relativePath: "\($0).flac", title: "Song \($0)", artist: "Artist", albumTitle: "Album",
                  albumArtist: "Artist", trackNumber: $0, discNumber: 1, duration: 60,
                  artworkKey: nil, fileSize: 1, modifiedAt: nil)
        }
    }

    func testSelectedSongAndListeningHistory() {
        let tracks = tracks()
        var queue = PlaybackQueue()
        queue.start(tracks, at: tracks[2])
        XCTAssertEqual(queue.current?.track, tracks[2])
        XCTAssertFalse(queue.previous(), "Earlier album tracks have not actually been heard")
        XCTAssertEqual(queue.upcoming.map(\.track), Array(tracks[3...]))
        XCTAssertTrue(queue.advance())
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current?.track, tracks[2])
        XCTAssertTrue(queue.advance())
        XCTAssertTrue(queue.advance())
        XCTAssertFalse(queue.advance())
    }

    func testOlderSavedQueueDropsRemovedModeWithoutLosingQueue() throws {
        var queue = PlaybackQueue()
        queue.start(tracks())
        queue.move(from: IndexSet(integer: 3), to: 0)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)) as? [String: Any])
        json["isShuffled"] = true
        let restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.currentID, queue.currentID)
        XCTAssertEqual(restored.upcomingIDs, queue.upcomingIDs)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertNil(encoded["isShuffled"])
        var newPlayback = restored
        newPlayback.start(tracks())
        XCTAssertEqual(newPlayback.current?.track, tracks()[0])
        XCTAssertEqual(newPlayback.upcoming.map(\.track), Array(tracks().dropFirst()))
    }

    func testAppendsOrderedAlbumsAndIndependentlyRemovesDuplicates() {
        let tracks = tracks()
        var queue = PlaybackQueue()
        queue.start(tracks)
        let original = queue.upcomingIDs
        queue.append(Array(tracks.prefix(2)))
        XCTAssertEqual(Array(queue.upcomingIDs.prefix(original.count)), original)
        XCTAssertEqual(queue.upcoming.suffix(2).map(\.track), Array(tracks.prefix(2)))
        let duplicate = queue.upcoming.last!
        queue.remove([duplicate.id])
        XCTAssertEqual(queue.entries.filter { $0.track == duplicate.track }.count, 1)
        XCTAssertEqual(Set(queue.entries.map(\.id)).count, queue.entries.count)
    }

    func testManualOrderingIsUsedByRepeat() {
        var queue = PlaybackQueue()
        queue.start(tracks())
        let current = queue.currentID
        let last = queue.upcomingIDs.last!
        queue.move(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(queue.upcomingIDs.first, last)
        let edited = queue.upcomingIDs
        XCTAssertEqual(queue.currentID, current)
        queue.repeatMode = .all
        while !queue.upcoming.isEmpty { queue.advance() }
        queue.advance()
        XCTAssertEqual(queue.currentID, current)
        XCTAssertEqual(queue.upcomingIDs, edited)
    }

    func testJumpSkipsEntriesButPreviousReturnsToActualSong() {
        var queue = PlaybackQueue()
        queue.start(tracks())
        let first = queue.currentID
        let target = queue.upcomingIDs[2]
        XCTAssertTrue(queue.jump(to: target))
        XCTAssertEqual(queue.upcoming.count, 1)
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.currentID, first)
        XCTAssertEqual(queue.upcomingIDs.first, target)
    }

    func testRepeatOneDoesNotTrapManualNext() {
        var queue = PlaybackQueue()
        queue.start(tracks(2))
        queue.repeatMode = .one
        let first = queue.currentID
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.currentID, first)
        XCTAssertTrue(queue.advance())
        XCTAssertNotEqual(queue.currentID, first)
        XCTAssertFalse(queue.canAdvance)
        XCTAssertTrue(queue.advance(automatically: true))
    }

    func testRepeatAllPreservesAlbumOrder() {
        var queue = PlaybackQueue()
        queue.start(tracks())
        queue.repeatMode = .all
        let all = queue.entries.map(\.id)
        for _ in 0..<10 {
            while !queue.upcoming.isEmpty { queue.advance() }
            let last = queue.current?.track.id
            XCTAssertTrue(queue.advance())
            XCTAssertNotEqual(queue.current?.track.id, last)
            XCTAssertEqual([queue.currentID!] + queue.upcomingIDs, all)
            XCTAssertTrue(queue.isValid)
        }
    }

    func testClearedEntriesNeverReturnThroughRepeat() {
        var queue = PlaybackQueue()
        queue.start(tracks())
        queue.repeatMode = .all
        let current = queue.currentID
        queue.clearUpcoming()
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.currentID, current)
        XCTAssertTrue(queue.upcoming.isEmpty)
    }

    func testRefreshRemovesMissingSongsAndUpdatesAllDuplicateMetadata() {
        let original = tracks()
        var queue = PlaybackQueue()
        queue.start(original)
        queue.append([original[2]])
        queue.reconcile(with: Array(original[2...]))
        XCTAssertEqual(queue.current?.track, original[2])
        XCTAssertEqual(queue.entries.count, 4)
        XCTAssertTrue(queue.isValid)
        queue.reconcile(with: [])
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertTrue(queue.isValid)
    }

    func testRestorationRetainsIdentityHistoryModesAndManualOrder() throws {
        var queue = PlaybackQueue()
        queue.start(tracks())
        queue.advance()
        queue.append(tracks(2))
        queue.move(from: IndexSet(integer: 2), to: 0)
        queue.repeatMode = .one
        let saved = SavedPlayback(queue: queue, folderPath: "/Music", elapsed: 23.5)
        let restored = try JSONDecoder().decode(SavedPlayback.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.queue.entries, queue.entries)
        XCTAssertEqual(restored.queue.upcomingIDs, queue.upcomingIDs)
        XCTAssertEqual(restored.queue.history, queue.history)
        XCTAssertEqual(restored.queue.currentID, queue.currentID)
        XCTAssertEqual(restored.queue.repeatMode, .one)
        XCTAssertEqual(restored.elapsed, 23.5)
    }
}
