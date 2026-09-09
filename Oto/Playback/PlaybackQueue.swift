import Foundation

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    var label: String {
        switch self { case .off: "Repeat Off"; case .all: "Repeat All"; case .one: "Repeat One" }
    }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
    var next: Self { switch self { case .off: .all; case .all: .one; case .one: .off } }
}

struct QueueEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var track: Track
    init(track: Track) { id = UUID(); self.track = track }
}

/// Canonical entries define playback/repeat order; history records actual listening.
/// Each insertion has its own identity, including repeated copies of the same song.
struct PlaybackQueue: Codable, Sendable {
    private(set) var entries: [QueueEntry] = []
    private(set) var currentID: UUID?
    private(set) var upcomingIDs: [UUID] = []
    private(set) var history: [UUID] = []
    var repeatMode: RepeatMode = .off

    var current: QueueEntry? { entries.first { $0.id == currentID } }
    var upcoming: [QueueEntry] {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return upcomingIDs.compactMap { byID[$0] }
    }
    var canAdvance: Bool { !upcomingIDs.isEmpty || (repeatMode == .all && currentID != nil) }

    mutating func start(_ tracks: [Track], at track: Track? = nil) {
        entries = tracks.map(QueueEntry.init)
        history = []
        guard !entries.isEmpty else { currentID = nil; upcomingIDs = []; return }
        let index = track.flatMap { track in entries.firstIndex { $0.track.id == track.id } } ?? 0
        currentID = entries[index].id
        upcomingIDs = Array(entries.dropFirst(index + 1).map(\.id))
    }

    mutating func append(_ tracks: [Track]) {
        let added = tracks.map(QueueEntry.init)
        entries += added
        upcomingIDs += added.map(\.id)
        if currentID == nil && !upcomingIDs.isEmpty { currentID = upcomingIDs.removeFirst() }
    }

    @discardableResult mutating func advance(automatically: Bool = false) -> Bool {
        guard let currentID else { return false }
        if automatically && repeatMode == .one { return true }
        if upcomingIDs.isEmpty {
            guard repeatMode == .all else { return false }
            upcomingIDs = entries.map(\.id)
        }
        guard !upcomingIDs.isEmpty else { return false }
        history.append(currentID)
        // Retain useful listening history without growing forever during repeat.
        if history.count > 1000 { history.removeFirst(history.count - 1000) }
        self.currentID = upcomingIDs.removeFirst()
        return true
    }

    @discardableResult mutating func previous() -> Bool {
        guard let previous = history.popLast() else { return false }
        if let currentID {
            upcomingIDs.removeAll { $0 == currentID }
            upcomingIDs.insert(currentID, at: 0)
        }
        // A repeat boundary can put a history entry back into the upcoming cycle.
        upcomingIDs.removeAll { $0 == previous }
        currentID = previous
        return true
    }

    @discardableResult mutating func jump(to id: UUID) -> Bool {
        guard let index = upcomingIDs.firstIndex(of: id) else { return false }
        if let currentID { history.append(currentID) }
        currentID = id
        upcomingIDs.removeFirst(index + 1)
        return true
    }

    mutating func remove(_ ids: Set<UUID>) {
        let removable = ids.subtracting(currentID.map { [$0] } ?? [])
        entries.removeAll { removable.contains($0.id) }
        upcomingIDs.removeAll { removable.contains($0) }
        history.removeAll { removable.contains($0) }
    }

    mutating func clearUpcoming() { remove(Set(upcomingIDs)) }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().compactMap { upcomingIDs.indices.contains($0) ? upcomingIDs[$0] : nil }
        let remaining = upcomingIDs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let index = min(max(0, destination - offsets.filter { $0 < destination }.count), remaining.count)
        upcomingIDs = Array(remaining.prefix(index)) + moving + Array(remaining.dropFirst(index))
        let reordered = upcoming
        let ids = Set(upcomingIDs)
        entries = entries.filter { !ids.contains($0.id) } + reordered
    }

    /// A refresh updates metadata and removes missing entries; never resumes by itself.
    mutating func reconcile(with tracks: [Track]) {
        let byPath = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        entries = entries.compactMap { entry in
            guard let track = byPath[entry.track.id] else { return nil }
            var updated = entry; updated.track = track; return updated
        }
        let valid = Set(entries.map(\.id))
        upcomingIDs.removeAll { !valid.contains($0) }
        history.removeAll { !valid.contains($0) }
        if let currentID, !valid.contains(currentID) {
            self.currentID = upcomingIDs.isEmpty ? nil : upcomingIDs.removeFirst()
        }
        if currentID == nil { entries = []; upcomingIDs = []; history = [] }
    }

    mutating func clear() {
        entries = []; currentID = nil; upcomingIDs = []; history = []
    }

    var isValid: Bool {
        let ids = Set(entries.map(\.id))
        return ids.count == entries.count && Set(upcomingIDs).count == upcomingIDs.count
            && upcomingIDs.allSatisfy(ids.contains) && history.allSatisfy(ids.contains)
            && (currentID.map(ids.contains) ?? entries.isEmpty)
    }
}

struct SavedPlayback: Codable {
    let queue: PlaybackQueue
    let folderPath: String?
    let elapsed: TimeInterval
}
