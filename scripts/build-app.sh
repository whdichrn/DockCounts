#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
build_flags=(-c "$configuration")
if [[ "${DOCKCOUNTS_UNIVERSAL:-0}" == "1" ]]; then
    build_flags+=(--arch arm64 --arch x86_64)
fi
swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"
app="dist/DockCounts.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/DockCounts" "$app/Contents/MacOS/DockCounts"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DockCounts</string>
<key>CFBundleIdentifier</key><string>io.github.whdichrn.DockCounts</string>
<key>CFBundleName</key><string>DockCounts</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier io.github.whdichrn.DockCounts "$app"
printf 'Built %s\n' "$PWD/$app"
