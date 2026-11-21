<p align="center">
  <img src="Sources/DockCounts/Resources/AppIcon.png" width="112" height="112" alt="DockCounts Icon">
</p>

<h1 align="center">DockCounts</h1>

<p align="center">
  专注于 Dock 窗口计数与左键精准窗口选择的 macOS 菜单栏工具（SwiftUI / AppKit，支持 macOS 15+）。
</p>

---

## 核心特性

- **精准左键窗口菜单**：左键点击 Dock 图标时直接弹出窗口选择菜单，解决多个窗口（含最小化窗口）缩进图标时原生左键行为模糊的问题。默认仅在**多窗口**时弹菜单，也可切换为**含单窗口**。
- **前台单窗口点按即收起**：当单窗口应用处于前台且未最小化时，再次点击 Dock 图标直接将其最小化；再点即恢复，形成单手闭环（可在设置中单独开关）。
- **高效的窗口清单交互**：自动按「当前主窗口 → 展开窗口 → 已最小化」排序展示；支持数字键 `1–9` 与方向键快速选择、鼠标悬停行内直接最小化/恢复或关闭窗口，以及头部一键「展开全部」。
- **智能降噪 Dock 角标**：默认隐藏无干扰的单窗口正常状态；多窗口显示简洁圆角数字（如 `3`），含最小化窗口显示紧凑 `3↓1`。提供系统玻璃、柔和磨砂、高对比纯色、系统主题色四套精选风格及紧凑/标准两档尺寸。
- **原生菜单栏与轻量架构**：采用系统原生 `.menu` 菜单栏样式；`CGEventTap` 回调仅做本地几何与 WindowServer 层级判定，不阻塞桌面输入；右键、修饰键点击与拖动（> 5 pt）保留系统原样。无屏幕采集、无网络请求、无遥测。

## 下载与安装

1. 前往 [GitHub Releases](https://github.com/whdichrn/DockCounts/releases) 下载最新通用版压缩包 `DockCounts-0.5.0-universal.zip`（支持 Apple Silicon 与 Intel）。
2. 解压后将 `DockCounts.app` 拖入 `/Applications`（应用程序）目录并启动。
3. 在 **系统设置 → 隐私与安全性 → 辅助功能** 中允许 `DockCounts`。
   > **提示**：由于公开包使用 ad-hoc 签名，升级替换或重新构建后若系统仍提示未授权，请在辅助功能列表中移除旧记录后重新勾选当前 `/Applications/DockCounts.app`。
4. 可按需在 **系统设置 → 桌面与程序坞** 中开启「将窗口最小化至应用程序图标」。

## 构建与测试

环境要求：Xcode 16 或更新版本（Swift 6 工具链）。如需修改 SVG 后重新生成图标资源，请先安装 `librsvg`（`rsvg-convert`）。

```sh
# 1. 运行单元测试（无需桌面交互权限）
swift test

# 2. 构建本机架构 .app
scripts/build-app.sh

# 或构建 Apple Silicon + Intel 通用版本
DOCKCOUNTS_UNIVERSAL=1 scripts/build-app.sh

# 3. 从 Artwork/*.svg 重新生成图标与菜单栏 PDF 资源（需 librsvg）
scripts/generate-icons.sh
```

需要真实桌面会话与辅助功能权限的集成测试（运行前请先退出已有 `DockCounts`）：

```sh
DOCKCOUNTS_TEST_MENU=1 scripts/test-live.sh
```

## 实现与权限边界

- Apple 的 `NSDockTile` 仅适用于本应用自身图标，无法为其他应用写入角标；因此角标层使用忽略鼠标事件的透明 `NSPanel` 跟随辅助功能 API 暴露的 Dock 图标坐标。
- 窗口清单读取自系统辅助功能树（`AXUIElement`），对跨 Space、全屏或特殊框架应用的窗口可见性取决于应用自身公开的辅助功能信息。
- 本地构建与当前 release 包使用 ad-hoc 签名，未经过 Developer ID 公证。

## License

基于 [MIT License](LICENSE) 开源。
