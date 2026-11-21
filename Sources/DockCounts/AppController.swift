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
                picker.dismiss(notify: false)
                menuOpen = false
                clicks.stop()
                intercepting = false
            }
            if oldValue.triggerMode != preferences.triggerMode
                || oldValue.minimizeActiveSingleWindow != preferences.minimizeActiveSingleWindow {
                picker.dismiss(notify: false)
                menuOpen = false
            }
            renderCurrentState()
            if oldValue.enabled != preferences.enabled
                || oldValue.badgesEnabled != preferences.badgesEnabled
                || oldValue.windowSelectionEnabled != preferences.windowSelectionEnabled {
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
    private var currentTimerInterval: TimeInterval = 0
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
    private var applications: [URL: [pid_t]] = [:]
    private var nextApplicationsPoll = Date.distantPast
    private var settingsWindow: NSWindow?
    private var settingsHostingView: NSHostingView<SettingsView>?
    private let picker = WindowPickerController()
    private var menuOpen = false
    private var dockDefaults: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }

    init(store: PreferencesStore = PreferencesStore(), login: LoginItemController = LoginItemController()) {
        self.store = store
        self.login = login
        preferences = store.load()
        super.init()

        clicks.shouldIntercept = { [weak self] entry in
            guard let self, self.trusted else { return false }
            let windows = entry.windows ?? []
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let isActive = frontPID.map { entry.pids.contains($0) } ?? false
            return self.preferences.clickAction(windows: windows, isAppActive: isActive) != .passThrough
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
            self.refresh()
        }
        events.onApplicationsChange = { [weak self] in
            self?.nextApplicationsPoll = .distantPast
            self?.refresh()
        }
        refresh(force: true)
    }

    private func rescheduleTimer(interval: TimeInterval) {
        let clamped = max(1.0 / 30.0, interval)
        guard timer == nil || abs(clamped - currentTimerInterval) > 0.005 else { return }
        timer?.invalidate()
        currentTimerInterval = clamped
        let nextTimer = Timer(timeInterval: clamped, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        login.refresh()
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: SettingsView(controller: self))
            hosting.translatesAutoresizingMaskIntoConstraints = true
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "DockCounts 设置"
            window.collectionBehavior = [.fullScreenNone]
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.contentMinSize = NSSize(width: 520, height: 300)
            window.contentMaxSize = NSSize(width: 520, height: 680)
            settingsWindow = window
            settingsHostingView = hosting
            resizeSettingsWindow(animated: false)
            window.center()
        } else {
            resizeSettingsWindow(animated: false)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func resizeSettingsWindow(animated: Bool = true) {
        guard let window = settingsWindow, let hosting = settingsHostingView else { return }
        hosting.layoutSubtreeIfNeeded()
        let fittedHeight = min(640, max(300, ceil(hosting.fittingSize.height)))
        let targetContentSize = NSSize(width: 520, height: fittedHeight)
        let currentFrame = window.frame
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
        guard abs(currentFrame.height - targetFrameSize.height) > 1 || abs(currentFrame.width - targetFrameSize.width) > 1 else {
            return
        }
        let nextOriginY = currentFrame.maxY - targetFrameSize.height
        let nextFrame = NSRect(x: currentFrame.origin.x, y: nextOriginY, width: targetFrameSize.width, height: targetFrameSize.height)
        window.setFrame(nextFrame, display: true, animate: animated)
    }

    #if DEBUG
    // In-process callback smoke test: no synthetic mouse input is posted to the desktop.
    func smokeClick(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let url = app.bundleURL,
              let entry = AX.dockEntries(applications: [url.standardizedFileURL: app.processIdentifier]).first else {
            FileHandle.standardError.write(Data("SMOKE: no fixture entry\n".utf8))
            return
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
        timer?.invalidate()
        timer = nil
        currentTimerInterval = 0
        generation += 1
        inventoryRevision += 1
        servicesActive = false
        events.stop()
        picker.dismiss(notify: false)
        menuOpen = false
        clicks.stop()
        badges.reset()
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

        guard preferences.needsDock && trusted else {
            events.stop()
            if servicesActive {
                generation += 1
                inventoryRevision += 1
                servicesActive = false
                picker.dismiss(notify: false)
                menuOpen = false
                badges.hide()
                clicks.stop()
                intercepting = false
                dockEntries = []
                windowCache.reset()
                visibility.reset()
                nextGeometryPoll = .distantPast
                nextInventoryPoll = .distantPast
                lastSnapshot = nil
            }
            setMessage(!preferences.enabled ? "已暂停" : !preferences.needsDock ? "角标与窗口选择均已关闭" : "需要辅助功能权限")
            rescheduleTimer(interval: 1.0)
            return
        }

        if !servicesActive {
            servicesActive = true
            events.start()
        }
        if checkPermissions { events.reconnect() }

        if preferences.windowSelectionEnabled {
            if !intercepting && (checkPermissions || force) { intercepting = clicks.start() }
        } else if intercepting {
            clicks.stop()
            intercepting = false
        }

        setMessage(
            preferences.windowSelectionEnabled && !intercepting
                ? "无法接管点击，请在授权后重新启动"
                : preferences.windowSelectionEnabled
                    ? (preferences.badgesEnabled ? "运行中 · 角标与左键菜单" : "运行中 · 仅左键菜单")
                    : "运行中 · 仅显示角标"
        )

        let token = generation
        let point = NSEvent.mouseLocation
        let pointer = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        let interval = motion.interval(pointer: pointer, entries: dockEntries, at: now)
        rescheduleTimer(interval: interval)

        let approachingDock = interval < 0.1 && nextGeometryPoll.timeIntervalSince(now) > interval
        if !geometryBusy && (force || approachingDock || now >= nextGeometryPoll) {
            geometryBusy = true
            nextGeometryPoll = now.addingTimeInterval(interval)
            if now >= nextApplicationsPoll {
                let ownPID = ProcessInfo.processInfo.processIdentifier
                var grouped: [URL: [pid_t]] = [:]
                var allPIDs = Set<pid_t>()
                for app in NSWorkspace.shared.runningApplications {
                    let pid = app.processIdentifier
                    guard pid != ownPID, let url = app.bundleURL?.standardizedFileURL else { continue }
                    allPIDs.insert(pid)
                    if app.isActive {
                        grouped[url, default: []].insert(pid, at: 0)
                    } else {
                        grouped[url, default: []].append(pid)
                    }
                }
                applications = grouped
                runningPIDs = allPIDs
                nextApplicationsPoll = now.addingTimeInterval(1)
            }

            let applications = self.applications
            let expectedDockPID = events.dockPID
            let axScreens = NSScreen.screens.map {
                Geometry.appKitRect($0.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            }
            let previous = lastSnapshot
            let refreshItems = force || interval < 0.1 || now >= nextFullGeometryPoll
            if refreshItems { nextFullGeometryPoll = now.addingTimeInterval(0.35) }

            geometryWorker.async { [weak self] in
                let snapshot = AX.dockSnapshot(
                    applicationsByURL: applications,
                    dockPID: expectedDockPID,
                    previous: previous,
                    refreshItems: refreshItems,
                    windowProvider: { _ in nil }
                )
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
                            self.dockPID = snapshot.pid
                            self.badges.reset()
                            self.motion.wake(at: finished)
                        }
                        moving = self.motion.observe(entries: snapshot.entries, dockFrame: snapshot.frame, at: finished)
                        self.dockEntries = snapshot.entries.map { entry in
                            let combined = entry.pids.compactMap { self.windowCache.windows(pid: $0, at: finished) }
                            let windows: [WindowRecord]? = combined.isEmpty ? nil : combined.flatMap { $0 }
                            return DockEntry(pid: entry.pid, pids: entry.pids, name: entry.name, url: entry.url, frame: entry.frame, windows: windows)
                        }
                        if moving {
                            self.nextGeometryPoll = min(self.nextGeometryPoll, finished.addingTimeInterval(1.0 / 30.0))
                            self.rescheduleTimer(interval: 1.0 / 30.0)
                        }
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
            let pids = Set(dockEntries.flatMap(\.pids))
            inventoryWorker.async { [weak self] in
                var cache: [pid_t: [WindowRecord]] = [:]
                for pid in pids {
                    if let windows = AX.windows(pid: pid) { cache[pid] = windows }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inventoryBusy = false
                    guard token == self.generation, revision == self.inventoryRevision, self.servicesActive else { return }
                    let finished = Date()
                    for (pid, windows) in cache { self.windowCache.record(pid: pid, windows: windows, at: finished) }
                    self.windowCache.retain(self.runningPIDs)
                    self.dockEntries = self.dockEntries.map { entry in
                        let combined = entry.pids.compactMap { self.windowCache.windows(pid: $0, at: finished) }
                        let windows: [WindowRecord]? = combined.isEmpty ? nil : combined.flatMap { $0 }
                        return DockEntry(pid: entry.pid, pids: entry.pids, name: entry.name, url: entry.url, frame: entry.frame, windows: windows)
                    }
                    self.renderCurrentState()
                }
            }
        }
    }

    private func renderCurrentState() {
        let active = servicesActive && preferences.needsDock && trusted
        clicks.dockPID = dockPID
        clicks.entries = active && preferences.windowSelectionEnabled && !menuOpen && visibility.isVisible ? dockEntries : []
        if active && preferences.badgesEnabled {
            badges.update(
                dockEntries,
                visible: visibility.isVisible,
                runningPIDs: runningPIDs,
                visibilityMode: preferences.badgeVisibility,
                appearance: preferences.appearance
            )
        } else {
            badges.hide()
        }
    }

    func showAbout() { showSettings(tab: .about) }
    func restoreDefaults() { preferences = AppPreferences() }
    private func setMessage(_ value: String) { if message != value { message = value } }

    private func markUnminimizedInCache(pid: pid_t, element: AXUIElement) {
        let now = Date()
        if let cached = windowCache.windows(pid: pid, at: now) {
            windowCache.record(
                pid: pid,
                windows: cached.map { record in
                    CFEqual(record.element, element)
                        ? WindowRecord(
                            element: record.element,
                            title: record.title,
                            minimized: false,
                            isMain: true,
                            pid: record.pid,
                            isFullScreen: record.isFullScreen,
                            canMinimize: record.canMinimize
                        )
                        : WindowRecord(
                            element: record.element,
                            title: record.title,
                            minimized: record.minimized,
                            isMain: false,
                            pid: record.pid,
                            isFullScreen: record.isFullScreen,
                            canMinimize: record.canMinimize
                        )
                },
                at: now
            )
        }
    }

    private func markMinimizedInCache(pid: pid_t, element: AXUIElement) {
        let now = Date()
        if let cached = windowCache.windows(pid: pid, at: now) {
            windowCache.record(
                pid: pid,
                windows: cached.map { record in
                    CFEqual(record.element, element)
                        ? WindowRecord(
                            element: record.element,
                            title: record.title,
                            minimized: true,
                            isMain: false,
                            pid: record.pid,
                            isFullScreen: record.isFullScreen,
                            canMinimize: record.canMinimize
                        )
                        : record
                },
                at: now
            )
        }
        dockEntries = dockEntries.map { entry in
            let combined = entry.pids.compactMap { windowCache.windows(pid: $0, at: now) }
            let windows: [WindowRecord]? = combined.isEmpty ? entry.windows : combined.flatMap { $0 }
            return DockEntry(pid: entry.pid, pids: entry.pids, name: entry.name, url: entry.url, frame: entry.frame, windows: windows)
        }
    }

    func showWindows(_ entry: DockEntry, at point: CGPoint) {
        guard !menuOpen, preferences.enabled, preferences.windowSelectionEnabled else { return }
        let fresh = entry.pids.compactMap { AX.windows(pid: $0) }.flatMap { $0 }
        let windows = !fresh.isEmpty ? fresh : (entry.windows ?? [])
        guard !windows.isEmpty else { return }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let isActive = frontPID.map { entry.pids.contains($0) } ?? false
        switch preferences.clickAction(windows: windows, isAppActive: isActive) {
        case .minimizeSingleWindow:
            let target = windows[0]
            let targetPID = target.pid != 0 ? target.pid : entry.pid
            if WindowActivator.minimize(window: target) {
                markMinimizedInCache(pid: targetPID, element: target.element)
                renderCurrentState()
            }
            inventoryRevision += 1
            nextInventoryPoll = .distantPast
            refresh(force: true)
            return
        case .passThrough:
            _ = WindowActivator.activate(pid: entry.pid, window: windows[0])
            refresh(force: true)
            return
        case .openPicker:
            break
        }

        clicks.entries = []
        menuOpen = true

        picker.onChoose = { [weak self] window in
            guard let self else { return }
            let targetPID = window.pid != 0 ? window.pid : entry.pid
            if WindowActivator.activate(pid: targetPID, window: window) {
                self.markUnminimizedInCache(pid: targetPID, element: window.element)
            } else {
                self.message = "该窗口已关闭或应用暂时没有响应"
            }
            self.inventoryRevision += 1
            self.nextInventoryPoll = .distantPast
        }

        picker.onActivateAll = { [weak self] allWindows in
            guard let self else { return }
            WindowActivator.activateAll(pid: entry.pid, windows: allWindows)
            let now = Date()
            for pid in entry.pids {
                if let cached = self.windowCache.windows(pid: pid, at: now) {
                    self.windowCache.record(
                        pid: pid,
                        windows: cached.map {
                            WindowRecord(element: $0.element, title: $0.title, minimized: false, isMain: $0.isMain, pid: $0.pid)
                        },
                        at: now
                    )
                }
            }
            self.inventoryRevision += 1
            self.nextInventoryPoll = .distantPast
        }

        picker.onToggleMinimize = { [weak self] window in
            guard let self else { return }
            let targetPID = window.pid != 0 ? window.pid : entry.pid
            _ = WindowActivator.toggleMinimize(pid: targetPID, window: window)
            self.inventoryRevision += 1
            self.nextInventoryPoll = .distantPast
            self.refresh(force: true)
        }

        picker.onCloseWindow = { [weak self] window in
            guard let self else { return }
            _ = WindowActivator.close(window: window)
            self.inventoryRevision += 1
            self.nextInventoryPoll = .distantPast
            self.refresh(force: true)
        }

        picker.present(name: entry.name, appURL: entry.url, windows: windows, icon: entry.frame, at: point)
    }
}
