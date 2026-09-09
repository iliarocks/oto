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
        queue.start(tracks, at: tracks[2], shuffled: false)
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

    func testShuffleOnlyChangesUpcomingAndRestoresOriginalOrder() {
        let tracks = tracks(20)
        var queue = PlaybackQueue()
        queue.start(tracks, shuffled: false)
        queue.advance()
        let current = queue.currentID
        let remaining = queue.upcomingIDs
        queue.setShuffle(true)
        XCTAssertEqual(queue.currentID, current)
        XCTAssertEqual(Set(queue.upcomingIDs), Set(remaining))
        queue.setShuffle(false)
        XCTAssertEqual(queue.upcomingIDs, remaining)
        queue.start(tracks, at: tracks[7], shuffled: true)
        XCTAssertEqual(queue.current?.track, tracks[7])
        XCTAssertEqual(Set(queue.upcoming.map(\.track.id)), Set(tracks.filter { $0 != tracks[7] }.map(\.id)))
    }

    func testAppendsOrderedAlbumsAndIndependentlyRemovesDuplicates() {
        let tracks = tracks()
        var queue = PlaybackQueue()
        queue.start(tracks, shuffled: true)
        let original = queue.upcomingIDs
        queue.append(Array(tracks.prefix(2)))
        XCTAssertEqual(Array(queue.upcomingIDs.prefix(original.count)), original)
        XCTAssertEqual(queue.upcoming.suffix(2).map(\.track), Array(tracks.prefix(2)))
        let duplicate = queue.upcoming.last!
        queue.remove([duplicate.id])
        XCTAssertEqual(queue.entries.filter { $0.track == duplicate.track }.count, 1)
        XCTAssertEqual(Set(queue.entries.map(\.id)).count, queue.entries.count)
    }

    func testManualOrderingSurvivesShuffleRoundTrip() {
        var queue = PlaybackQueue()
        queue.start(tracks(), shuffled: false)
        let current = queue.currentID
        let last = queue.upcomingIDs.last!
        queue.move(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(queue.upcomingIDs.first, last)
        let edited = queue.upcomingIDs
        queue.setShuffle(true)
        queue.setShuffle(false)
        XCTAssertEqual(queue.upcomingIDs, edited)
        XCTAssertEqual(queue.currentID, current)
    }

    func testJumpSkipsEntriesButPreviousReturnsToActualSong() {
        var queue = PlaybackQueue()
        queue.start(tracks(), shuffled: false)
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
        queue.start(tracks(2), shuffled: false)
        queue.repeatMode = .one
        let first = queue.currentID
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.currentID, first)
        XCTAssertTrue(queue.advance())
        XCTAssertNotEqual(queue.currentID, first)
        XCTAssertFalse(queue.canAdvance)
        XCTAssertTrue(queue.advance(automatically: true))
    }

    func testRepeatAllUsesFreshCompleteCyclesAndAvoidsBoundaryRepeat() {
        var queue = PlaybackQueue()
        queue.start(tracks(), shuffled: true)
        queue.repeatMode = .all
        let all = Set(queue.entries.map(\.id))
        for _ in 0..<10 {
            while !queue.upcoming.isEmpty { queue.advance() }
            let last = queue.current?.track.id
            XCTAssertTrue(queue.advance())
            XCTAssertNotEqual(queue.current?.track.id, last)
            XCTAssertEqual(Set(queue.upcomingIDs + [queue.currentID!]), all)
            XCTAssertTrue(queue.isValid)
        }
    }

    func testClearedEntriesNeverReturnThroughRepeat() {
        var queue = PlaybackQueue()
        queue.start(tracks(), shuffled: false)
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
        queue.start(original, shuffled: false)
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
        queue.start(tracks(), shuffled: true)
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
        XCTAssertTrue(restored.queue.isShuffled)
        XCTAssertEqual(restored.elapsed, 23.5)
    }
}
