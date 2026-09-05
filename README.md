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

Open `Oto.xcodeproj` in Xcode. Select the Oto scheme and an iPhone simulator. Device builds need a development signing team.

The implementation and validation record lives in `docs/WORKLOG.md`.

