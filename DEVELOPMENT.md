# Development

Use **Xcode 27 RC, build 27A266a**. Select it in Xcode's Locations settings or
with `sudo xcode-select --switch /Applications/Xcode.app`. Run Xcode's first-launch
setup and install the iOS 27 simulator runtime. The scripts report a toolchain
mismatch; set `EXPECTED_XCODE_BUILD` only when intentionally checking another
reviewed Xcode version.

## Builds and tests

Run commands from this repository:

```sh
Scripts/check.sh ios unit
Scripts/check.sh ios all
TEST_DESTINATION='generic/platform=iOS' Scripts/check.sh ios build
```

The second argument accepts `unit`, `ui`, `all`, or `build`. iOS tests default to
an iPhone 17 simulator. Set `TEST_DESTINATION` to a complete Xcode destination
(e.g. `platform=iOS Simulator,id=...`) when selecting a particular device/runtime.
Run UI tests with the desktop available for automation. Stop a run if an Apple
simulator service repeatedly crashes; do not hide global crash reports.

Build output lives in `.build/derived/<platform>`, and the latest result for each
suite lives in `.build/results`. Both are disposable and ignored by Git.

## Development data

Debug builds use `ilia.page.oto.dev` and display **Oto Dev**. Release builds keep
`ilia.page.oto`. The two installations have separate app containers. Choose the
music folder once in the development app; production bookmarks and playback state
are not copied into it.

UI tests use a separate library directory. `OtoBasicUITests` runs on a simulator
or physical iPhone. The music-screen suite shares synthetic files with the app;
iOS sandboxing restricts it to simulators, so it explicitly skips on physical
devices. Unit tests run on either destination with temporary, isolated data.

To use a connected iPhone, set `TEST_DESTINATION='platform=iOS,id=<device-UDID>'`.
The `all` command runs the unit suite and basic UI checks there. Test the real
music folder and playback manually on the phone as well.

## Local release archives

Commit the reviewed source, then run:

```sh
Scripts/archive.sh ios
```

Archives live in `.build/releases/<version>-<build>-<platform>/Oto.xcarchive`.
Each has a `source.txt` recording its commit and Xcode build. The script refuses
a dirty checkout or an existing archive path. `Scripts/ExportOptions.plist` holds
the App Store export settings. Archiving does not upload, submit or publish.

Keep each submitted archive and its dSYMs while it is needed for debugging.
Unlike source, these ignored files cannot be recovered from Git. Remove obsolete
DerivedData, test output and superseded local experiments instead of keeping
ad-hoc backup directories.

## Before publishing

- Run unit/UI checks on iOS 27 and the oldest supported major version, iOS 18.
- Test the user's music folder, refresh/cancellation, queue/repeat, seeking, background playback, interruptions and relaunch restoration.
- Validate the signed archive and bundled privacy manifest; upload only after approval, then confirm processing and the selected App Store build.

The public website lives in `docs`; maintained repository documentation belongs
outside that folder. Raw screenshots and final designs remain separate under
`screenshots`, as described in its README.
