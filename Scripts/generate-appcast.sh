#!/bin/bash
set -euo pipefail

# Generate a signed feed for the already-packaged app ZIP. Never publishes files.
app=${1:?Usage: generate-appcast.sh /path/to/kk.app /path/to/release-output /path/to/Sparkle/bin}
output=${2:?Usage: generate-appcast.sh /path/to/kk.app /path/to/release-output /path/to/Sparkle/bin}
tools=${3:?Usage: generate-appcast.sh /path/to/kk.app /path/to/release-output /path/to/Sparkle/bin}
account=dev.kw2.kk
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
public_key=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$app/Contents/Info.plist")
signing_public_key=$("$tools/generate_keys" --account "$account" -p)
if [[ -z "$public_key" || "$public_key" != "$signing_public_key" ]]; then
    echo "The app's SUPublicEDKey must match the dev.kw2.kk Sparkle key in Keychain." >&2
    exit 1
fi
archive="$output/kk-v$version-macos-arm64.app.zip"
[[ -f "$archive" ]] || { echo "Missing app ZIP: $archive" >&2; exit 1; }
stage=$(mktemp -d "${TMPDIR:-/tmp}/kk-appcast.XXXXXX")
trap 'rm -rf "$stage"' EXIT
# A feed with the current release is sufficient. Restrict input to one ZIP so
# generate_appcast cannot choose the duplicate DMG or modify older artifacts.
ditto "$archive" "$stage/$(basename "$archive")"
"$tools/generate_appcast" --account "$account" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/imapotatoes11/kk/releases/download/v$version/" \
    --link "https://github.com/imapotatoes11/kk/releases/tag/v$version" "$stage"
ditto "$stage/appcast.xml" "$output/appcast.xml"
echo "Generated $output/appcast.xml. Upload it alongside this release's ZIP and DMG."
