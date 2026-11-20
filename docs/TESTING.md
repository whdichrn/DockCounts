# 本机测试记录

日期：2026-11-21。测试机为 Apple Silicon，macOS 27.2.1（26B131），Xcode 27.2（27B52），Swift 6.4.2。

## 已验证

- `swift test`：9 项无需辅助功能权限的测试通过。另 3 项真实桌面集成测试在普通测试中显式跳过，避免误操作用户窗口。
- `DOCKCOUNTS_TEST_MENU=1 scripts/test-live.sh`：对一次性 fixture 应用执行 3 项真实桌面集成测试：
  1. 读取三个标准窗口，其中一个最小化；验证标题集合、`3·1` 计数、Dock 图标映射及当前点击命中。
  2. 调试程序从后台通过生产点击处理器显示原生菜单；从真实辅助功能树验证菜单只有应用标题和三个窗口，最小化窗口带状态文字。
  3. 调用菜单动作使用的同一窗口激活方法，验证 Beta 不再最小化、成为主窗口和焦点窗口，fixture 应用成为前台应用。
- 通过本机界面观察到 Beta 恢复后的窗口，确认结果；设置界面中的暂停、重新启用均正常更新状态。
- `DOCKCOUNTS_UNIVERSAL=1 scripts/build-app.sh`：构建 Apple Silicon 与 Intel 通用包；`lipo -info` 验证两种架构；`vtool -show-build` 验证两个架构的 `minos 15.0`；`codesign --verify --strict` 验证本地签名。
- Release 可执行文件不含调试菜单驱动入口。

## 点击处理测试覆盖

普通按下与松开被成对接管，并异步传递正确应用与菜单位置；Command / Control / Option / Shift 点击直接放行；零窗口应用、Dock 隐藏或被遮挡时不接管；移动不足 5 pt 保持点击候选，超过阈值后先交还原始按下事件，再放行拖动和松开；在图标外松开时交还原始事件序列。

这些测试创建内存中的 CGEvent 并直接调用生产事件处理函数，不向桌面注入鼠标输入。菜单集成驱动同样通过进程内回调触发，而不是伪装为物理鼠标测试。

## 尚需人工验收的范围

本机计算机操作工具不能直接定位并点击系统 Dock，也不能选择其外部弹出菜单，因此没有将“真实鼠标点击 Dock → 选菜单项”的完整物理输入链路标记为已自动化通过。事件处理、原生菜单内容和生产恢复方法分别通过了测试。

实体多显示器、全部 Dock 方向与放大动画组合、跨 Space / 全屏切换，以及不同第三方应用的完整窗口暴露情况，均不在本次实机覆盖范围内。多屏坐标换算和屏幕边界判断已有单元测试。本机系统不是 macOS 15，最低系统版本由包声明及两架构 Mach-O 记录证明；仓库 CI 在 macOS 15 runner 构建并运行无权限测试，CI 结果以 GitHub Actions 为准。

## 重现

```sh
swift test
DOCKCOUNTS_TEST_MENU=1 scripts/test-live.sh
DOCKCOUNTS_UNIVERSAL=1 scripts/build-app.sh
codesign --verify --strict dist/DockCounts.app
lipo -info dist/DockCounts.app/Contents/MacOS/DockCounts
xcrun vtool -show-build dist/DockCounts.app/Contents/MacOS/DockCounts
```

运行完整桌面集成测试前退出已有 DockCounts 实例，并确保终端 / 测试环境已获辅助功能权限。脚本在结束或失败后清理自身的测试进程与临时应用；菜单测试会将 `dist` 中的包构建为 debug，测试后重新运行 release 构建命令即可。
