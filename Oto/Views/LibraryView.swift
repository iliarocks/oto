import SwiftUI

struct LibraryView: View {
    @AppStorage("albumSort") private var albumSort: AlbumSort = .artist
    @Bindable var library: LibraryStore
    @Bindable var player: PlaybackController
    @State private var showingPicker = false
    @State private var showingSettings = false
    @State private var showingPlayer = false
    @State private var path: [String] = []
    @State private var chooseAfterSettingsDismisses = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.albums.isEmpty && !library.isScanning { emptyLibrary }
                else {
                    List {
                        if library.isScanning { scanProgress }
                        if !library.isScanning, let issues = library.snapshot?.issues, !issues.isEmpty {
                            Button { showingSettings = true } label: {
                                Label(issues.count == 1 ? "1 file needs attention" : "\(issues.count) files need attention", systemImage: "exclamationmark.circle")
                                    .font(.subheadline)
                            }
                            .accessibilityIdentifier("library-issues")
                            .listRowSeparator(.hidden)
                        }
                        ForEach(albumSort.sorted(library.albums)) { album in
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
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                        .listSectionSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .refreshable { await library.refreshAndWait() }
                }
            }
            .modifier(PlayerBar(player: player) { showingPlayer = true })
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let album = library.albums.first(where: { $0.id == id }) {
                    AlbumView(album: album, library: library, player: player)
                        .modifier(ArtworkTheme(key: album.artworkKey, directory: library.persistence.artworkDirectory))
                        .modifier(PlayerBar(player: player) { showingPlayer = true })
                } else { ContentUnavailableView("Album Unavailable", systemImage: "music.note") }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if library.snapshot != nil {
                        Text(librarySummary)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .accessibilityIdentifier("library-summary")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                        .accessibilityIdentifier("settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort Albums", selection: $albumSort) {
                            ForEach(AlbumSort.allCases) { sort in
                                Text(sort.label).tag(sort)
                            }
                        }
                    } label: {
                        Label("Sort Albums", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("album-sort")
                    .accessibilityValue(albumSort.label)
                    .disabled(library.albums.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                library.choose(url)
                showingPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if chooseAfterSettingsDismisses {
                chooseAfterSettingsDismisses = false
                showingPicker = true
            }
        }) {
            SettingsView(library: library) {
                chooseAfterSettingsDismisses = true
                showingSettings = false
            }
        }
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(player: player)
        }
        .onChange(of: library.folderPath) { old, new in
            if old != new {
                player.stop()
                showingPlayer = false
                path = []
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

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(library.snapshot == nil ? "Choose a folder" : "No Songs Found", systemImage: "music.note")
        } description: {
            if let snapshot = library.snapshot {
                Text("Add music to “\(snapshot.folderName)” in Files, then refresh your library.")
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
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.circle)
                .padding(.top, 16)
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
                Text("iCloud Drive files must be downloaded.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
    }
}

private struct SettingsView: View {
    private static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let library: LibraryStore
    let chooseFolder: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let snapshot = library.snapshot {
                    Section {
                        Button(action: chooseFolder) {
                            HStack(spacing: 12) {
                                Label("Folder", systemImage: "folder")
                                    .layoutPriority(1)
                                Text(snapshot.folderName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Folder")
                        .accessibilityValue(snapshot.folderName)
                        .accessibilityHint("Choose another music folder")
                        .accessibilityIdentifier("settings-folder")
                        Button("Refresh", systemImage: "arrow.clockwise") { library.refresh(); dismiss() }
                            .accessibilityIdentifier("settings-refresh")
                    } header: {
                        Text("Library")
                    } footer: {
                        Text("Last update \(snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened)). Refresh after adding or removing files. iCloud Drive files must be downloaded.")
                    }
                    .disabled(library.isScanning)
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
                } else {
                    Section("Library") {
                        Button("Choose Music Folder", systemImage: "folder.badge.plus") { chooseFolder() }
                            .disabled(library.isScanning)
                            .accessibilityIdentifier("settings-choose-folder")
                    }
                }
                Section {
                    externalLink("Privacy", systemImage: "hand.raised", destination: URL(string: "https://oto.page/#privacy")!)
                        .accessibilityIdentifier("settings-privacy")
                    externalLink("Support", systemImage: "lifepreserver", destination: URL(string: "https://oto.page/#support")!)
                        .accessibilityIdentifier("settings-support")
                } header: {
                    Text("About")
                } footer: {
                    Text("Version \(Self.appVersion)")
                }
            }
            .buttonStyle(.plain)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func externalLink(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }

}
