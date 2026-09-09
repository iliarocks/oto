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

1. Tap **Choose Music Folder**, navigate to your folder in Files, and tap **Open**.
2. Open an album, then tap **Play** or an individual song. Playback continues in album order and stops after the final song.
3. Tap the floating player for seeking, previous/next, and AirPlay. Swipe down to dismiss Now Playing. Previous restarts the song after three seconds; otherwise it moves back one track. Skipping while paused stays paused.
4. After changing the contents of your folder, pull to refresh or use **Settings → Refresh**. A notice in the library links to any files that couldn't be read. **Settings**, opened from the gear at the top left, shows the selected folder; tap its **Folder** row to choose another. Its About section links to Privacy and Support.

The toolbar shows your album and song count. Browsing stays focused on albums, without search. The compact player uses native Liquid Glass on iOS 26 and later, with a material capsule on older supported versions.

Long titles and artist names stay on one line and scroll horizontally in both players. Short text stays still. Now Playing fits its controls on screen, with artwork adapting to the available space; swipe down to dismiss it. Text motion respects Reduce Motion, and VoiceOver reads the full label.

iCloud Drive files must be downloaded before Oto can scan or play them. Use **Keep Downloaded** on the folder in Files, wait for it to finish, then refresh Oto. Oto does not maintain a second copy of your audio. Both players keep the artist and play/pause control visible while songs open. Pause also stops a pending song from starting. Playback errors also offer **Try Again**. Scans show the current filename and can be cancelled without replacing the existing library. Cancellation stops waiting for coordinated access, though a file read that has already started may need to finish.

## Deliberate limits

One music folder at a time, with recursive album folders. No playlists, queue editing, shuffle/repeat modes, account, streaming, equalizer, ReplayGain, or promised gapless playback. The library persists, but the current playback session does not resume after force-quitting the app. Library refresh is manual. Unsupported formats such as Ogg/Opus and DRM-protected files are not supported.

FLAC Vorbis comments and embedded pictures are parsed with bounded reads. MP3/M4A metadata uses AVFoundation. Untagged songs fall back to filenames and folder names. Album grouping uses folder, album title, and album artist; compilations work best with ALBUMARTIST tags. Separate CD/Disc subfolders with the same album tags are combined and ordered by disc then track. Malformed metadata may fall back to filenames rather than report an audio error.

The implementation and validation record lives in `docs/WORKLOG.md`.
