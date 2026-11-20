# DockCounts

一个专注于 Dock 窗口计数与选择的 macOS 菜单栏辅助程序。SwiftUI 界面，支持 macOS 15 及以上。

- 在正在运行的应用 Dock 图标上显示 `窗口总数 · 已最小化数`，例如 `5·2` 表示共 5 个窗口，其中 2 个已最小化。
- 普通左键点击有窗口的应用图标，显示只含该应用窗口标题、最小化状态的菜单；选择即可恢复、切换到该窗口。
- 右键、Command / Control / Option / Shift 点击、零窗口应用保留系统行为。拖动超过 5 pt 后将原始按下事件交回 Dock，继续原生拖动。
- 仅在系统开启“将窗口最小化至应用程序图标”时工作；关闭该选项或暂停程序后，移除角标并停止点击接管。
- 没有窗口预览、截图采集、网络请求、遥测或额外窗口管理功能。

## 使用

1. 将构建好的 `DockCounts.app` 放到固定位置（例如 `~/Applications`）后启动。
2. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 DockCounts。首次启动的设置窗口提供入口。授权后若仍无法接管点击，退出并重新启动。
3. 在“系统设置 → 桌面与程序坞”开启“将窗口最小化至应用程序图标”。
4. 从菜单栏的叠放窗口图标可暂停、打开设置或退出。

角标第一项是总数（包含已最小化窗口）；第二项用黄色显示最小化数。不支持辅助功能的应用不显示推测的计数，保留原有点击行为。隐藏应用的窗口仍计入总数，窗口最小化与应用隐藏分别处理。

## 构建与测试

需要 Xcode 16 或更新版本（Swift 6 工具链）。可直接用 Xcode 打开 `Package.swift` 查看、编辑和运行。

```sh
swift test
scripts/build-app.sh
open dist/DockCounts.app
```

默认构建本机架构。可构建 Apple Silicon + Intel 通用版本：

```sh
DOCKCOUNTS_UNIVERSAL=1 scripts/build-app.sh
```

需要桌面会话和测试运行环境的辅助功能权限的真实窗口集成测试：

```sh
scripts/test-live.sh
# 包括原生菜单内容的完整桌面集成测试（先退出已有 DockCounts）
DOCKCOUNTS_TEST_MENU=1 scripts/test-live.sh
```

该脚本创建一个一次性应用，打开三个已命名窗口并最小化其中一个，验证真实窗口总数、最小化数、Dock 图标匹配，以及恢复窗口后的最小化、主窗口和前台应用状态。结束时退出并清理测试应用。请不要同时运行第二个测试 fixture。

调试包还提供 `--settings --smoke-menu io.github.whdichrn.DockCountsFixture` 的进程内回调测试入口：8 秒后，用真实 Dock 命中测试调用点击处理器并显示窗口菜单，不向桌面发送合成鼠标输入。菜单显示后可运行 `DOCKCOUNTS_MENU_TEST=1 swift test --filter LiveMenuTests` 检查实际菜单。该入口不编入 release 包。详细测试边界见 [测试记录](docs/TESTING.md)。

## 实现边界

Apple 的 `NSDockTile` 用于本应用图标，不能为其他应用直接设置角标。因此本程序使用不接收鼠标事件的透明面板，跟随辅助功能 API 暴露的 Dock 图标位置，不修改 Dock 进程或其他应用。

窗口清单来自应用公开的辅助功能树，统计标准窗口和对话框，不将标签页、浮动面板或独立 sheet 当作额外窗口。某些应用只暴露部分窗口，或在其他 Space / 全屏环境下提供不完整信息，计数以应用实际提供的信息为准。

位置与窗口状态约每 350 ms 轮询一次，慢应用使用有超时的串行后台读取。点击时重新命中实际图标，避免依赖放大动画期间的旧坐标。Dock 隐藏或被全屏应用遮住时，隐藏角标。多屏坐标转换有单元测试；实体多显示器、所有 Dock 方向、快速放大动画、跨 Space 和所有第三方应用的兼容性仍需逐项人工验证。

本地包使用 ad-hoc 签名，没有 Developer ID 公证。更换路径或重新签名后，系统可能要求重新授权辅助功能。源代码声明的最低系统版本和构建包均为 macOS 15；本机真实窗口测试系统见测试记录，不能将其视为所有 macOS 15+ 版本的实机兼容认证。

参考：[NSDockTile](https://developer.apple.com/documentation/appkit/nsdocktile)、[AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)、[CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)。
