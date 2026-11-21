import SwiftUI
import AppKit

@main
struct DockCountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            StatusView(controller: delegate.controller)
        } label: {
            Image(nsImage: AppArtwork.menuBarIcon).accessibilityLabel("DockCounts")
        }.menuBarExtraStyle(.window)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-menu"), index + 1 < CommandLine.arguments.count {
            let bundleID = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.controller.smokeClick(bundleID: bundleID) }
        }
        #endif
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || !controller.trusted || CommandLine.arguments.contains("--settings") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            controller.showSettings()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { controller.stop() }
}
struct StatusView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(nsImage: AppArtwork.appIcon).resizable().frame(width: 32, height: 32)
                Text("DockCounts").font(.headline)
            }
            Text(controller.message).font(.callout).foregroundStyle(.secondary)
            Toggle("启用窗口计数与选择", isOn: $controller.enabled)
            HStack {
                Button("设置与权限…", action: controller.showSettings)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }.padding(18).frame(width: 320)
    }
}
struct SettingsView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: AppArtwork.appIcon).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DockCounts").font(.title2.bold())
                    Text("在 Dock 上看见窗口数量，点击选择窗口。") .foregroundStyle(.secondary)
                }
            }
            Toggle("启用窗口计数与选择", isOn: $controller.enabled)
            VStack(alignment: .leading, spacing: 12) {
                Label(controller.trusted ? "辅助功能已授权" : "需要辅助功能权限", systemImage: controller.trusted ? "checkmark.circle.fill" : "lock.circle")
                if !controller.trusted { Button("授权辅助功能…", action: controller.requestPermission) }
                Label(controller.minimizeToApplication ? "已开启最小化至应用程序图标" : "请开启最小化至应用程序图标", systemImage: controller.minimizeToApplication ? "checkmark.circle.fill" : "circle")
                if !controller.minimizeToApplication {
                    Button("打开桌面与程序坞设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!) }
                }
            }.font(.callout)
            HStack(spacing: 10) {
                CountBadge(counts: WindowCounts(minimized: 2, total: 5))
                Text("窗口总数 · 已最小化数").font(.callout).foregroundStyle(.secondary)
            }
            Text("普通点击显示窗口列表；选择窗口即可恢复并切换。右键和修饰键点击保留系统行为。窗口数量取决于应用提供的辅助功能信息。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(controller.message).font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(width: 440)
    }
}
