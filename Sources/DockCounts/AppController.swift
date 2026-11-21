import AppKit
import SwiftUI
import ApplicationServices

final class AppController: NSObject, ObservableObject {
    private let store: PreferencesStore
    let login: LoginItemController
    @Published var preferences: AppPreferences {
        didSet {
            store.save(preferences)
            if !preferences.enabled || !preferences.windowSelectionEnabled {
                picker.dismiss(notify: false); menuOpen = false
                clicks.stop(); intercepting = false
            }
            if oldValue.selectSingleWindow != preferences.selectSingleWindow {
                picker.dismiss(notify: false); menuOpen = false
            }
            renderCurrentState()
            if oldValue.enabled != preferences.enabled || oldValue.badgesEnabled != preferences.badgesEnabled || oldValue.windowSelectionEnabled != preferences.windowSelectionEnabled {
                refresh(force: true)
            }
        }
    }
    @Published var settingsTab: SettingsTab = .general
    @Published var trusted = false
    @Published var minimizeToApplication = false
    @Published var intercepting = false
    @Published var message = "正在检查权限…"
    private let badges = BadgeController()
    private let clicks = ClickInterceptor()
    private let geometryWorker = DispatchQueue(label: "DockCounts.dockGeometry", qos: .userInteractive)
    private let inventoryWorker = DispatchQueue(label: "DockCounts.windowInventory", qos: .userInitiated)
    private var timer: Timer?
    private var geometryBusy = false
    private var inventoryBusy = false
    private var servicesActive = false
    private var generation = 0
    private var inventoryRevision = 0
    private var nextPermissionPoll = Date.distantPast
    private var nextGeometryPoll = Date.distantPast
    private var nextInventoryPoll = Date.distantPast
    private var nextFullGeometryPoll = Date.distantPast
    private var lastSnapshot: AX.DockSnapshot?
    private var dockEntries: [DockEntry] = []
    private var windowCache = WindowInventoryCache()
    private let events = DockEventMonitor()
    private var motion = DockMotion()
    private var visibility = DockVisibility()
    private var phase = DockPhase.unknown
    private var dockPID: pid_t?
    private var runningPIDs = Set<pid_t>()
    private var applications: [URL: pid_t] = [:]
    private var nextApplicationsPoll = Date.distantPast
    private var settingsWindow: NSWindow?
    private let picker = WindowPickerController()
    private var menuOpen = false
    private var dockDefaults: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }
    init(store: PreferencesStore = PreferencesStore(), login: LoginItemController = LoginItemController()) {
        self.store = store; self.login = login; preferences = store.load()
        super.init()
        clicks.shouldIntercept = { [weak self] entry in
            guard let self else { return false }
            return self.trusted && self.minimizeToApplication && self.preferences.selectsWindow(total: entry.counts?.total ?? 0)
        }
        clicks.onClick = { [weak self] entry, point in self?.showWindows(entry, at: point) }
        clicks.onPointerDown = { [weak self] point in self?.picker.dismissIfOutside(at: point) }
        picker.onDismiss = { [weak self] in
            self?.menuOpen = false
            self?.refresh(force: true)
        }
    }
    func start() {
        events.onChange = { [weak self] in
            guard let self else { return }
            self.motion.wake(at: Date())
            self.nextGeometryPoll = .distantPast
            self.nextFullGeometryPoll = .distantPast
            self.nextInventoryPoll = .distantPast
        }
        events.onApplicationsChange = { [weak self] in self?.nextApplicationsPoll = .distantPast }
        refresh()
        timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        login.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 260, width: 660, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "DockCounts"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(controller: self))
            window.minSize = NSSize(width: 590, height: 560)
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
    func stop() {
        timer?.invalidate(); generation += 1; inventoryRevision += 1
        servicesActive = false; events.stop()
        picker.dismiss(notify: false); menuOpen = false; clicks.stop(); badges.reset()
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func refresh(force: Bool = false) {
        let now = Date()
        let checkPermissions = force || now >= nextPermissionPoll
        if checkPermissions {
            let access = AXIsProcessTrusted()
            let compact = dockDefaults?.bool(forKey: "minimize-to-application") ?? false
            if trusted != access { trusted = access }
            if minimizeToApplication != compact { minimizeToApplication = compact }
            login.refresh()
            nextPermissionPoll = now.addingTimeInterval(1)
        }
        guard preferences.needsDock && trusted && minimizeToApplication else {
            events.stop()
            if servicesActive {
                generation += 1; inventoryRevision += 1; servicesActive = false
                picker.dismiss(notify: false); menuOpen = false
                badges.hide(); clicks.stop(); intercepting = false
                dockEntries = []; windowCache.reset(); visibility.reset()
                nextGeometryPoll = .distantPast; nextInventoryPoll = .distantPast; lastSnapshot = nil
            }
            setMessage(!preferences.enabled ? "已暂停" : !preferences.needsDock ? "角标与窗口选择均已关闭" : !trusted ? "需要辅助功能权限" : "请先开启“将窗口最小化至应用程序图标”")
            return
        }
        if !servicesActive { servicesActive = true; events.start() }
        if checkPermissions { events.reconnect() }
        if preferences.windowSelectionEnabled {
            if !intercepting && (checkPermissions || force) { intercepting = clicks.start() }
        } else if intercepting { clicks.stop(); intercepting = false }
        setMessage(preferences.windowSelectionEnabled && !intercepting ? "无法接管点击，请在授权后重新启动" : preferences.windowSelectionEnabled ? (preferences.badgesEnabled ? "运行中 · 角标与窗口选择" : "运行中 · 仅窗口选择") : "运行中 · 仅显示角标")
        let token = generation
        let point = NSEvent.mouseLocation
        let pointer = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        let interval = motion.interval(pointer: pointer, entries: dockEntries, at: now)
        // Enter the fast cadence immediately when the pointer approaches Dock.
        let approachingDock = interval < 0.1 && nextGeometryPoll.timeIntervalSince(now) > interval
        if !geometryBusy && (force || approachingDock || now >= nextGeometryPoll) {
            geometryBusy = true
            nextGeometryPoll = now.addingTimeInterval(interval)
            if now >= nextApplicationsPoll {
                let ownPID = ProcessInfo.processInfo.processIdentifier
                applications = NSWorkspace.shared.runningApplications.reduce(into: [URL: pid_t]()) { result, app in
                    let pid = app.processIdentifier
                    if pid != ownPID, let url = app.bundleURL { result[url.standardizedFileURL] = pid }
                }
                runningPIDs = Set(applications.values)
                nextApplicationsPoll = now.addingTimeInterval(1)
            }
            let applications = self.applications
            let expectedDockPID = events.dockPID
            let axScreens = NSScreen.screens.map { Geometry.appKitRect($0.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0) }
            let previous = lastSnapshot
            let refreshItems = force || interval < 0.1 || now >= nextFullGeometryPoll
            if refreshItems { nextFullGeometryPoll = now.addingTimeInterval(0.35) }
            geometryWorker.async { [weak self] in
                let snapshot = AX.dockSnapshot(applications: applications, dockPID: expectedDockPID, previous: previous, refreshItems: refreshItems, windowProvider: { _ in nil })
                let evidence = snapshot.map { AX.dockEvidence($0, screenFrames: axScreens) } ?? .unknown
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.geometryBusy = false
                    guard token == self.generation, self.servicesActive else { return }
                    let finished = Date()
                    let visible = self.visibility.update(evidence, at: finished)
                    var moving = false
                    if let snapshot {
                        self.lastSnapshot = snapshot
                        if self.dockPID != snapshot.pid {
                            self.dockPID = snapshot.pid; self.badges.reset()
                            self.motion.wake(at: finished)
                        }
                        moving = self.motion.observe(entries: snapshot.entries, dockFrame: snapshot.frame, at: finished)
                        self.dockEntries = snapshot.entries.map { entry in
                            DockEntry(pid: entry.pid, name: entry.name, url: entry.url, frame: entry.frame, windows: self.windowCache.windows(pid: entry.pid, at: finished))
                        }
                        if moving { self.nextGeometryPoll = min(self.nextGeometryPoll, finished.addingTimeInterval(1.0 / 30.0)) }
                    }
                    let nextPhase: DockPhase = evidence == .hidden ? .hidden : evidence == .unknown ? .unknown : moving ? .moving : .visible
                    if nextPhase != self.phase {
                        DockTrace.event("dock.phase \(self.phase.rawValue)->\(nextPhase.rawValue) visible=\(visible) entries=\(self.dockEntries.count)")
                        self.phase = nextPhase
                    }
                    self.renderCurrentState()
                    self.refresh()
                }
            }
        }
        if !inventoryBusy && !dockEntries.isEmpty && (force || now >= nextInventoryPoll) {
            inventoryBusy = true
            nextInventoryPoll = now.addingTimeInterval(0.35)
            let revision = inventoryRevision
            let pids = Set(dockEntries.map(\.pid))
            inventoryWorker.async { [weak self] in
                var cache: [pid_t: [WindowRecord]] = [:]
                for pid in pids { if let windows = AX.windows(pid: pid) { cache[pid] = windows } }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inventoryBusy = false
                    guard token == self.generation, revision == self.inventoryRevision, self.servicesActive else { return }
                    let finished = Date()
                    for (pid, windows) in cache { self.windowCache.record(pid: pid, windows: windows, at: finished) }
                    self.windowCache.retain(self.runningPIDs)
                    self.dockEntries = self.dockEntries.map { entry in
                        DockEntry(pid: entry.pid, name: entry.name, url: entry.url, frame: entry.frame, windows: self.windowCache.windows(pid: entry.pid, at: finished))
                    }
                    self.renderCurrentState()
                }
            }
        }
    }
    private func renderCurrentState() {
        let active = servicesActive && preferences.needsDock && trusted && minimizeToApplication
        clicks.entries = active && preferences.windowSelectionEnabled && !menuOpen && visibility.isVisible ? dockEntries : []
        if active && preferences.badgesEnabled {
            badges.update(dockEntries, visible: visibility.isVisible, runningPIDs: runningPIDs, appearance: preferences.appearance)
        } else { badges.hide() }
    }
    func showAbout() { showSettings(tab: .about) }
    func restoreDefaults() { preferences = AppPreferences() }
    private func setMessage(_ value: String) { if message != value { message = value } }
    func showWindows(_ entry: DockEntry, at point: CGPoint) {
        guard !menuOpen, preferences.enabled, preferences.windowSelectionEnabled else { return }
        let windows = AX.windows(pid: entry.pid) ?? entry.windows ?? []
        if windows.count == 1 && !preferences.selectSingleWindow {
            _ = WindowActivator.activate(pid: entry.pid, window: windows[0])
            refresh(force: true)
            return
        }
        clicks.entries = []
        menuOpen = true
        picker.onChoose = { [weak self] window in
            guard let self else { return }
            if WindowActivator.activate(pid: entry.pid, window: window) {
                if let cached = self.windowCache.windows(pid: entry.pid, at: Date()) {
                    self.windowCache.record(pid: entry.pid, windows: cached.map { record in
                        CFEqual(record.element, window.element) ? WindowRecord(element: record.element, title: record.title, minimized: false) : record
                    }, at: Date())
                }
            } else {
                self.message = "该窗口已关闭或应用暂时没有响应"
            }
            self.inventoryRevision += 1
            self.nextInventoryPoll = .distantPast
        }
        picker.present(name: entry.name, windows: windows, icon: entry.frame, at: point)
    }
}
