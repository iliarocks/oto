import SwiftUI

struct AlbumView: View {
    @Environment(\.albumAccent) private var accent
    @Environment(\.albumAccentInk) private var accentInk
    @Environment(\.albumTextAccent) private var textAccent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let album: Album
    let library: LibraryStore
    let player: PlaybackController
    @State private var headerProgress: CGFloat = 0

    var body: some View {
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
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
                                } action: { headerProgress = $0 }
                            Text(album.artist).font(.title3).foregroundStyle(.secondary)
                            Text("\(album.tracks.count) songs · \(MusicTime.summary(album.duration))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        actionLayout {
                            Button { play(shuffled: false) } label: {
                                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 5)
                                    .foregroundStyle(accentInk)
                            }
                            .accessibilityIdentifier("play-album")
                            Button { play(shuffled: true) } label: {
                                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity).padding(.vertical, 5)
                                    .foregroundStyle(accentInk)
                            }
                            .accessibilityIdentifier("shuffle-album")
                        }
                        .buttonStyle(.borderedProminent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: 340)
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
                                            Image(systemName: player.wantsPlayback ? "speaker.wave.2.fill" : "speaker.fill").font(.caption)
                                        } else { Text(track.trackNumber.map(String.init) ?? "–").font(.subheadline).monospacedDigit() }
                                    }
                                    .foregroundStyle(isCurrent(track) ? accent : Color.secondary)
                                    .frame(width: 26)
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
            .modifier(AlbumScrollEdge())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(backdropProgress)
                    .animation(.easeOut(duration: 0.18), value: headerProgress)
                    .frame(height: topInset)
                    .offset(y: -topInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FadingNavigationTitle(title: album.title, progress: titleProgress)
                    .accessibilityHidden(titleProgress == 0)
            }
        }
    }

    // Offset the two reveal ranges by a small amount in both scroll directions.
    private var backdropProgress: CGFloat { min(headerProgress / 0.88, 1) }
    private var titleProgress: CGFloat { max((headerProgress - 0.12) / 0.88, 0) }

    private var discNumbers: [Int] { Set(album.tracks.map { $0.discNumber ?? 1 }).sorted() }
    private func isCurrent(_ track: Track) -> Bool { player.currentTrack == track }
    private func play(_ track: Track? = nil, shuffled: Bool? = nil) {
        guard let bookmark = library.snapshot?.bookmark else { return }
        player.play(album.tracks, startingAt: track, bookmark: bookmark, shuffled: shuffled)
    }
}

/// The album supplies a backdrop whose visibility follows the title, so disable the
/// independent system scroll-edge frosting while retaining native navigation controls.
private struct AlbumScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
