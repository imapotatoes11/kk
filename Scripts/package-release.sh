#!/bin/bash
set -euo pipefail

# Package a previously built Release app. GitHub assets must be files, so the
# standalone .app is transported in a ZIP that preserves the macOS bundle.
source_app=${1:?Usage: package-release.sh /path/to/kk.app /path/to/output}
output_dir=${2:?Usage: package-release.sh /path/to/kk.app /path/to/output}
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")
architecture=$(lipo -archs "$source_app/Contents/MacOS/kk")
if [[ "$architecture" != "arm64" ]]; then
    echo "Expected an arm64 release, got: $architecture" >&2
    exit 1
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
ditto "$source_app" "$output_dir/kk.app"
# Ad-hoc apps have no Team ID to match Sparkle's framework signature. Keep the
# hardened runtime, but permit the bundled framework to load. Developer ID
# distribution should instead sign all nested code with the same Team ID.
script_dir=$(cd "$(dirname "$0")" && pwd)
codesign --force --deep --options runtime --entitlements "$script_dir/adhoc.entitlements" --sign - "$output_dir/kk.app"
codesign --verify --deep --strict "$output_dir/kk.app"

ditto -c -k --sequesterRsrc --keepParent "$output_dir/kk.app" "$output_dir/kk-v$version-macos-arm64.app.zip"
stage=$(mktemp -d "${TMPDIR:-/tmp}/kk-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$output_dir/kk.app" "$stage/kk.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "kk $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$output_dir/kk-v$version-macos-arm64.dmg"
(
    cd "$output_dir"
    shasum -a 256 "kk-v$version-macos-arm64.app.zip" "kk-v$version-macos-arm64.dmg" > SHA256SUMS.txt
)
