#!/bin/bash
set -euo pipefail

# Render real kk views against fictional screen content and local SSE fixtures.
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
output_dir="$repo_dir/docs/screenshots"
build_dir=${KK_PREVIEW_BUILD_PATH:-"$repo_dir/DerivedData/DocumentationPreviewBuild"}
mkdir -p "$repo_dir/DerivedData" "$output_dir"
export CLANG_MODULE_CACHE_PATH="$repo_dir/DerivedData/DocumentationPreviewModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
package_dir=$(mktemp -d "$repo_dir/DerivedData/preview-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
cp "$repo_dir/Package.swift" "$repo_dir/Package.resolved" "$package_dir/"
cp -R "$repo_dir/Sources" "$package_dir/"
mkdir -p "$package_dir/Tests/kkTests"
cp "$repo_dir/docs/previews/PreviewTests.swift" "$package_dir/Tests/kkTests/"
KK_PREVIEW_DIR="$output_dir" KK_PROBLEM_SET_PDF="$repo_dir/docs/previews/problem-set.pdf" swift test --package-path "$package_dir" \
  --scratch-path "$build_dir" --cache-path "$repo_dir/DerivedData/DocumentationPreviewCache" \
  --disable-sandbox --filter DocumentationPreviewTests

if command -v ffmpeg >/dev/null 2>&1; then
  render_gif() {
    local name=$1
    shift
    local frame_dir="$package_dir/$name"
    local index=0
    mkdir -p "$frame_dir"
    for scene in "$@"; do
      cp "$output_dir/$scene.png" "$frame_dir/$(printf '%02d' "$index").png"
      index=$((index + 1))
    done
    ffmpeg -hide_banner -loglevel error -y -framerate 1/2 -i "$frame_dir/%02d.png" \
      -vf 'scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse=dither=sierra2_4a' \
      -loop 0 -final_delay 200 "$output_dir/$name.gif"
  }
  render_gif workflow annotate screen-context follow-up
  render_gif math-workflow math-annotate math-context math-reannotate math-follow-up
else
  echo "Rendered PNGs. Install ffmpeg to regenerate the workflow GIFs." >&2
fi
