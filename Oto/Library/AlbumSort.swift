import Foundation

enum AlbumSort: String, CaseIterable, Identifiable {
    case artist, title, recentlyAdded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .artist: "Artist"
        case .title: "Title"
        case .recentlyAdded: "Recently Added"
        }
    }

    func sorted(_ albums: [Album], addedAt: [String: Date]) -> [Album] {
        albums.sorted { lhs, rhs in
            if self == .recentlyAdded {
                let left = addedAt[lhs.id] ?? .distantPast
                let right = addedAt[rhs.id] ?? .distantPast
                if left != right { return left > right }
            }
            let leftFields = self == .title ? [lhs.title, lhs.artist] : [lhs.artist, lhs.title]
            let rightFields = self == .title ? [rhs.title, rhs.artist] : [rhs.artist, rhs.title]
            for (left, right) in zip(leftFields, rightFields) {
                let comparison = left.localizedStandardCompare(right)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return lhs.id < rhs.id
        }
    }
}
