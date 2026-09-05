import Foundation

struct LibrarySearch {
    let query: String
    let albums: [Album]
    let tracks: [Track]
    var isActive: Bool { !query.isEmpty }
    var isEmpty: Bool { albums.isEmpty && tracks.isEmpty }

    init(query: String, albums: [Album]) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query
        guard !query.isEmpty else { self.albums = albums; tracks = []; return }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        func matches(_ fields: [String]) -> Bool {
            terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
        }
        self.albums = albums.filter {
            matches([$0.title, $0.artist])
        }
        tracks = albums.flatMap(\.tracks).filter {
            matches([$0.title, $0.artist, $0.albumTitle, $0.albumArtist])
        }
    }
}
