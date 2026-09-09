import SwiftUI

@main
struct OtoApp: App {
    @State private var library: LibraryStore
    @State private var player: PlaybackController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaults.standard.removeObject(forKey: "albumSort")
        var persistence = LibraryPersistence.live
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["OTO_UI_TEST"] == "1" {
            persistence = LibraryPersistence(directory: URL.applicationSupportDirectory.appendingPathComponent("OtoUITests"))
            if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                try? FileManager.default.removeItem(at: persistence.directory)
            }
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-empty-library") {
            // A separate, temporary store lets the real empty state stay interactive
            // without reading or replacing the user's saved music library.
            persistence = LibraryPersistence(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("OtoEmptyPreview-\(UUID().uuidString)", isDirectory: true))
        }
        #endif
        let library = LibraryStore(persistence: persistence)
        _library = State(initialValue: library)
        let player = PlaybackController(artworkDirectory: persistence.artworkDirectory, library: library.snapshot)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--clear-playback") { player.stop() }
        #endif
        _player = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library, player: player)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { player.checkpoint() }
                }
                .task {
                    #if DEBUG && targetEnvironment(simulator)
                    if let path = ProcessInfo.processInfo.environment["OTO_MUSIC_FOLDER"] {
                        library.choose(URL(fileURLWithPath: path, isDirectory: true))
                    }
                    #endif
                }
        }
    }
}
