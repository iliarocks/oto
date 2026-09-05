import SwiftUI

struct LibraryView: View {
    @Bindable var library: LibraryStore
    @Bindable var player: PlaybackController
    @State private var showingPicker = false
    @State private var showingFolder = false
    @State private var showingPlayer = false
    @State private var search = ""

    private var visibleAlbums: [Album] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return library.albums }
        return library.albums.filter { album in
            [album.title, album.artist].contains { $0.localizedStandardContains(search) }
            || album.tracks.contains { $0.title.localizedStandardContains(search) || $0.artist.localizedStandardContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.albums.isEmpty && !library.isScanning { emptyLibrary }
                else {
                    List {
                        if library.isScanning { scanProgress }
                        if !library.albums.isEmpty {
                            Section {
                                ForEach(visibleAlbums) { album in
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
                                Text("\(library.albums.count) albums · \(library.tracks.count) songs")
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if visibleAlbums.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) }
                    }
                    .searchable(text: $search, prompt: "Albums, artists, or songs")
                    .refreshable { library.refresh() }
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
                        Button("Choose Music Folder", systemImage: "folder.badge.plus") { showingPicker = true }
                        if library.snapshot != nil {
                            Button("Refresh Library", systemImage: "arrow.clockwise") { library.refresh() }
                            Button("Music Folder", systemImage: "folder") { showingFolder = true }
                        }
                    } label: { Label("Library Options", systemImage: "ellipsis") }
                    .disabled(library.isScanning)
                    .accessibilityIdentifier("library-options")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentTrack != nil { MiniPlayer(player: player) { showingPlayer = true } }
            }
        }
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                library.choose(url)
                showingPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingFolder) { FolderInfoView(library: library) { showingFolder = false; showingPicker = true } }
        .sheet(isPresented: $showingPlayer) { NowPlayingView(player: player) }
        .alert("Couldn't Update Library", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .alert("Couldn't Play", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK", role: .cancel) { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Your music, right here", systemImage: "music.note")
        } description: {
            Text("Choose a folder of songs or albums from Files. Your music stays in its folder.")
        } actions: {
            Button("Choose Music Folder", systemImage: "folder.badge.plus") { showingPicker = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("choose-folder")
        }
    }

    private var scanProgress: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Reading your music…").font(.headline)
                    Spacer()
                    Button("Cancel") { library.cancelScan() }.font(.subheadline)
                }
                if let progress = library.progress, progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    Text("\(progress.completed) of \(progress.total) songs").font(.caption).foregroundStyle(.secondary)
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
                        LabeledContent("Last Read", value: snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened))
                    } footer: {
                        Text("Oto reads your files in place. After adding or removing music in Files, refresh your library. For offline listening, use Keep Downloaded on the music folder in Files.")
                    }
                    Section {
                        Button("Refresh Library", systemImage: "arrow.clockwise") { library.refresh(); dismiss() }
                        Button("Choose Another Folder", systemImage: "folder") { chooseFolder() }
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
