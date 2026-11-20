#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${DOCKCOUNTS_TEST_MENU:-0}" == "1" ]] && pgrep -x DockCounts >/dev/null; then
    printf 'Quit DockCounts before running the menu integration test.\n' >&2
    exit 1
fi
fixture_dir="$(mktemp -d /tmp/DockCountsLive.XXXXXX)"
fixture_app="$fixture_dir/DockCountsFixture.app"
mkdir -p "$fixture_app/Contents/MacOS"
swiftc scripts/fixtures/WindowFixture.swift -o "$fixture_app/Contents/MacOS/DockCountsFixture"
cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DockCountsFixture</string>
<key>CFBundleIdentifier</key><string>io.github.whdichrn.DockCountsFixture</string>
<key>CFBundleName</key><string>DockCountsFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$fixture_app"
"$fixture_app/Contents/MacOS/DockCountsFixture" &
fixture_pid=$!
test_app_pid=""
cleanup() {
    if [[ -n "$test_app_pid" ]]; then kill "$test_app_pid" 2>/dev/null || true; fi
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
    rm -rf "$fixture_dir"
}
trap cleanup EXIT
sleep 2
DOCKCOUNTS_LIVE_TESTS=1 swift test --filter LiveAccessibilityTests/testFixtureWindowInventoryAndDockMapping
if [[ "${DOCKCOUNTS_TEST_MENU:-0}" == "1" ]]; then
    scripts/build-app.sh debug
    dist/DockCounts.app/Contents/MacOS/DockCounts --smoke-menu io.github.whdichrn.DockCountsFixture &
    test_app_pid=$!
    sleep 1
    DOCKCOUNTS_LIVE_TESTS=1 swift test --filter LiveAccessibilityTests/testFixtureWindowInventoryAndDockMapping
    sleep 8
    DOCKCOUNTS_MENU_TEST=1 swift test --filter LiveMenuTests
    kill "$test_app_pid"
    wait "$test_app_pid" 2>/dev/null || true
    test_app_pid=""
fi
DOCKCOUNTS_RESTORE_TEST=1 swift test --filter LiveAccessibilityTests/testRestoreMinimizedFixtureWindow
