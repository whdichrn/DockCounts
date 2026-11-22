import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var confirmReset = false

    var body: some View {
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
                        Text("更改即时生效并保存")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("还原默认设置…") { confirmReset = true }
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 4)
                }
            }
            .padding(14)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("恢复默认功能与外观设置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("恢复默认设置") { controller.restoreDefaults() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("开机启动由系统登录项单独管理，不会随此操作改变。")
        }
        .onChange(of: controller.settingsTab) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.trusted) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.minimizeToApplication) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.login.state) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.windowSelectionEnabled) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.minimizeActiveSingleWindow) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.cmdTabRestoreMinimized) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.cmdTabReopenEmptyApp) { _, _ in scheduleResize(animated: true) }
        .onChange(of: controller.preferences.badgesEnabled) { _, _ in scheduleResize(animated: true) }
    }

    private func scheduleResize(animated: Bool) {
        DispatchQueue.main.async {
            controller.resizeSettingsWindow(animated: animated)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.general, title: "通用", symbol: "gearshape")
            tabButton(.enhancement, title: "增强", symbol: "sparkles")
            tabButton(.appearance, title: "外观", symbol: "circle.lefthalf.filled")
            tabButton(.about, title: "关于", symbol: "info.circle")
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
        VStack(alignment: .leading, spacing: 11) {
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

            SettingsCard(title: "启动与系统状态") {
                LoginItemRow(login: controller.login)
                SettingsDivider()
                SettingsRow {
                    Label(
                        controller.trusted ? "辅助功能已授权" : "需要辅助功能权限",
                        systemImage: controller.trusted ? "checkmark.circle.fill" : "lock.circle.fill"
                    )
                    .foregroundStyle(controller.trusted ? Color.primary : Color.orange)
                    Spacer()
                    if !controller.trusted {
                        Button("授权辅助功能…", action: controller.requestPermission)
                    }
                }
                SettingsDivider()
                SettingsRow {
                    Label(
                        controller.minimizeToApplication
                            ? "已开启“将窗口最小化至应用程序图标”"
                            : "建议开启“将窗口最小化至应用程序图标”",
                        systemImage: controller.minimizeToApplication ? "checkmark.circle.fill" : "info.circle"
                    )
                    .foregroundStyle(controller.minimizeToApplication ? Color.primary : Color.secondary)
                    Spacer()
                    if !controller.minimizeToApplication {
                        Button("前往设置") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                        }
                    }
                }
            }
        }
    }

    private var enhancementTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "点按 Dock 图标") {
                SettingsRow {
                    Text("点按图标选择窗口")
                    Spacer()
                    Toggle("", isOn: $controller.preferences.windowSelectionEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("window-selection-enabled")
                }
                SettingsDivider()
                SettingsRow {
                    Text("触发条件")
                    Spacer()
                    Picker("触发条件", selection: $controller.preferences.triggerMode) {
                        ForEach(WindowTriggerMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .disabled(!controller.preferences.windowSelectionEnabled)
                    .accessibilityIdentifier("window-trigger-mode")
                }
                SettingsDivider()
                SettingsRow {
                    Text("前台单窗口再次点按时直接最小化")
                    Spacer()
                    Toggle("", isOn: $controller.preferences.minimizeActiveSingleWindow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!controller.preferences.windowSelectionEnabled)
                        .accessibilityIdentifier("minimize-active-single-window")
                }
                SettingsDivider()
                Text(controller.preferences.triggerMode.summary + (controller.preferences.minimizeActiveSingleWindow ? " 单窗口处于前台时再次点按直接最小化。" : ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }

            SettingsCard(title: "⌘Tab 切换增强") {
                SettingsRow {
                    Text("全部最小化时自动处理")
                    Spacer()
                    Toggle("", isOn: $controller.preferences.cmdTabRestoreMinimized)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("cmdtab-restore-minimized")
                }
                SettingsDivider()
                SettingsRow {
                    Text("多个最小化窗口")
                    Spacer()
                    Picker("多个最小化窗口", selection: $controller.preferences.cmdTabMultiMinimizedBehavior) {
                        ForEach(CmdTabMultiMinimizedBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    .disabled(!controller.preferences.cmdTabRestoreMinimized)
                    .accessibilityIdentifier("cmdtab-multi-behavior")
                }
                SettingsDivider()
                SettingsRow {
                    Text("零窗口应用自动新建窗口")
                    Spacer()
                    Toggle("", isOn: $controller.preferences.cmdTabReopenEmptyApp)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("cmdtab-reopen-empty")
                }
                SettingsDivider()
                Text("仅在通过 ⌘Tab 切换且确认应用在其他空间无可见窗口时触发。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
        }
    }

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "整体外观") {
                SettingsRow {
                    Text("外观模式")
                    Spacer()
                    Picker("外观模式", selection: $controller.preferences.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 222)
                    .accessibilityIdentifier("app-appearance-mode")
                }
                SettingsDivider()
                Text("统一作用于程序坞角标、窗口选择菜单与设置窗口。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }

            SettingsCard(title: "Dock 角标") {
                SettingsRow {
                    Text("显示 Dock 窗口角标")
                    Spacer()
                    Toggle("", isOn: $controller.preferences.badgesEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("badges-enabled")
                }
                SettingsDivider()
                SettingsRow {
                    Text("显示时机")
                    Spacer()
                    Picker("显示时机", selection: $controller.preferences.badgeVisibility) {
                        ForEach(BadgeVisibilityMode.allCases) { mode in
                            Text(mode.title).tag(mode)
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
                    Text("角标风格")
                    Spacer()
                    Picker("角标风格", selection: $controller.preferences.appearance.preset) {
                        ForEach(BadgePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
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
                    Text("角标尺寸")
                    Spacer()
                    Picker("角标尺寸", selection: $controller.preferences.appearance.size) {
                        ForEach(BadgeSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                    .disabled(!controller.preferences.badgesEnabled)
                    .accessibilityIdentifier("badge-size")
                }
                SettingsDivider()
                SettingsRow {
                    Text("背景不透明度")
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
        VStack(spacing: 12) {
            Image(nsImage: AppArtwork.appIcon)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("DockCounts")
                    .font(.system(size: 20, weight: .bold))
                Text("版本 \(ProjectLinks.version)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .accessibilityIdentifier("app-version")
            }

            Text("在 Dock 上看清窗口数量，点按精准选择与恢复窗口。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("项目主页", destination: ProjectLinks.home)
                    .accessibilityIdentifier("project-home")
                Link("版本与下载", destination: ProjectLinks.releases)
            }
            .padding(.top, 2)

            Divider()
                .frame(width: 280)
                .padding(.vertical, 4)

            Text("窗口清单读取自系统辅助功能接口，不采集屏幕图像，不发起网络请求。\nmacOS 26+ 使用原生玻璃材质，macOS 15 使用系统磨砂兼容层。")
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

private struct LoginItemRow: View {
    @ObservedObject var login: LoginItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("登录 Mac 时自动启动")
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
                Text(login.state.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("login-status")
                Spacer()
                if login.state == .requiresApproval {
                    Button("打开系统登录项设置…", action: login.openSystemSettings)
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
