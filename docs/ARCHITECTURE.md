# Architecture

## Ownership

The selected folder owns the audio. Oto never moves, deletes, converts, or rewrites music files. Application Support contains one atomically written JSON snapshot and bounded-size JPEG artwork. There are no third-party frameworks, analytics, network clients, or app-managed music downloads. Files providers may download selected files as part of coordinated reads.

## Library

`LibraryStore` is the main-actor UI model. `LibraryScanner` runs filesystem traversal and metadata extraction on its own actor. The Files picker grants directory access; `FolderAccess` balances security-scoped access and creates/resolves persistent bookmarks. Playback holds an independent scope so a scan's completion cannot revoke its access.

The scanner skips hidden files, packages, and symbolic links. `MusicPath` checks containment again before playback. Reads are coordinated with file providers. Audio decoding and duration use AVFoundation; a bounds-checked FLAC metadata reader handles Vorbis comments and embedded pictures that AVAsset may not expose. Other tags use AVAsset's asynchronous metadata API. Artwork is downsampled to 1,000 pixels and keyed by a content digest to avoid decoding repeated album art during subsequent scans.

A scan stages a replacement snapshot. Cancellation or traversal failure keeps the existing index. Each coordinated read connects task cancellation to its own coordinator's `cancel()`, so waiting for provider access can be interrupted; an accessor already executing must finish. During refresh of the same folder, unreadable tracks retain their prior metadata and receive an issue entry; genuinely removed files disappear. An empty replacement folder is rejected; a successful refresh of the current folder can become empty. Only a successful atomic write publishes the new library. Switching to a different folder stops the prior playback session.

## Playback

`PlaybackController` is a main-actor observable model backed by `AVAudioPlayer`. A separate actor prepares each file, then transfers exclusive ownership to the controller. A generation token rejects stale load completions. The implicit queue is an album's ordered tracks, not a saved playlist.

Audio-session activation happens off the UI actor. Now Playing metadata and remote commands cover play/pause, previous/next, and seeking. Notification handling pauses for route disconnection, resumes after eligible interruptions only when previously playing, and lets the user retry after media-service resets. A lightweight timer publishes coarse playback state; the visible native slider reads precise playback time through CADisplayLink, only while playing on screen in an active scene. Its public thumb-geometry override preserves fractional point positions; the default UISlider rounds them to whole points. Seeking remains native, including VoiceOver, and stops automatic updates while tracking. Background audio is declared in Info.plist.

## UI

SwiftUI NavigationStack, List, ContentUnavailableView, sheets, system materials, and SF Symbols. The library has an inline toolbar count with no page title or search. Album pages use the main heading’s measured safe-area boundary to reveal a native principal toolbar title. A 0.25-second eased opacity animation runs in both directions, independent of swipe speed. A persistent UIKit label animates its alpha, avoiding SwiftUI toolbar content replacement cutting off fade-out. The native animation begins from the current visible alpha when interrupted. Hidden titles are excluded from accessibility; the native label stays mounted so both directions can finish. A floating player uses `safeAreaBar` and capsule-shaped native `glassEffect` on iOS 26+, with a material and safe-area-inset fallback on iOS 18. UIKit supplies the Files picker and AVKit supplies the AirPlay route picker. Semantic colors support light/dark mode, Dynamic Type can scroll naturally, and transport controls have accessibility labels. The icon reuses Nagare's HiraginoSans-W6 geometry settings and Icon Composer material configuration with 音.

## References

- [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Apple: Cancelling file coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel())
- [Apple: AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [Apple: Becoming a Now Playable app](https://developer.apple.com/documentation/mediaplayer/becoming-a-now-playable-app)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

No API keys, online services, cloud database, or Apple Music library authorization are required.

Player labels share `MarqueeText`: native single-line UILabels move in a Core Animation layer with explicit linear timing, a brief initial pause, and a repeated copy. SwiftUI playback updates do not rebuild the moving text or restart its animation. Dynamic Type, width, and title changes rebuild the layout when necessary. Fitting text, Reduce Motion, and inactive scenes stop movement. Accessibility exposes one full label rather than the visual copies. Now Playing has no scroll view; portrait layout gives spare height to artwork, while landscape places artwork beside compact controls. Landscape limits text scaling to XXXL to preserve control access in its limited height; portrait supports the accessibility sizes. Dismissal uses the native sheet gesture and accessibility escape action.

`PlayerBar` is applied to the library and album content inside the navigation stack, rather than outside the stack. This lets each List reserve the actual player height in its scrollable safe area, keeping the last row accessible when playback starts or text size changes.

Album accents come from a cached, off-main-actor sample of artwork. The decoder normalizes a 64-pixel thumbnail to sRGB. A fine histogram feeds deterministic, population-weighted clustering in [Oklab](https://bottosson.github.io/posts/oklab/); neutral pixels and insignificant clusters are excluded. Clusters rank by population and chroma. Each contributes readable source shades for light and dark appearance, allowing a dominant color spread across a gradient to remain dominant. If no suitable shade exists, the accent falls back to black/white. No source music or artwork is modified.

Controls use a 3:1 contrast check against the screen background, including the elevated dark sheet, while song-title accents require 4.5:1 and otherwise remain primary text. The Play button selects black or white lettering for contrast against its fill. These separate checks follow [non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) and [text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) guidance. Missing artwork retains the app accent. Now Playing shows title and artist without an album link or loading-message row.

Motion requests the screen’s supported refresh rate; the phone configuration allows ProMotion. The compositor runs marquee transforms independently of SwiftUI layout. Display-link targets hold a weak slider reference and invalidate when detached; paused/background views do not keep ticking.
