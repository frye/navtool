#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# The shared source remains full-bleed for window, Windows, and Linux icons.
source_svg="$REPO_ROOT/src/Navtool.App/Assets/Navtool.svg"
# This derived master records the macOS-only safe-area treatment.
master_png="$REPO_ROOT/branding/macos/Navtool-1024.png"
target_icns="$REPO_ROOT/src/Navtool.App/Assets/Navtool.icns"

for tool in sips iconutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required macOS icon tool is unavailable: $tool" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/Navtool.iconset"
macos_svg="$work_dir/Navtool.svg"
rendered_master="$work_dir/Navtool-1024.png"
rendered_icns="$work_dir/Navtool.icns"
mkdir -p "$iconset"
mkdir -p "$(dirname "$master_png")"

sed \
  -e '1s#>$#><g transform="translate(100 100) scale(0.8046875)">#' \
  -e '$s#</svg>#</g></svg>#' \
  "$source_svg" > "$macos_svg"
if ! grep -q '<g transform="translate(100 100) scale(0.8046875)">' "$macos_svg"; then
  echo "Could not apply the macOS safe-area transform to $source_svg" >&2
  exit 1
fi

sips -s format png "$macos_svg" --out "$rendered_master" >/dev/null
width="$(sips -g pixelWidth "$rendered_master" | awk '/pixelWidth:/ { print $2 }')"
height="$(sips -g pixelHeight "$rendered_master" | awk '/pixelHeight:/ { print $2 }')"
if [[ "$width" != "1024" || "$height" != "1024" ]]; then
  echo "Expected a 1024x1024 macOS master, got ${width}x${height}" >&2
  exit 1
fi

while read -r size filename; do
  sips -z "$size" "$size" "$rendered_master" --out "$iconset/$filename" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

iconutil -c icns "$iconset" -o "$rendered_icns"
cp "$rendered_master" "$master_png"
cp "$rendered_icns" "$target_icns"
