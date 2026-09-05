# Work log

## 2026-09-04 — Scope and foundation

Read the preceding “DRM Free Music Services” discussion and Nagare's design guide and SwiftUI views. Confirmed folder ownership and FLAC are central requirements. Working name: Oto; minimum iOS 18, native SwiftUI, no dependencies. Xcode 27 beta 6 and an iOS 27 simulator are available locally; use DEVELOPER_DIR per invocation without changing the machine's selected toolchain.

Implementation sequence:
1. Library models, durable folder access, metadata reading, and deterministic album grouping.
2. Native browsing and playback, including audio session and remote controls.
3. File-format, persistence, playback, and UI checks; address findings; document limitations.

The music directory remains canonical. Only bookmarks, metadata, and resized cover art are stored by the app. Refresh is explicit in this first version. Folder replacement must be transactional: keep the prior library if the new scan fails or is cancelled.

## First development build — 22:40

Built and installed version 0.1 (1) on the connected iPhone at the user's request. Folder selection is done through the native Files picker. The simulator indexed the user's beabadoobee and Panchiko albums (23 FLAC songs), including embedded covers and correct track order. The UI test reached real FLAC playback, pause, and Now Playing. Eleven unit/integration tests pass, covering formats, tags, album grouping, file containment, persistence, failure recovery, and playback. Further UI checks and hardening are in progress; this is an early development build.

Fixed findings so far: replaying the last song now immediately resets displayed time; the mini player stays visible on pushed album screens. The remaining UI test failure is an ambiguous test selector matching both the mini player's and sheet's Next button.
