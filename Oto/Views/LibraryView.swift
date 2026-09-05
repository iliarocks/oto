import SwiftUI

struct LibraryView: View {
    @Bindable var library: LibraryStore
    @Bindable var player: PlaybackController
    @State private var showingPicker = false
    @State private var showingFolder = false
    @State private var showingPlayer = false
    @State private var search = ""
    @State private var path: [String] = []
    @State private var chooseAfterFolderDismisses = false
    @FocusState private var searchFocused: Bool

    private var currentAlbum: Album? { library.albums.first { $0.id == player.currentTrack?.albumID } }

    var body: some View {
        // Several sections read the same result. Filter once per view update.
        let results = LibrarySearch(query: search, albums: library.albums)
        NavigationStack(path: $path) {
            Group {
                if library.albums.isEmpty && !library.isScanning { emptyLibrary }
                else {
                    List {
                        if library.isScanning { scanProgress }
                        if !library.isScanning && !results.isActive, let issues = library.snapshot?.issues, !issues.isEmpty {
                            Button { showingFolder = true } label: {
                                Label(issues.count == 1 ? "1 file needs attention" : "\(issues.count) files need attention", systemImage: "exclamationmark.circle")
                                    .font(.subheadline)
                            }
                            .accessibilityIdentifier("library-issues")
                        }
                        if !results.albums.isEmpty {
                            Section {
                                ForEach(results.albums) { album in
                                    NavigationLink(value: album.id) {
                                        HStack(spacing: 14) {
                                            ArtworkView(key: album.artworkKey, directory: library.persistence.artworkDirectory, size: 64)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(album.title).font(.headline).foregroundStyle(.primary)
                                                Text(album.artist).font(.subheadline).foregroundStyle(.secondary)
                                            }
                                            .lineLimit(2)
                                            .padding(.vertical, 5)
                                        }
                                    }
                                    .accessibilityIdentifier("album-\(album.title)")
                                }
                            } header: {
                                Text(results.isActive ? "Albums" : librarySummary)
                                    .textCase(nil)
                            }
                        }
                        if results.isActive && !results.tracks.isEmpty {
                            Section("Songs") {
                                ForEach(results.tracks) { track in
                                    Button { playSearchResult(track) } label: {
                                        HStack(spacing: 12) {
                                            ArtworkView(key: track.artworkKey, directory: library.persistence.artworkDirectory, size: 44)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(track.title).foregroundStyle(.primary)
                                                Text("\(track.artist) · \(track.albumTitle)")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            if player.currentTrack?.id == track.id {
                                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                                    .font(.caption).foregroundStyle(Color.accentColor)
                                            }
                                        }
                                        .padding(.vertical, 5)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Play \(track.title), \(track.artist), \(track.albumTitle)")
                                    .accessibilityIdentifier("search-song-\(track.title)")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if results.isEmpty && results.isActive { ContentUnavailableView.search(text: results.query) }
                    }
                    .searchable(text: $search, prompt: "Albums, artists, or songs")
                    .searchFocused($searchFocused)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await library.refreshAndWait() }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: String.self) { id in
                if let album = library.albums.first(where: { $0.id == id }) {
                    AlbumView(album: album, library: library, player: player)
                } else { ContentUnavailableView("Album Unavailable", systemImage: "music.note") }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(library.snapshot == nil ? "Choose Music Folder" : "Choose Another Folder", systemImage: "folder.badge.plus") { showingPicker = true }
                        if library.snapshot != nil {
                            Button("Refresh Library", systemImage: "arrow.clockwise") { library.refresh() }
                            Button("Music Folder", systemImage: "folder") { showingFolder = true }
                        }
                    } label: { Label("Library Options", systemImage: "ellipsis") }
                    .disabled(library.isScanning)
                    .accessibilityIdentifier("library-options")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil { MiniPlayer(player: player) { showingPlayer = true } }
        }
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                library.choose(url)
                showingPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingFolder, onDismiss: {
            if chooseAfterFolderDismisses {
                chooseAfterFolderDismisses = false
                showingPicker = true
            }
        }) {
            FolderInfoView(library: library) {
                chooseAfterFolderDismisses = true
                showingFolder = false
            }
        }
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(player: player, showAlbum: currentAlbum.map { album in
                {
                    searchFocused = false
                    search = ""
                    path = [album.id]
                    showingPlayer = false
                }
            })
        }
        .onChange(of: library.folderPath) { old, new in
            if old != new {
                player.stop()
                showingPlayer = false
                path = []
                search = ""
            }
        }
        .alert("Couldn't Update Library", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .alert("Couldn't Play", isPresented: Binding(get: { !showingPlayer && player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            if player.currentTrack != nil {
                Button("Try Again") { player.errorMessage = nil; player.resume() }
            }
            Button("Cancel", role: .cancel) { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    private var librarySummary: String {
        let albums = library.albums.count == 1 ? "1 album" : "\(library.albums.count) albums"
        let songs = library.tracks.count == 1 ? "1 song" : "\(library.tracks.count) songs"
        return "\(albums) · \(songs)"
    }

    private func playSearchResult(_ track: Track) {
        guard let album = library.albums.first(where: { $0.id == track.albumID }),
              let bookmark = library.snapshot?.bookmark else { return }
        searchFocused = false
        player.play(album.tracks, startingAt: track, bookmark: bookmark)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(library.snapshot == nil ? "Your music, right here" : "No Songs Found", systemImage: "music.note")
        } description: {
            if let snapshot = library.snapshot {
                Text("Add music to “\(snapshot.folderName)” in Files, then refresh your library.")
            } else {
                Text("Choose a folder of songs or albums from Files. Your music stays in its folder.")
            }
        } actions: {
            if library.snapshot != nil {
                Button { library.refresh() } label: {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("refresh-empty-library")
                Button("Choose Another Folder") { showingPicker = true }.buttonStyle(.bordered)
            } else {
                Button { showingPicker = true } label: {
                    Label("Choose Music Folder", systemImage: "folder.badge.plus")
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("choose-folder")
            }
        }
    }

    private var scanProgress: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(library.isCancelling ? "Cancelling…" : "Reading your music…").font(.headline)
                    Spacer()
                    Button("Cancel") { library.cancelScan() }.font(.subheadline)
                        .disabled(library.isCancelling)
                }
                if let progress = library.progress, progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    Text("\(progress.completed) of \(progress.total) songs").font(.caption).foregroundStyle(.secondary)
                    if !progress.filename.isEmpty {
                        Text(progress.filename).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                } else { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                Text("Files in iCloud may need a moment to download.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
    }
}

private struct FolderInfoView: View {
    let library: LibraryStore
    let chooseFolder: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let snapshot = library.snapshot {
                    Section {
                        LabeledContent("Folder", value: snapshot.folderName)
                        LabeledContent("Songs", value: "\(snapshot.tracks.count)")
                        LabeledContent("Last Updated", value: snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened))
                    } footer: {
                        Text("Oto reads your files in place. After adding or removing music in Files, refresh your library. For offline listening, use Keep Downloaded on the music folder in Files.")
                    }
                    Section {
                        Button("Refresh Library", systemImage: "arrow.clockwise") { library.refresh(); dismiss() }
                        Button("Choose Another Folder", systemImage: "folder") { chooseFolder() }
                            .accessibilityIdentifier("choose-another-folder")
                    }
                    if !snapshot.issues.isEmpty {
                        Section("Files Needing Attention") {
                            ForEach(snapshot.issues) { issue in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(issue.path).font(.subheadline)
                                    Text(issue.message).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Music Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
