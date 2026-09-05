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
        self.albums = albums.filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
        }
        tracks = albums.flatMap(\.tracks).filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
                || $0.albumTitle.localizedStandardContains(query) || $0.albumArtist.localizedStandardContains(query)
        }
    }
}
