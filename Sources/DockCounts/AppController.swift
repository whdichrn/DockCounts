import AppKit
import SwiftUI
import ApplicationServices

final class AppController: NSObject, ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); refresh() }
    }
    @Published var trusted = false
    @Published var minimizeToApplication = false
    @Published var intercepting = false
    @Published var message = "正在检查权限…"
    private let badges = BadgeController()
    private let clicks = ClickInterceptor()
    private let worker = DispatchQueue(label: "DockCounts.accessibility", qos: .userInitiated)
    private var timer: Timer?
    private var busy = false
    private var generation = 0
    private var settingsWindow: NSWindow?
    private let picker = WindowPickerController()
    private var menuOpen = false
    private var dockDefaults: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }
    override init() {
        super.init()
        clicks.onClick = { [weak self] entry, point in self?.showWindows(entry, at: point) }
        clicks.onPointerDown = { [weak self] point in self?.picker.dismissIfOutside(at: point) }
        picker.onDismiss = { [weak self] in
            self?.menuOpen = false
            self?.refresh()
        }
    }
    func start() {
        refresh()
        timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 260, width: 492, height: 390), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "DockCounts"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(controller: self))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    #if DEBUG
    // In-process callback smoke test: no synthetic mouse input is posted to the desktop.
    func smokeClick(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let url = app.bundleURL,
              let entry = AX.dockEntries(applications: [url.standardizedFileURL: app.processIdentifier]).first else {
            FileHandle.standardError.write(Data("SMOKE: no fixture entry\n".utf8)); return
        }
        FileHandle.standardError.write(Data("SMOKE: entry \(entry.frame) count \(String(describing: entry.counts))\n".utf8))
        clicks.entries = [entry]
        let point = CGPoint(x: entry.frame.midX, y: entry.frame.midY)
        let proxy: CGEventTapProxy? = nil
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)!
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)!
        let consumedDown = clicks.handle(proxy, .leftMouseDown, down) == nil
        let consumedUp = clicks.handle(proxy, .leftMouseUp, up) == nil
        FileHandle.standardError.write(Data("SMOKE: consumed down=\(consumedDown) up=\(consumedUp)\n".utf8))
    }
    #endif
    func stop() { timer?.invalidate(); generation += 1; picker.dismiss(notify: false); menuOpen = false; clicks.stop(); badges.hide() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func refresh() {
        trusted = AXIsProcessTrusted()
        minimizeToApplication = dockDefaults?.bool(forKey: "minimize-to-application") ?? false
        guard enabled && trusted && minimizeToApplication else {
            generation += 1
            picker.dismiss(notify: false); menuOpen = false
            badges.hide(); clicks.stop(); intercepting = false
            message = !enabled ? "已暂停" : !trusted ? "需要辅助功能权限" : "请先开启“将窗口最小化至应用程序图标”"
            return
        }
        if !intercepting { intercepting = clicks.start() }
        message = intercepting ? "运行中 · 点击 Dock 图标选择窗口" : "无法接管点击，请在授权后重新启动"
        guard !busy, !menuOpen else { return }
        busy = true
        let token = generation
        let applications = NSWorkspace.shared.runningApplications.reduce(into: [URL: pid_t]()) { result, app in
            if let url = app.bundleURL, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { result[url.standardizedFileURL] = app.processIdentifier }
        }
        worker.async { [weak self] in
            let entries = AX.dockEntries(applications: applications)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard token == self.generation, self.enabled, self.trusted, self.minimizeToApplication, !self.menuOpen else { return }
                self.clicks.entries = entries
                self.badges.update(entries)
            }
        }
    }
    func showWindows(_ entry: DockEntry, at point: CGPoint) {
        guard !menuOpen else { return }
        clicks.entries = []
        menuOpen = true
        picker.onChoose = { [weak self] window in
            guard let self else { return }
            if !WindowActivator.activate(pid: entry.pid, window: window) {
                self.message = "该窗口已关闭或应用暂时没有响应"
            }
        }
        picker.present(name: entry.name, windows: AX.windows(pid: entry.pid) ?? [], icon: entry.frame, at: point)
    }
}
