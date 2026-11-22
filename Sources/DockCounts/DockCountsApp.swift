import SwiftUI
import AppKit

@main
struct DockCountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(controller: delegate.controller)
        } label: {
            Image(nsImage: AppArtwork.menuBarIcon).accessibilityLabel("DockCounts")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { delegate.controller.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于 DockCounts…", action: delegate.controller.showAbout)
            }
        }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.controller.smokeClick(bundleID: bundleID)
            }
        }
        #endif
        if !UserDefaults.standard.bool(forKey: "hasLaunched")
            || (!controller.trusted && controller.preferences.needsAnyService)
            || CommandLine.arguments.contains("--settings") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            controller.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

struct StatusMenuView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Text(controller.message)
        if !controller.trusted && controller.preferences.needsAnyService {
            Button("授权辅助功能…", action: controller.requestPermission)
        }
        Divider()
        Toggle("启用 DockCounts", isOn: $controller.preferences.enabled)
        Toggle("显示 Dock 角标", isOn: $controller.preferences.badgesEnabled)
        Toggle("点按选择窗口", isOn: $controller.preferences.windowSelectionEnabled)
        Toggle("⌘Tab 切换增强", isOn: cmdTabBinding)
        Divider()
        Button("设置…") { controller.showSettings() }
            .keyboardShortcut(",")
        Button("关于 DockCounts…", action: controller.showAbout)
        Divider()
        Button("退出 DockCounts") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var cmdTabBinding: Binding<Bool> {
        Binding(
            get: { controller.preferences.cmdTabRestoreMinimized || controller.preferences.cmdTabReopenEmptyApp },
            set: { enabled in
                controller.preferences.cmdTabRestoreMinimized = enabled
                controller.preferences.cmdTabReopenEmptyApp = enabled
            }
        )
    }
}
