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

/// Source entries are stable; manual additions are consumed when left.
struct PlaybackQueue: Codable, Sendable {
    private(set) var source: [QueueEntry] = []
    private(set) var sourcePosition = -1
    private(set) var queued: [QueueEntry] = []
    private(set) var current: QueueEntry?
    var repeatMode: RepeatMode = .off

    var currentID: UUID? { current?.id }
    var sourceAlbumID: String? {
        guard let first = source.first, source.allSatisfy({ $0.track.albumID == first.track.albumID }) else { return nil }
        return first.track.albumID
    }
    var sourceTitle: String? {
        guard let first = source.first else { return nil }
        return sourceAlbumID != nil ? first.track.albumTitle : "Previous Queue"
    }
    var sourceUpcoming: [QueueEntry] { Array(source.dropFirst(sourcePosition + 1)) }
    var upcoming: [QueueEntry] { queued + sourceUpcoming }
    var isCurrentQueued: Bool { current != nil && !source.contains { $0.id == currentID } }
    var canAdvance: Bool {
        current != nil && (!queued.isEmpty || !sourceUpcoming.isEmpty || (repeatMode != .off && !source.isEmpty))
    }

    mutating func start(_ tracks: [Track], at track: Track? = nil) {
        guard !tracks.isEmpty else { return }
        source = tracks.map(QueueEntry.init)
        sourcePosition = track.flatMap { selected in source.firstIndex { $0.track.id == selected.id } } ?? 0
        current = source[sourcePosition]
        // Pending additions survive choosing a new source. An active addition is consumed.
    }

    mutating func append(_ tracks: [Track]) {
        queued += tracks.map(QueueEntry.init)
        if current == nil && !queued.isEmpty { current = queued.removeFirst() }
    }

    @discardableResult mutating func advance(automatically: Bool = false) -> Bool {
        guard current != nil else { return false }
        if automatically && repeatMode == .one { return true }
        guard canAdvance else {
            if automatically && isCurrentQueued { current = nil }
            return false
        }
        if !automatically && repeatMode == .one { repeatMode = .all }
        if !queued.isEmpty { current = queued.removeFirst() }
        else {
            sourcePosition = sourcePosition + 1 < source.count ? sourcePosition + 1 : 0
            current = source[sourcePosition]
        }
        return true
    }

    /// Previous follows source order, never consumed manual additions.
    @discardableResult mutating func previous() -> Bool {
        guard current != nil else { return false }
        let destination = isCurrentQueued ? sourcePosition : sourcePosition - 1
        guard source.indices.contains(destination) else { return false }
        sourcePosition = destination
        current = source[destination]
        if repeatMode == .one { repeatMode = .all }
        return true
    }

    @discardableResult mutating func jump(to id: UUID) -> Bool {
        if let index = queued.firstIndex(where: { $0.id == id }) {
            current = queued[index]
            queued.removeFirst(index + 1)
        } else if let index = source.firstIndex(where: { $0.id == id }), index > sourcePosition {
            // Selecting a later displayed row skips everything preceding it.
            queued.removeAll()
            sourcePosition = index
            current = source[index]
        } else { return false }
        if repeatMode == .one { repeatMode = .all }
        return true
    }

    mutating func remove(_ ids: Set<UUID>) {
        queued.removeAll { ids.contains($0.id) }
        let removable = Set(sourceUpcoming.map(\.id)).intersection(ids)
        source.removeAll { removable.contains($0.id) }
    }

    mutating func clearUpcoming() { queued.removeAll() }

    mutating func moveQueued(from offsets: IndexSet, to destination: Int) {
        queued = Self.moving(queued, from: offsets, to: destination)
    }

    mutating func moveSourceUpcoming(from offsets: IndexSet, to destination: Int) {
        source = Array(source.prefix(sourcePosition + 1)) + Self.moving(sourceUpcoming, from: offsets, to: destination)
    }

    private static func moving(_ entries: [QueueEntry], from offsets: IndexSet, to destination: Int) -> [QueueEntry] {
        let valid = offsets.filter { entries.indices.contains($0) }
        let moved = valid.sorted().map { entries[$0] }
        let remaining = entries.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let index = min(max(0, destination - valid.filter { $0 < destination }.count), remaining.count)
        return Array(remaining.prefix(index)) + moved + Array(remaining.dropFirst(index))
    }

    /// Refresh metadata and discard missing files without resurrecting consumed entries.
    mutating func reconcile(with tracks: [Track]) {
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func updated(_ entry: QueueEntry) -> QueueEntry? {
            guard let track = byID[entry.track.id] else { return nil }
            var result = entry; result.track = track; return result
        }
        let survivingPrefix = source.prefix(sourcePosition + 1).compactMap(updated).count
        let previous = current
        source = source.compactMap(updated)
        sourcePosition = survivingPrefix - 1
        queued = queued.compactMap(updated)
        current = current.flatMap(updated)
        if previous != nil && current == nil {
            if !queued.isEmpty { current = queued.removeFirst() }
            else if sourcePosition + 1 < source.count {
                sourcePosition += 1
                current = source[sourcePosition]
            }
        }
        if current == nil { clear() }
    }

    mutating func clear() {
        source = []; sourcePosition = -1; queued = []; current = nil
    }

    var isValid: Bool {
        let ids = (source + queued).map(\.id)
        guard Set(ids).count == ids.count, sourcePosition >= -1, sourcePosition < source.count else { return false }
        guard let current else { return source.isEmpty && queued.isEmpty }
        guard !queued.contains(where: { $0.id == current.id }) else { return false }
        if let index = source.firstIndex(where: { $0.id == current.id }) { return index == sourcePosition }
        return true
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case source, sourcePosition, queued, current, repeatMode
        case entries, currentID, upcomingIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        repeatMode = try values.decode(RepeatMode.self, forKey: .repeatMode)
        if values.contains(.source) {
            source = try values.decode([QueueEntry].self, forKey: .source)
            sourcePosition = try values.decode(Int.self, forKey: .sourcePosition)
            queued = try values.decode([QueueEntry].self, forKey: .queued)
            current = try values.decodeIfPresent(QueueEntry.self, forKey: .current)
        } else {
            // The old flat queue has no provenance. Preserve its next-song order as
            // a legacy source until the user chooses an album, rather than guessing.
            let entries = try values.decode([QueueEntry].self, forKey: .entries)
            let id = try values.decodeIfPresent(UUID.self, forKey: .currentID)
            let upcoming = try values.decode([UUID].self, forKey: .upcomingIDs)
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard Set(entries.map(\.id)).count == entries.count,
                  Set(upcoming).count == upcoming.count, upcoming.allSatisfy({ byID[$0] != nil }),
                  !upcoming.contains(where: { $0 == id }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid saved queue"))
            }
            current = id.flatMap { byID[$0] }
            if let current {
                source = entries.filter { $0.id != id && !upcoming.contains($0.id) } + [current]
                sourcePosition = source.count - 1
                source += upcoming.compactMap { byID[$0] }
            } else if !entries.isEmpty {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing current entry"))
            }
        }
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid saved source or queue"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source)
        try values.encode(sourcePosition, forKey: .sourcePosition)
        try values.encode(queued, forKey: .queued)
        try values.encodeIfPresent(current, forKey: .current)
        try values.encode(repeatMode, forKey: .repeatMode)
    }
}

struct SavedPlayback: Codable {
    let queue: PlaybackQueue
    let folderPath: String?
    let elapsed: TimeInterval
}
