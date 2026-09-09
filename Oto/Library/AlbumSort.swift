import Foundation

enum AlbumSort: String, CaseIterable, Identifiable {
    case artist, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .artist: "Artist"
        case .title: "Title"
        }
    }

    func sorted(_ albums: [Album]) -> [Album] {
        albums.sorted { lhs, rhs in
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
