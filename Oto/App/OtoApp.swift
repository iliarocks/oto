import SwiftUI

@main
struct OtoApp: App {
    @State private var library: LibraryStore
    @State private var player: PlaybackController

    init() {
        var persistence = LibraryPersistence.live
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["OTO_UI_TEST"] == "1" {
            persistence = LibraryPersistence(directory: URL.applicationSupportDirectory.appendingPathComponent("OtoUITests"))
            if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                UserDefaults.standard.removeObject(forKey: "albumSort")
                try? FileManager.default.removeItem(at: persistence.directory)
            }
        }
        #endif
        _library = State(initialValue: LibraryStore(persistence: persistence))
        _player = State(initialValue: PlaybackController(artworkDirectory: persistence.artworkDirectory))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library, player: player)
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
