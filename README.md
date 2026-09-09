# Oto

A small native iOS player for a folder of DRM-free music. Working name.

## First version

- Choose an existing music folder in Files. Read it in place; never move, rewrite, or delete the originals.
- Browse albums and tracks, with embedded metadata and artwork.
- Play FLAC, ALAC, AAC, MP3, WAV, and AIFF using Apple's audio stack.
- Simple Now Playing controls, seeking, album-order playback, background audio, lock-screen controls, and AirPlay.
- Keep access and a lightweight library index across launches.

SwiftUI system components, restrained styling, and no third-party dependencies. Inspired by Nagare's native design approach. No playlists, accounts, streaming service integrations, or ornamental transitions.

## Development

Requires Xcode 26 or newer (the checked-in icon uses Icon Composer) and iOS 18 or newer. Developed and tested with Xcode 27 beta 6 and iOS 27. Open `Oto.xcodeproj`, select the Oto scheme, and choose an iPhone simulator. The project currently uses the same development signing team as Nagare; change it for other accounts.

```sh
# Use the Xcode installation you have available, without changing xcode-select.
export DEVELOPER_DIR="/Applications/Xcode Beta 6.app/Contents/Developer"
xcodebuild -project Oto.xcodeproj -scheme Oto \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build test
```

Tests include small original, nearly silent audio fixtures. No personal music or copyrighted album art is included in the repository. `Scripts/generate-fixtures.sh` regenerates fixtures using FFmpeg; FFmpeg is **not** an app dependency.

To regenerate the vector icon on macOS:

```sh
swift Scripts/generate-icon.swift HiraginoSans-W6 '#171717' \
  Oto/AppIcon.icon/Assets/OtoKanji-W6.svg
```

## Using Oto

1. Tap the **folder-plus** button, navigate to your folder in Files, and tap **Open**.
2. Open an album, then tap **Play** or an individual song. If the current song belongs to that album, its main button switches between Play and Pause without replacing the queue; playing another album replaces the queue and starts in album order.
3. Tap the floating player for seeking, previous/next, repeat, AirPlay, and the queue. Repeat cycles through Off, All, and One. Previous restarts the song after three seconds; otherwise it follows listening history. Skipping while paused stays paused. Swipe down to dismiss Now Playing.
4. After changing the contents of your folder, pull to refresh or use **Settings → Refresh**. A notice in the library links to any files that couldn't be read. **Settings**, opened from the gear at the top left, shows the selected folder; tap its **Folder** row to choose another. Its About section links to Privacy and Support.

Swipe left on an album or song and tap the queue-plus icon to append it to the queue. The queue button in Now Playing switches between artwork and Playing Next. Touch and hold a queued row to drag it into a new position, swipe it to remove it, or tap **Clear** to remove upcoming songs. The queue button sits to the left of Previous, opposite Repeat; switching views resizes the artwork into the queue thumbnail while keeping playback controls fixed. Adding while paused stays paused; with nothing loaded, adding starts playback. Queue entries can include duplicates.

The queue, playback modes, current song, and position are saved. Reopening restores playback paused and does not open an audio file until you tap Play.

The toolbar shows your album and song count. The top-right sort menu offers Artist and Title and remembers your choice. Browsing stays focused on albums, without search. The compact player uses native Liquid Glass on iOS 26 and later, with a material capsule on older supported versions.

Long titles and artist names stay on one line and scroll horizontally in both players. Short text stays still. Now Playing fits its controls on screen, with artwork adapting to the available space; swipe down to dismiss it. Text motion respects Reduce Motion, and VoiceOver reads the full label.

iCloud Drive files must be downloaded before Oto can scan or play them. Use **Keep Downloaded** on the folder in Files, wait for it to finish, then refresh Oto. Oto does not maintain a second copy of your audio. Both players keep the artist and play/pause control visible while songs open. Pause also stops a pending song from starting. Playback errors also offer **Try Again**. Scans show progress and the current filename. Failed refreshes preserve the existing library.

## Deliberate limits

One music folder at a time, with recursive album folders. No saved playlists, account, streaming, equalizer, ReplayGain, or promised gapless playback. Restored playback always waits for you to press Play. Library refresh is manual. Unsupported formats such as Ogg/Opus and DRM-protected files are not supported.

FLAC Vorbis comments and embedded pictures are parsed with bounded reads. MP3/M4A metadata uses AVFoundation. Untagged songs fall back to filenames and folder names. Album grouping uses folder, album title, and album artist; compilations work best with ALBUMARTIST tags. Separate CD/Disc subfolders with the same album tags are combined and ordered by disc then track. Malformed metadata may fall back to filenames rather than report an audio error.

The implementation and validation record lives in `docs/WORKLOG.md`.
