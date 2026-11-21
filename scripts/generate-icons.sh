#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { printf 'Install librsvg to render the editable SVG artwork.\n' >&2; exit 1; }
icon_dir="$(mktemp -d /tmp/DockCountsIcon.XXXXXX)"
mkdir -p "$icon_dir/DockCounts.iconset" Sources/DockCounts/Resources
for side in 16 32 128 256 512; do
    rsvg-convert -w "$side" -h "$side" Artwork/AppIcon.svg -o "$icon_dir/DockCounts.iconset/icon_${side}x${side}.png"
    rsvg-convert -w "$((side*2))" -h "$((side*2))" Artwork/AppIcon.svg -o "$icon_dir/DockCounts.iconset/icon_${side}x${side}@2x.png"
done
iconutil -c icns "$icon_dir/DockCounts.iconset" -o Sources/DockCounts/Resources/DockCounts.icns
cp "$icon_dir/DockCounts.iconset/icon_512x512@2x.png" Sources/DockCounts/Resources/AppIcon.png
rsvg-convert -f pdf Artwork/MenuBarTemplate.svg -o Sources/DockCounts/Resources/MenuBarTemplate.pdf
printf 'Generated AppIcon.png, DockCounts.icns and MenuBarTemplate.pdf\n'
