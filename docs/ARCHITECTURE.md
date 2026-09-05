# Architecture

## Ownership

The selected folder owns the audio. Oto never moves, deletes, converts, or rewrites music files. Application Support contains one atomically written JSON snapshot and bounded-size JPEG artwork. There are no third-party frameworks, analytics, network clients, or app-managed music downloads. Files providers may download selected files as part of coordinated reads.

## Library

`LibraryStore` is the main-actor UI model. `LibraryScanner` runs filesystem traversal and metadata extraction on its own actor. The Files picker grants directory access; `FolderAccess` balances security-scoped access and creates/resolves persistent bookmarks. Playback holds an independent scope so a scan's completion cannot revoke its access.

The scanner skips hidden files, packages, and symbolic links. `MusicPath` checks containment again before playback. Reads are coordinated with file providers. Audio decoding and duration use AVFoundation; a bounds-checked FLAC metadata reader handles Vorbis comments and embedded pictures that AVAsset may not expose. Other tags use AVAsset's asynchronous metadata API. Artwork is downsampled to 1,000 pixels and keyed by a content digest to avoid decoding repeated album art during subsequent scans.

A scan stages a replacement snapshot. Cancellation or traversal failure keeps the existing index. Each coordinated read connects task cancellation to its own coordinator's `cancel()`, so waiting for provider access can be interrupted; an accessor already executing must finish. During refresh of the same folder, unreadable tracks retain their prior metadata and receive an issue entry; genuinely removed files disappear. An empty replacement folder is rejected; a successful refresh of the current folder can become empty. Only a successful atomic write publishes the new library. Switching to a different folder stops the prior playback session.

## Playback

`PlaybackController` is a main-actor observable model backed by `AVAudioPlayer`. A separate actor prepares each file, then transfers exclusive ownership to the controller. A generation token rejects stale load completions. The implicit queue is an album's ordered tracks, not a saved playlist.

Audio-session activation happens off the UI actor. Now Playing metadata and remote commands cover play/pause, previous/next, and seeking. Notification handling pauses for route disconnection, resumes after eligible interruptions only when previously playing, and lets the user retry after media-service resets. A lightweight timer updates the visible scrubber while playback runs. Background audio is declared in Info.plist.

## UI

SwiftUI NavigationStack, List, ContentUnavailableView, sheets, system materials, and SF Symbols. The library has an inline toolbar count with no page title or search. A floating player uses `safeAreaBar` and capsule-shaped native `glassEffect` on iOS 26+, with a material and safe-area-inset fallback on iOS 18. UIKit supplies the Files picker and AVKit supplies the AirPlay route picker. Semantic colors support light/dark mode, Dynamic Type can scroll naturally, and transport controls have accessibility labels. The icon reuses Nagare's HiraginoSans-W6 geometry settings and Icon Composer material configuration with 音.

## References

- [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Apple: Cancelling file coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel())
- [Apple: AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [Apple: Becoming a Now Playable app](https://developer.apple.com/documentation/mediaplayer/becoming-a-now-playable-app)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

No API keys, online services, cloud database, or Apple Music library authorization are required.

Player labels share `MarqueeText`: measured overflow enables a bounded 30 Hz timeline, a brief initial pause, and a repeated label that cycles horizontally. Fitting text, Reduce Motion, and inactive scenes pause the timeline. Accessibility exposes one full label rather than the visual copies. Now Playing has no scroll view; portrait layout gives spare height to artwork, while landscape places artwork beside compact controls. Landscape limits text scaling to XXXL to preserve control access in its limited height; portrait supports the accessibility sizes. Dismissal uses the native sheet gesture and accessibility escape action.

`PlayerBar` is applied to the library and album content inside the navigation stack, rather than outside the stack. This lets each List reserve the actual player height in its scrollable safe area, keeping the last row accessible when playback starts or text size changes.
