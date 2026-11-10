#!/bin/bash
set -euo pipefail

# Re-export after editing AppIcon.icon in Icon Composer. Ship explicit variants:
# macOS's global icon style can differ from its window appearance.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
resources="$repo_root/Sources/kk/Resources"
composer="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"
for rendition in Default Dark; do
    name=Light
    [[ "$rendition" == Dark ]] && name=Dark
    "$composer" "$resources/AppIcon.icon" --export-image \
        --output-file "$resources/AppIcon$name.png" --platform macOS \
        --rendition "$rendition" --width 512 --height 512 --scale 2
done

# Finder uses the dark icon before the app has ever launched. Runtime selection
# changes About and the Dock without writing into the signed application bundle.
stage=$(mktemp -d "${TMPDIR:-/tmp}/kk-icons.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$resources/AppIconDark.png" --out "$stage/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$resources/AppIconDark.png" --out "$stage/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/AppIcon.iconset" -o "$resources/AppIconDark.icns"
