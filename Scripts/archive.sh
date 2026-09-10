#!/bin/bash
set -euo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
expected_xcode_build="${EXPECTED_XCODE_BUILD:-27A266a}"
actual_xcode_build="$(xcodebuild -version | awk '/Build version/ {print $3}')"
if [[ "$actual_xcode_build" != "$expected_xcode_build" ]]; then
    echo "Select Xcode 27 RC (27A266a), or explicitly set EXPECTED_XCODE_BUILD for a reviewed toolchain update." >&2
    exit 1
fi
platform="${1:-ios}"
case "$platform" in
    ios) destination='generic/platform=iOS' ;;
    *) echo "Unsupported platform: $platform" >&2; exit 2 ;;
esac
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit the reviewed source before making a release archive." >&2
    exit 1
fi
settings="$(xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Release -destination "$destination" -showBuildSettings)"
version="$(awk '/ MARKETING_VERSION = / {print $3; exit}' <<< "$settings")"
build="$(awk '/ CURRENT_PROJECT_VERSION = / {print $3; exit}' <<< "$settings")"
[[ -n "$version" && -n "$build" ]] || { echo 'Missing version/build metadata' >&2; exit 1; }
output=".build/releases/$version-$build-$platform"
[[ ! -e "$output" ]] || { echo "Already exists: $output" >&2; exit 1; }
mkdir -p "$output"
xcodebuild -project Oto.xcodeproj -scheme Oto -configuration Release \
    -destination "$destination" -derivedDataPath ".build/derived/$platform" \
    -archivePath "$output/Oto.xcarchive" -allowProvisioningUpdates archive
{
    git rev-parse HEAD
    xcodebuild -version
    echo "$platform $version ($build)"
} > "$output/source.txt"
echo "Archive: $output/Oto.xcarchive"
echo "Export configuration: Scripts/ExportOptions.plist"
echo "This command does not upload or publish."
