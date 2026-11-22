#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
version="$(cat VERSION)"
build_number="${DOCKCOUNTS_BUILD_NUMBER:-8}"
build_flags=(-c "$configuration")
if [[ "${DOCKCOUNTS_UNIVERSAL:-0}" == "1" ]]; then
    build_flags+=(--arch arm64 --arch x86_64)
fi
swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"
app="dist/DockCounts.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Sources/DockCounts/Resources/* "$app/Contents/Resources/"
cp "$bin_dir/DockCounts" "$app/Contents/MacOS/DockCounts"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DockCounts</string>
<key>CFBundleIdentifier</key><string>io.github.whdichrn.DockCounts</string>
<key>CFBundleName</key><string>DockCounts</string>
<key>CFBundleIconFile</key><string>DockCounts</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
resolve_sign_identity() {
    if [[ -n "${DOCKCOUNTS_SIGN_IDENTITY:-}" ]]; then
        printf '%s' "$DOCKCOUNTS_SIGN_IDENTITY"
        return
    fi
    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    local pattern hash
    for pattern in "Developer ID Application:" "Apple Development:" "DockCounts"; do
        hash="$(printf '%s\n' "$identities" | grep -F "$pattern" | head -n 1 | awk '{print $2}' || true)"
        if [[ -n "$hash" ]]; then
            printf '%s' "$hash"
            return
        fi
    done
    printf '%s' "-"
}

sign_identity="$(resolve_sign_identity)"
if [[ "$sign_identity" == "-" ]]; then
    codesign --force --sign - --identifier io.github.whdichrn.DockCounts "$app"
else
    codesign --force --deep --sign "$sign_identity" "$app"
fi
printf 'Built %s (signed with %s)\n' "$PWD/$app" "$sign_identity"
