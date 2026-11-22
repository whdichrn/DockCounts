import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var confirmReset = false

    var body: some View {
        let lang = controller.preferences.language
        VStack(spacing: 0) {
            tabBar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                switch controller.settingsTab {
                case .general: generalTab
                case .enhancement: enhancementTab
                case .appearance: appearanceTab
                case .about: aboutTab
                }
                if controller.settingsTab != .about {
                    HStack {
                        Text(L10n.t("更改即时生效并保存", "Changes take effect immediately", lang))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t("还原默认设置…", "Reset Defaults…", lang)) { confirmReset = true }
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 4)
                }
            }
            .padding(14)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            L10n.t("恢复默认功能与外观设置？", "Reset all settings to defaults?", lang),
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button(L10n.t("恢复默认设置", "Reset Defaults", lang)) { controller.restoreDefaults() }
            Button(L10n.t("取消", "Cancel", lang), role: .cancel) {}
        } message: {
            Text(L10n.t("开机启动由系统登录项单独管理，不会随此操作改变。", "Login item status is managed by macOS and will not change.", lang))
        }
        .onChange(of: controller.settingsTab) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.trusted) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.minimizeToApplication) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.login.state) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.windowSelectionEnabled) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.minimizeActiveSingleWindow) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.secondClickRunsNativeAction) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.cmdTabRestoreMinimized) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.cmdTabReopenEmptyApp) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.badgesEnabled) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.language) { _, _ in scheduleResize(animated: true) }
    }

    private func scheduleResize(animated: Bool) {
        DispatchQueue.main.async {
            controller.resizeSettingsWindow(animated: animated)
        }
    }

    private var tabBar: some View {
        let lang = controller.preferences.language
        return HStack(spacing: 6) {
            tabButton(.general, title: L10n.t("通用", "General", lang), symbol: "gearshape")
            tabButton(.enhancement, title: L10n.t("增强", "Enhancement", lang), symbol: "sparkles")
            tabButton(.appearance, title: L10n.t("外观", "Appearance", lang), symbol: "circle.lefthalf.filled")
            tabButton(.about, title: L10n.t("关于", "About", lang), symbol: "info.circle")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabButton(_ tab: SettingsTab, title: String, symbol: String) -> some View {
        let selected = controller.settingsTab == tab
        return Button {
            controller.settingsTab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }

    private var generalTab: some View {
        let lang = controller.preferences.language
        let resolved = lang.resolve()
        return VStack(alignment: .leading, spacing: 11) {
            SettingsCard {
                HStack(spacing: 12) {
                    Image(nsImage: AppArtwork.appIcon)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DockCounts")
                            .font(.system(size: 14.5, weight: .bold))
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                            Text(controller.message)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $controller.preferences.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("master-enabled")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            SettingsCard(title: L10n.t("启动与系统状态", "Startup & System", lang)) {
                SettingsRow {
                    Text(L10n.t("界面语言", "Language", lang))
                    Spacer()
                    Picker(L10n.t("界面语言", "Language", lang), selection: $controller.preferences.language) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(item.title(in: resolved)).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 236)
                    .accessibilityIdentifier("app-language")
                }
                SettingsDivider()
                LoginItemRow(login: controller.login, language: lang)
                SettingsDivider()
                SettingsRow {
                    Label(
                        controller.trusted
                            ? L10n.t("辅助功能已授权", "Accessibility permission granted", lang)
                            : L10n.t("需要辅助功能权限", "Accessibility permission required", lang),
                        systemImage: controller.trusted ? "checkmark.circle.fill" : "lock.circle.fill"
                    )
                    .foregroundStyle(controller.trusted ? Color.primary : Color.orange)
                    Spacer()
                    if !controller.trusted {
                        Button(L10n.t("授权辅助功能…", "Grant Access…", lang), action: controller.requestPermission)
                    }
                }
                SettingsDivider()
                SettingsRow {
                    Label(
                        controller.minimizeToApplication
                            ? L10n.t("已开启“将窗口最小化至应用程序图标”", "“Minimize windows into application icon” is on", lang)
                            : L10n.t("建议开启“将窗口最小化至应用程序图标”", "Enable “Minimize windows into application icon”", lang),
                        systemImage: controller.minimizeToApplication ? "checkmark.circle.fill" : "info.circle"
                    )
                    .foregroundStyle(controller.minimizeToApplication ? Color.primary : Color.secondary)
                    Spacer()
                    if !controller.minimizeToApplication {
                        Button(L10n.t("前往设置", "Open Settings", lang)) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                        }
                    }
                }
            }
        }
    }

    private var enhancementTab: some View {
        let lang = controller.preferences.language
        let clickSummary = controller.preferences.triggerMode.summary(in: lang)
            + (controller.preferences.minimizeActiveSingleWindow
                ? L10n.t(" 前台单窗口再次点按直接最小化。", " Clicking a frontmost single window minimizes it.", lang)
                : "")
            + (controller.preferences.secondClickRunsNativeAction
                ? L10n.t(" 菜单已开时再点同一图标执行原生行为。", " Re-clicking while open runs native Dock.", lang)
                : L10n.t(" 菜单已开时再点同一图标仅关闭菜单。", " Re-clicking while open only dismisses the menu.", lang))

        return VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: L10n.t("Dock 点按增强", "Dock Click Enhancement", lang)) {
                SettingsRow {
                    Text(L10n.t("点按图标选择窗口", "Click Dock icon to pick window", lang))
                    Spacer()
                    Toggle("", isOn: $controller.preferences.windowSelectionEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("window-selection-enabled")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("触发条件", "Trigger condition", lang))
                    Spacer()
                    Picker(L10n.t("触发条件", "Trigger condition", lang), selection: $controller.preferences.triggerMode) {
                        ForEach(WindowTriggerMode.allCases) { mode in
                            Text(mode.title(in: lang)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .disabled(!controller.preferences.windowSelectionEnabled)
                    .accessibilityIdentifier("window-trigger-mode")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("前台单窗口再次点按时直接最小化", "Click active single window to minimize", lang))
                    Spacer()
                    Toggle("", isOn: $controller.preferences.minimizeActiveSingleWindow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!controller.preferences.windowSelectionEnabled)
                        .accessibilityIdentifier("minimize-active-single-window")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("菜单已开时再次点按执行原生行为", "Repeat click while open runs native Dock", lang))
                    Spacer()
                    Toggle("", isOn: $controller.preferences.secondClickRunsNativeAction)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!controller.preferences.windowSelectionEnabled)
                        .accessibilityIdentifier("second-click-native-action")
                }
                SettingsDivider()
                Text(clickSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }

            SettingsCard(title: L10n.t("⌘Tab 切换增强", "⌘Tab Switch Enhancement", lang)) {
                SettingsRow {
                    Text(L10n.t("全部最小化时自动处理", "Handle when all windows are minimized", lang))
                    Spacer()
                    Toggle("", isOn: $controller.preferences.cmdTabRestoreMinimized)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("cmdtab-restore-minimized")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("多个最小化窗口", "Multiple minimized windows", lang))
                    Spacer()
                    Picker(L10n.t("多个最小化窗口", "Multiple minimized windows", lang), selection: $controller.preferences.cmdTabMultiMinimizedBehavior) {
                        ForEach(CmdTabMultiMinimizedBehavior.allCases) { behavior in
                            Text(behavior.title(in: lang)).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 236)
                    .disabled(!controller.preferences.cmdTabRestoreMinimized)
                    .accessibilityIdentifier("cmdtab-multi-behavior")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("零窗口应用自动新建窗口", "Reopen apps with zero windows", lang))
                    Spacer()
                    Toggle("", isOn: $controller.preferences.cmdTabReopenEmptyApp)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("cmdtab-reopen-empty")
                }
                SettingsDivider()
                Text(L10n.t("仅在通过 ⌘Tab 切换且确认应用在其他空间无可见窗口时触发。", "Triggers only after ⌘Tab when the app has no on-screen windows in any Space.", lang))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
        }
    }

    private var appearanceTab: some View {
        let lang = controller.preferences.language
        return VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: L10n.t("整体外观", "App Appearance", lang)) {
                SettingsRow {
                    Text(L10n.t("外观模式", "Appearance Mode", lang))
                    Spacer()
                    Picker(L10n.t("外观模式", "Appearance Mode", lang), selection: $controller.preferences.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title(in: lang)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 222)
                    .accessibilityIdentifier("app-appearance-mode")
                }
                SettingsDivider()
                Text(L10n.t("统一作用于程序坞角标、窗口选择菜单与设置窗口。", "Applies to Dock badges, window picker, and Settings.", lang))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }

            SettingsCard(title: L10n.t("Dock 角标", "Dock Badges", lang)) {
                SettingsRow {
                    Text(L10n.t("显示 Dock 窗口角标", "Show Dock window badges", lang))
                    Spacer()
                    Toggle("", isOn: $controller.preferences.badgesEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("badges-enabled")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("显示时机", "Visibility", lang))
                    Spacer()
                    Picker(L10n.t("显示时机", "Visibility", lang), selection: $controller.preferences.badgeVisibility) {
                        ForEach(BadgeVisibilityMode.allCases) { mode in
                            Text(mode.title(in: lang)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 246)
                    .disabled(!controller.preferences.badgesEnabled)
                    .accessibilityIdentifier("badge-visibility")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("角标风格", "Badge Style", lang))
                    Spacer()
                    Picker(L10n.t("角标风格", "Badge Style", lang), selection: $controller.preferences.appearance.preset) {
                        ForEach(BadgePreset.allCases) { preset in
                            Text(preset.title(in: lang)).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 148)
                    .disabled(!controller.preferences.badgesEnabled)
                    .accessibilityIdentifier("badge-preset")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("角标尺寸", "Badge Size", lang))
                    Spacer()
                    Picker(L10n.t("角标尺寸", "Badge Size", lang), selection: $controller.preferences.appearance.size) {
                        ForEach(BadgeSize.allCases) { size in
                            Text(size.title(in: lang)).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 152)
                    .disabled(!controller.preferences.badgesEnabled)
                    .accessibilityIdentifier("badge-size")
                }
                SettingsDivider()
                SettingsRow {
                    Text(L10n.t("背景不透明度", "Opacity", lang))
                    Spacer(minLength: 16)
                    Slider(value: $controller.preferences.appearance.opacity, in: 0.4...1.0)
                        .frame(width: 170)
                        .disabled(!controller.preferences.badgesEnabled)
                        .accessibilityIdentifier("badge-opacity")
                    Text(controller.preferences.appearance.opacity.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var aboutTab: some View {
        let lang = controller.preferences.language
        return VStack(spacing: 12) {
            Image(nsImage: AppArtwork.appIcon)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("DockCounts")
                    .font(.system(size: 20, weight: .bold))
                Text(L10n.t("版本 \(ProjectLinks.version)", "Version \(ProjectLinks.version)", lang))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .accessibilityIdentifier("app-version")
            }

            Text(L10n.t("在 Dock 上看清窗口数量，点按精准选择与恢复窗口。", "See Dock window counts clearly and switch windows cleanly.", lang))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link(L10n.t("项目主页", "Homepage", lang), destination: ProjectLinks.home)
                    .accessibilityIdentifier("project-home")
                Link(L10n.t("版本与下载", "Releases", lang), destination: ProjectLinks.releases)
            }
            .padding(.top, 2)

            UpdateCheckSection(updater: controller.updater, language: lang) {
                scheduleResize(animated: true)
            }

            Divider()
                .frame(width: 280)
                .padding(.vertical, 4)

            Text(
                L10n.t(
                    "窗口清单读取自系统辅助功能接口，不采集屏幕图像。\n不后台联网或收集遥测，仅在点击“检查更新”时查询 GitHub Releases。\nmacOS 26+ 使用原生玻璃材质，macOS 15 使用系统磨砂兼容层。",
                    "Window lists are read via macOS Accessibility APIs with zero screen capture.\nNo background requests or telemetry; GitHub Releases is queried only when checking for updates.\nUses native glass on macOS 26+ and system vibrancy on macOS 15.",
                    lang
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        if !controller.preferences.enabled || !controller.preferences.needsDock { return .secondary }
        if !controller.trusted { return .orange }
        if controller.preferences.windowSelectionEnabled && !controller.intercepting { return .red }
        return .green
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.75)
            )
        }
    }
}

private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 10) {
            content()
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}

private struct UpdateCheckSection: View {
    @ObservedObject var updater: UpdateChecker
    let language: AppLanguage
    let onStateChange: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(L10n.t("检查更新", "Check for Updates", language)) {
                Task { await updater.check() }
            }
            .disabled(updater.state == .checking)
            .accessibilityIdentifier("check-for-updates")

            switch updater.state {
            case .idle:
                EmptyView()
            case .checking:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("正在检查更新…", "Checking for updates…", language))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            case .upToDate(let current):
                Text(L10n.t("已是最新版本（\(current)）", "You’re up to date (\(current))", language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            case .available(let version, let url):
                HStack(spacing: 8) {
                    Text(L10n.t("发现新版本 v\(version)", "Update available: v\(version)", language))
                        .foregroundStyle(.primary)
                    Link(L10n.t("前往下载", "Download", language), destination: url)
                }
                .font(.system(size: 11.5, weight: .medium))
            case .failed:
                Text(L10n.t("无法检查更新，请稍后重试。", "Unable to check for updates. Please try again later.", language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: updater.state) { _, _ in
            onStateChange()
        }
    }
}

private struct LoginItemRow: View {
    @ObservedObject var login: LoginItemController
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("登录 Mac 时自动启动", "Launch at login", language))
                    .font(.system(size: 12.5))
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(get: { login.state.isRequested }, set: login.setEnabled)
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("launch-at-login")
            }
            HStack {
                Text(login.state.message(in: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("login-status")
                Spacer()
                if login.state == .requiresApproval {
                    Button(L10n.t("打开系统登录项设置…", "Open Login Items Settings…", language), action: login.openSystemSettings)
                        .controlSize(.small)
                }
            }
            if let error = login.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("login-error")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
