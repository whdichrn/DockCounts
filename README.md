<p align="center">
  <img src="Sources/DockCounts/Resources/AppIcon.png" width="112" height="112" alt="DockCounts Icon">
</p>

<h1 align="center">DockCounts</h1>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  Upgrade your macOS Dock &amp; <code>⌘Tab</code> workflow: clean per-app window badges, click-to-pick window switcher, repeat-click minimize for active single windows, and automatic restore or reopen on <code>⌘Tab</code>.
</p>

<p align="center">
  <img src="assets/showcase.png" width="840" alt="DockCounts in Light and Dark macOS desktops showing Liquid Glass Dock badges and window picker">
</p>

---

## Why DockCounts

| Native macOS Friction | How DockCounts Helps |
| --- | --- |
| Minimized and stacked windows disappear behind a single Dock icon | **Clean count badges** (`1`, `3`, `3↓1`, `↓3`) always highlight minimized windows (`↓b`), while showing total count `a` via `Auto / Always / Hide` (`Auto` omits redundant `a` when all windows are minimized) |
| Clicking a multi-window Dock icon offers no quick picker; clicking the front single window does nothing | **Dock Click Enhancement** pops up a window menu (`1–9` shortcuts, hover minimize/close), minimizes a frontmost single window on repeat click, and lets you configure whether re-clicking an open menu triggers native Dock behavior or simply dismisses it |
| `⌘Tab` to an all-minimized or zero-window app updates only the menu bar | **`⌘Tab` Switch Enhancement** unminimizes single-window apps (or opens a centered picker / restores the latest window for multiple minimized windows) and triggers native Dock `reopen` for regular apps with zero windows |

## Features

- **Dock Click Enhancement**: Click any multi-window Dock icon (optionally including single-window apps) to open a crisp window list grouped by `Main → Open → Minimized`, supporting `1–9` / arrow keys, per-row hover minimize/close, and one-click `Show All`. Clicking a frontmost single window minimizes it immediately; a dedicated toggle controls whether re-clicking the same Dock icon while the menu is open triggers the native Dock action or dismisses the menu cleanly.
- **`⌘Tab` Switch Enhancement**: Automatically restores minimized windows when switching via `⌘Tab` (showing a centered picker or restoring the most recent window when multiple exist), and triggers a new window via Dock `AXPress` for regular apps with zero windows — guarded by `activeSpaceDidChange` and on-screen window checks to avoid false triggers across Spaces.
- **Clear `a↓b` Dock Badges**: Minimized count (`↓b`) always appears whenever minimized windows exist; total count `a` is independently configurable (`Auto` / `Always` / `Hide`), where `Auto` displays `a` whenever visible windows remain (`1`, `3`, `3↓1`) and trims to `↓b` when every window is minimized (`↓1`, `↓3`). Available across 4 native styles (`Liquid Glass`, `Soft Frosted`, `High Contrast`, `Accent Color`) and two sizes (`Compact`, `Standard`).
- **Unified Appearance & Live EN/ZH UI**: Switch appearance mode (`System / Light / Dark`) uniformly across Settings, badges, and the window picker, and switch between English and Simplified Chinese live without restarting.
- **Lightweight, Local-First & Manual Update Check**: Native `.menu` menu bar extra; the `CGEventTap` listener only runs fast local hit-testing and leaves right-clicks, modifier-clicks, and drags (> 5 pt) untouched. Zero screen capture, zero telemetry, and zero background requests — GitHub Releases is queried only when you click **Check for Updates**.

## Installation

1. Download `DockCounts-0.5.1-universal.zip` (Apple Silicon & Intel, macOS 15+) from [GitHub Releases](https://github.com/whdichrn/DockCounts/releases).
2. Extract and move `DockCounts.app` into `/Applications`, then launch it.
3. Grant Accessibility access under **System Settings → Privacy & Security → Accessibility**.
   > **Note**: Release archives are ad-hoc signed. If macOS prompts for Accessibility again after replacing an older release build, remove the old entry in Accessibility settings and re-enable `/Applications/DockCounts.app`. Local builds from source automatically sign with an installed development certificate so future updates keep permissions.
4. Optionally enable **Minimize windows into application icon** in **System Settings → Desktop & Dock**.

## Build & Test

Requirements: macOS 15+, Xcode 16 or newer (Swift 6 toolchain). Generating icons from `Artwork/*.svg` requires `librsvg` (`rsvg-convert`).

```sh
# 1. Run unit tests (no Accessibility permission needed)
swift test

# 2. Build native .app bundle
scripts/build-app.sh

# Or build Apple Silicon + Intel universal binary
DOCKCOUNTS_UNIVERSAL=1 scripts/build-app.sh

# 3. Regenerate icon and menu bar template assets from SVG (requires librsvg)
scripts/generate-icons.sh
```

Desktop integration tests requiring an active desktop session and Accessibility permissions (quit any running `DockCounts` instance first):

```sh
DOCKCOUNTS_TEST_MENU=1 scripts/test-live.sh
```

## Architecture & Privacy Boundaries

- Apple’s `NSDockTile` only allows an app to badge its own Dock icon; `DockCounts` renders mouse-transparent `NSPanel` overlays positioned from Accessibility Dock item coordinates.
- Window inventories are queried via macOS Accessibility APIs (`AXUIElement`); visibility across Spaces, full-screen, or custom app frameworks depends on what windows an app exposes over AX.
- `scripts/build-app.sh` prefers an installed `Developer ID Application`, `Apple Development`, or `DockCounts` certificate in your Keychain (override via `DOCKCOUNTS_SIGN_IDENTITY`, pass `-` to force ad-hoc) and automatically falls back to ad-hoc signing in CI.

## License

Released under the [MIT License](LICENSE).
