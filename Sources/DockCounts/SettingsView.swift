import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var confirmReset = false
    var body: some View {
        TabView(selection: $controller.settingsTab) {
            general.tabItem { Label("通用", systemImage: "gearshape") }.tag(SettingsTab.general)
            windows.tabItem { Label("窗口选择", systemImage: "rectangle.on.rectangle") }.tag(SettingsTab.windows)
            badges.tabItem { Label("角标外观", systemImage: "circle.lefthalf.filled") }.tag(SettingsTab.badges)
            about.tabItem { Label("关于", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .padding(12)
        .frame(minWidth: 560, idealWidth: 660, maxWidth: .infinity, minHeight: 520, idealHeight: 680, maxHeight: .infinity)
        .confirmationDialog("恢复功能与外观的默认设置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("恢复默认设置") { controller.restoreDefaults() }
            Button("取消", role: .cancel) {}
        } message: { Text("开机启动由系统单独管理，不会随此操作改变。") }
    }
    private var general: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: AppArtwork.appIcon).resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DockCounts").font(.title2.bold())
                        Text(controller.message).font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
                Toggle("启用 DockCounts", isOn: $controller.preferences.enabled).accessibilityIdentifier("master-enabled")
                Text("暂停时保留全部配置；角标和窗口选择还可以分别关闭。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("启动") { LoginItemRow(login: controller.login) }
            Section("系统状态") {
                Label(controller.trusted ? "辅助功能已授权" : "需要辅助功能权限", systemImage: controller.trusted ? "checkmark.circle.fill" : "lock.circle")
                if !controller.trusted { Button("授权辅助功能…", action: controller.requestPermission) }
                Label(controller.minimizeToApplication ? "已开启最小化至应用程序图标" : "需要开启最小化至应用程序图标", systemImage: controller.minimizeToApplication ? "checkmark.circle.fill" : "circle")
                if !controller.minimizeToApplication {
                    Button("打开桌面与程序坞设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!) }
                }
            }
            Section {
                Button("恢复功能与外观默认设置…") { confirmReset = true }
                Text("所有开关和外观设置即时生效，并在下次启动时保留。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var windows: some View {
        Form {
            Section("Dock 点击") {
                Toggle("启用窗口选择", isOn: $controller.preferences.windowSelectionEnabled).accessibilityIdentifier("window-selection-enabled")
                Text("普通点击有窗口的 Dock 图标，显示该应用的窗口列表。关闭后交还系统处理，角标仍可独立显示。")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("只有一个窗口时也显示选择列表", isOn: $controller.preferences.selectSingleWindow)
                    .disabled(!controller.preferences.windowSelectionEnabled)
                    .accessibilityIdentifier("single-window-selection")
                Text(controller.preferences.selectSingleWindow ? "单窗口和多窗口均可打开列表。" : "仅在有多个窗口时打开列表；单窗口保留系统点击行为。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("使用方式") {
                Label("方向键选择，回车恢复或切换窗口", systemImage: "keyboard")
                Label("Esc 或点击外部关闭列表", systemImage: "escape")
                Text("右键、带修饰键的点击和拖动继续使用 Dock 的原有行为。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var badges: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color.blue.opacity(0.18), Color.orange.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(nsImage: AppArtwork.appIcon).resizable().frame(width: 64, height: 64)
                    CountBadge(counts: WindowCounts(minimized: 2, total: 5), appearance: controller.preferences.appearance)
                        .offset(x: 22, y: 26)
                }.frame(width: 114, height: 90)
                VStack(alignment: .leading, spacing: 5) {
                    Text("角标实时预览").font(.headline)
                    Text("窗口总数 · 已最小化数").foregroundStyle(.secondary)
                    Text(controller.preferences.badgesEnabled && controller.preferences.enabled ? "调整会同步到 Dock。" : "功能关闭时仍可调整和预览外观。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("还原外观") { controller.preferences.appearance = BadgeAppearance() }
            }.padding(16)
            Form {
                Section {
                    Toggle("显示窗口角标", isOn: $controller.preferences.badgesEnabled).accessibilityIdentifier("badges-enabled")
                    Text("角标与窗口选择独立；关闭角标不会关闭窗口列表。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("材质") {
                    Picker("候选材质", selection: $controller.preferences.appearance.surface) {
                        ForEach(BadgeSurface.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("badge-surface")
                    strengthSlider("背景不透明度", value: $controller.preferences.appearance.backgroundOpacity, identifier: "badge-opacity")
                    Text("仅调整背景强度，数字保持清晰；玻璃材质本身仍有透光效果。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("边缘与层次") {
                    Picker("附加描边", selection: $controller.preferences.appearance.edge) {
                        ForEach(BadgeEdge.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("badge-edge")
                    Toggle("高光", isOn: $controller.preferences.appearance.highlights).accessibilityIdentifier("badge-highlights")
                    Text("关闭高光后使用哑光外观；原生玻璃的折射亮边由系统统一绘制。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("附加阴影", isOn: $controller.preferences.appearance.shadow).accessibilityIdentifier("badge-shadow")
                    Toggle("鲜明显示", isOn: $controller.preferences.appearance.vivid).accessibilityIdentifier("badge-vivid")
                    Text("鲜明显示增强文字、描边及染色色彩的对比。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("颜色") {
                    Picker("染色来源", selection: $controller.preferences.appearance.tint) {
                        ForEach(BadgeTint.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("badge-tint")
                    if controller.preferences.appearance.tint == .custom {
                        ColorPicker("自选染色", selection: Binding(get: { Color(nsColor: controller.preferences.appearance.customColor.nsColor) }, set: { controller.preferences.appearance.customColor = RGBColor(NSColor($0)) }), supportsOpacity: false)
                            .accessibilityIdentifier("badge-custom-color")
                        HexColorField(color: $controller.preferences.appearance.customColor)
                    }
                    strengthSlider("染色强度", value: $controller.preferences.appearance.tintStrength, identifier: "badge-tint-strength")
                        .disabled(controller.preferences.appearance.tint == .none)
                    Picker("数字颜色", selection: $controller.preferences.appearance.textColor) {
                        ForEach(BadgeTextColor.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("badge-text-color")
                }
            }.formStyle(.grouped)
        }
    }
    private func strengthSlider(_ label: String, value: Binding<Double>, identifier: String) -> some View {
        HStack {
            Slider(value: value, in: 0...1, step: 0.01) { Text(label) }.accessibilityIdentifier(identifier)
            Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
        }
    }
    private var about: some View {
        VStack(spacing: 15) {
            Image(nsImage: AppArtwork.appIcon).resizable().frame(width: 96, height: 96)
            Text("DockCounts").font(.largeTitle.bold())
            Text("版本 \(ProjectLinks.version)").foregroundStyle(.secondary).accessibilityIdentifier("app-version")
            Text("在 Dock 上看见窗口数量，选择并恢复需要的窗口。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Link("项目主页", destination: ProjectLinks.home).accessibilityIdentifier("project-home")
                Link("版本与下载", destination: ProjectLinks.releases)
            }.padding(.vertical, 6)
            Divider().frame(width: 320)
            Text("窗口清单来自应用公开的辅助功能信息。\n应用不采集屏幕图像，不发送窗口信息。")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("macOS 15 使用兼容磨砂；较新系统支持原生玻璃。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HexColorField: View {
    @Binding var color: RGBColor
    @State private var draft = ""
    var body: some View {
        HStack {
            Text("颜色代码")
            Spacer()
            TextField("#336699", text: $draft)
                .labelsHidden()
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder).frame(width: 110)
                .accessibilityLabel("自选颜色代码").accessibilityIdentifier("badge-color-hex")
        }
        .onAppear { draft = color.hex }
        .onChange(of: draft) { _, value in
            if let parsed = RGBColor(hex: value), parsed.hex != color.hex { color = parsed }
        }
        .onChange(of: color) { _, value in if RGBColor(hex: draft) != value { draft = value.hex } }
        .onSubmit { draft = color.hex }
    }
}

private struct LoginItemRow: View {
    @ObservedObject var login: LoginItemController
    var body: some View {
        Toggle("登录 Mac 时自动启动", isOn: Binding(get: { login.state.isRequested }, set: login.setEnabled))
            .accessibilityIdentifier("launch-at-login")
        Text(login.state.message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("login-status")
        if let error = login.error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("login-error") }
        if login.state == .requiresApproval { Button("打开系统登录项设置…", action: login.openSystemSettings) }
    }
}
