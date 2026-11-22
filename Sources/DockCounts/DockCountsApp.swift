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
                Button(L10n.t("设置…", "Settings…", delegate.controller.preferences.language)) { delegate.controller.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .appInfo) {
                Button(L10n.t("关于 DockCounts…", "About DockCounts…", delegate.controller.preferences.language), action: delegate.controller.showAbout)
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
        let lang = controller.preferences.language
        Text(controller.message)
        if !controller.trusted && controller.preferences.needsAnyService {
            Button(L10n.t("授权辅助功能…", "Grant Accessibility…", lang), action: controller.requestPermission)
        }
        Divider()
        Toggle(L10n.t("启用 DockCounts", "Enable DockCounts", lang), isOn: $controller.preferences.enabled)
        Toggle(L10n.t("显示 Dock 角标", "Show Dock Badges", lang), isOn: $controller.preferences.badgesEnabled)
        Toggle(L10n.t("点按选择窗口", "Click Dock to Pick Window", lang), isOn: $controller.preferences.windowSelectionEnabled)
        Toggle(L10n.t("⌘Tab 切换增强", "⌘Tab Switch Enhancement", lang), isOn: cmdTabBinding)
        Divider()
        Button(L10n.t("设置…", "Settings…", lang)) { controller.showSettings() }
            .keyboardShortcut(",")
        Button(L10n.t("关于 DockCounts…", "About DockCounts…", lang), action: controller.showAbout)
        Divider()
        Button(L10n.t("退出 DockCounts", "Quit DockCounts", lang)) { NSApp.terminate(nil) }
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
