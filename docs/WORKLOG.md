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

## Hardening and UI — 22:50

The user tried the first phone build and said it looked good, with UI changes to discuss later. Kept that installation running rather than interrupting it with updates.

- Fixed the ambiguous UI test selector and replaced the personal library path with portable synthetic fixtures.
- Added coverage for cancelled replacement, unreadable versus deleted files on refresh, automatic track advancement, interruption resumption, headphone-disconnection notification handling, Now Playing metadata, and stop-during-load races.
- Allowed a successful refresh to empty a library; kept an empty new folder from accidentally replacing an existing library. Switching folders now stops the previous queue.
- Made the playback error alert available inside Now Playing and added VoiceOver seeking increments.
- Avoided repeatedly decoding identical embedded artwork by checking its content digest first.
- Checked dark mode and the largest accessibility text size. Corrected prominent-button contrast in dark mode and made the sheet-dismiss control neutral.
- Replaced the provisional icon with 音. Confirmed HiraginoSans-W6 exactly reproduces Nagare's original SVG before generating the new glyph; copied its scale and material configuration.

Validation: 15 unit/integration tests and 3 UI tests pass on iPhone 17 Pro / iOS 27 in dark mode, including large-text navigation. The earlier light-mode run passed all 17 tests then present. Real library validation indexed 23 FLAC tracks across Fake It Flowers and D-E-A-T-H-M-E-T-A-L and reached playback, pause, and Now Playing. No original music files were modified.

Limits of validation: background playback, physical lock-screen/headphone/AirPlay behavior, iCloud eviction/re-download, and older iOS versions still need device testing. Notification tests validate interruption policy, not actual incoming calls. Xcode beta emits an App Intents extraction notice (there is no App Intents dependency) and occasional simulator/audio-session diagnostics; app compilation has no Swift warnings. The phone currently has the earlier build 0.1 (1); later refinements are in Git and will be installed when they won't interrupt the user.

## Second phone build — 22:53

At the user's request before bed, built, installed, and launched version 0.1 (2) on the iPhone. This supersedes the previous installation note: the device now includes the 音 icon, dark-mode contrast fixes, visible Now Playing errors, VoiceOver seeking, refresh recovery, folder-switch playback reset, and artwork deduplication. Signed device build succeeds. User authorized a few more hours of focused work overnight; continue in this task until approximately 02:00 Pacific, prioritizing actual reliability/UI findings and keeping the phone undisturbed.

## Latest user direction — usefulness and interaction quality

Give feature usefulness and product judgment equal attention to reliability. For every feature, interaction, and UI component, ask whether it is the best available native pattern for its purpose, whether it makes sense, and whether it is pragmatic and worth keeping. Walk through the actual listening experience and improve or simplify friction. Modest improvements to the core flow are welcome; avoid spending the night exclusively on tests and internals. Existing boundaries remain: no playlists, decorative transitions, or unrelated features. The overnight continuation prompt has been updated to carry this direction forward.
