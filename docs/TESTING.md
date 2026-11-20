# 测试记录

日期：2026-11-21。测试机为 Apple Silicon，macOS 27.2.1（26B131），Xcode 27.2（27B52），Swift 6.4.2。

## 本机验证结果

- 基础测试：14 项通过，覆盖点击接管、修饰键与右键放行、拖动交还、屏幕坐标、隐藏 Dock、菜单键盘选择、空列表及菜单在屏幕边缘的布局。普通 `swift test` 将另外 5 项桌面测试显式跳过，避免操作用户窗口。
- 真实窗口集成：一次性 fixture 应用打开 Alpha、Beta、Gamma 三个标准窗口，并最小化 Beta；验证标题集合、窗口总数 3、最小化数 1、Dock 图标映射，以及角标覆盖区域的命中。
- 独立安装版界面：从正在运行的安装进程读取实际角标辅助功能标签，验证选择前为“共 3 个窗口，已最小化 1 个”，恢复后为“共 3 个窗口，已最小化 0 个”。
- 完整鼠标操作：原生输入点击 fixture 的 Dock 图标 → 出现 SwiftUI 窗口菜单 → 点击 Beta → 菜单关闭，Beta 恢复。随后断言 Beta 未最小化、是主窗口和焦点窗口、fixture 是前台应用，实际角标为 `3·0`。使用安装后的 release 包，未调用调试菜单驱动。
- 菜单内容：辅助功能树断言恰好三个窗口按钮，无其他应用操作；只有 Beta 带“已最小化”状态。
- 键盘与关闭：实际验证方向键选择、回车恢复、Esc 关闭和点击外部关闭。关闭监听覆盖辅助输入事件。
- 暂停与重新启用：通过设置界面验证状态更新。
- 打包：Apple Silicon + Intel 通用包，两个架构的 Mach-O 均为 `minos 15.0`，ad-hoc 签名检查通过，release 包不含调试菜单驱动。
- 仓库 CI 在 macOS 15 runner 执行基础测试、构建应用、检查签名和部署版本；当前结果以 GitHub Actions 为准。

## 环境与权限

已在系统设置中为固定安装路径的最终包授权辅助功能，独立启动正常运行。ad-hoc 签名在重新构建后会改变代码身份；如果设置里开关已开启，但应用仍报告未授权，应移除旧 DockCounts 记录，再添加当前安装路径的应用。

事件 tap 位于 annotated session 阶段，以覆盖常规鼠标及辅助输入。原生自动化工具可能保留 Command 修饰键，测试前先在一次空白区域的显式 Command 点击结束时释放该修饰键，随后发送普通点击。应用对修饰键点击保留系统行为。

## 重现基础与集成测试

```sh
swift test
scripts/test-live.sh
# 包括 SwiftUI 菜单内容（先退出已有 DockCounts）
DOCKCOUNTS_TEST_MENU=1 scripts/test-live.sh
DOCKCOUNTS_UNIVERSAL=1 scripts/build-app.sh
codesign --verify --strict dist/DockCounts.app
lipo -info dist/DockCounts.app/Contents/MacOS/DockCounts
xcrun vtool -show-build dist/DockCounts.app/Contents/MacOS/DockCounts
```

`test-live.sh` 创建并清理自己的测试应用，不读取或改动业务窗口。菜单测试会将 `dist` 构建为 debug；测试后重新构建 release 即可。进程内调试驱动创建内存中的 CGEvent 并调用生产回调，不向桌面发送鼠标输入，与下面的安装版输入验收区分。

## 重现安装版输入验收

先启动并授权已安装的 DockCounts，再启动交互 fixture：

```sh
DOCKCOUNTS_INTERACTIVE=1 scripts/test-live.sh
```

交互 fixture 额外显示一个普通层级的临时测试界面，便于定位 Dock 下方屏幕坐标。该界面标记为浮动窗口，不计入三个标准测试窗口。结束后 Ctrl-C 清理。

选择前运行：

```sh
DOCKCOUNTS_LIVE_TESTS=1 DOCKCOUNTS_E2E_EXPECT_MINIMIZED=1 swift test --filter 'testFixtureWindowInventoryAndDockMapping|testInstalledEndToEndWindowState'
```

实际点击 Dock 图标后运行：

```sh
DOCKCOUNTS_MENU_TEST=1 swift test --filter LiveMenuTests
```

通过菜单实际选择 Beta 后运行：

```sh
DOCKCOUNTS_E2E_EXPECT_MINIMIZED=0 DOCKCOUNTS_SELECTION_TEST=1 swift test --filter 'testInstalledEndToEndWindowState|testNativeWindowSelectionResult'
```

## 覆盖边界

实体多显示器、全部 Dock 方向与放大动画组合、跨 Space / 全屏切换，以及每个第三方应用的窗口暴露情况，未逐项实机覆盖。多屏坐标换算、左右下方菜单布局和屏幕边界已有基础测试。本机不是 macOS 15，macOS 15 上的构建与基础测试由 CI 验证；不将一次本机验收视为所有系统版本和应用的兼容性认证。
