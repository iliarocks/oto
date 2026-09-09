import SwiftUI

struct AlbumView: View {
    @Environment(\.albumAccent) private var accent
    @Environment(\.albumAccentInk) private var accentInk
    @Environment(\.albumTextAccent) private var textAccent
    let album: Album
    let library: LibraryStore
    let player: PlaybackController
    @State private var headerProgress: CGFloat = 0

    var body: some View {
        GeometryReader { viewport in
            let viewportTop = viewport.frame(in: .global).minY
            let topInset = viewport.safeAreaInsets.top
            List {
                Section {
                    VStack(spacing: 16) {
                        ArtworkView(key: album.artworkKey, directory: library.persistence.artworkDirectory)
                            .frame(maxWidth: 280)
                        VStack(spacing: 6) {
                            Text(album.title).font(.title2.bold())
                                .accessibilityIdentifier("album-main-title")
                                .onGeometryChange(for: CGFloat.self) { title in
                                    // The viewport already starts below the navigation bar. Adding its
                                    // safe-area inset again moves the trigger a full bar too early.
                                    let distance = viewportTop - title.frame(in: .global).maxY
                                    return min(max(distance / 56, 0), 1)
                                } action: { progress in
                                    // Scrolling can disable implicit animations; explicitly animate
                                    // the shared progress in either direction.
                                    var transaction = Transaction(animation: .easeInOut(duration: 0.22))
                                    transaction.disablesAnimations = false
                                    withTransaction(transaction) { headerProgress = progress }
                                }
                            Text(album.artist).font(.title3).foregroundStyle(.secondary)
                            Text("\(album.tracks.count) songs · \(MusicTime.summary(album.duration))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        Button {
                            if isCurrentAlbum { player.toggle() }
                            else { play() }
                        } label: {
                            PlaybackSymbol(isPlaying: albumIsPlaying)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                                .foregroundStyle(accentInk)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel(albumIsPlaying ? "Pause" : "Play")
                        .accessibilityIdentifier("play-album")
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: 240)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(discNumbers, id: \.self) { disc in
                    Section {
                        ForEach(album.tracks.filter { ($0.discNumber ?? 1) == disc }) { track in
                            Button { play(track) } label: {
                                HStack(spacing: 14) {
                                    Group {
                                        if isCurrent(track) {
                                            Image(systemName: player.wantsPlayback ? "speaker.wave.2.fill" : "speaker.fill")
                                                .font(.caption)
                                                .id(player.wantsPlayback)
                                                .contentTransition(.identity)
                                                .transition(.identity)
                                        } else {
                                            Text(track.trackNumber.map(String.init) ?? "–")
                                                .font(.subheadline).monospacedDigit()
                                                .transition(.identity)
                                        }
                                    }
                                    .foregroundStyle(isCurrent(track) ? accent : Color.secondary)
                                    .frame(width: 26)
                                    .transaction {
                                        $0.animation = nil
                                        $0.disablesAnimations = true
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).foregroundStyle(isCurrent(track) ? textAccent : Color.primary)
                                        if track.artist != album.artist { Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(MusicTime.clock(track.duration)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(track.title), \(MusicTime.clock(track.duration))")
                            .accessibilityValue(isCurrent(track) ? (player.wantsPlayback ? "Playing" : "Paused") : "")
                            .accessibilityIdentifier("track-\(track.title)")
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    if let bookmark = library.snapshot?.bookmark {
                                        player.enqueue([track], bookmark: bookmark)
                                    }
                                } label: { Label("Add to Queue", systemImage: "text.badge.plus").labelStyle(.iconOnly) }
                                .tint(accent)
                                .accessibilityLabel("Add to Queue")
                            }
                        }
                    } header: { if discNumbers.count > 1 { Text("Disc \(disc)") } }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .modifier(FadingHeaderScrollEdge())
            .modifier(AlbumNavigationHeader(title: album.title, progress: headerProgress, height: topInset))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var discNumbers: [Int] { Set(album.tracks.map { $0.discNumber ?? 1 }).sorted() }
    private var isCurrentAlbum: Bool { player.sourceAlbumID == album.id && player.currentTrack != nil }
    private var albumIsPlaying: Bool { isCurrentAlbum && player.wantsPlayback }
    private func isCurrent(_ track: Track) -> Bool { player.currentTrack == track }
    private func play(_ track: Track? = nil) {
        guard let bookmark = library.snapshot?.bookmark else { return }
        player.play(album.tracks, startingAt: track, bookmark: bookmark)
    }
}
