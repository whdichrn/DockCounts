import AppKit
import ApplicationServices

struct CmdTabTracker {
    private(set) var isSessionActive = false
    private var pendingSwitchTime: Date?
    private var optionHeldAtRelease = false

    mutating func handleKeyDown(keyCode: Int64, flags: CGEventFlags, at now: Date) {
        if keyCode == 48, flags.contains(.maskCommand), flags.intersection([.maskControl, .maskAlternate]).isEmpty {
            isSessionActive = true
            pendingSwitchTime = nil
            optionHeldAtRelease = false
        } else if isSessionActive, keyCode == 53 {
            reset()
        }
    }

    /// Returns `true` when Command is released from an active switcher session without Option held.
    mutating func handleFlagsChanged(flags: CGEventFlags, at now: Date) -> Bool {
        guard isSessionActive else { return false }
        guard !flags.contains(.maskCommand) else { return false }
        isSessionActive = false
        optionHeldAtRelease = flags.contains(.maskAlternate)
        pendingSwitchTime = optionHeldAtRelease ? nil : now
        return !optionHeldAtRelease
    }

    mutating func handleMouseUp(at now: Date) -> Bool {
        guard isSessionActive else { return false }
        isSessionActive = false
        optionHeldAtRelease = false
        pendingSwitchTime = now
        return true
    }

    mutating func consumePendingSwitch(at now: Date, window: TimeInterval = 0.75) -> Bool {
        guard !optionHeldAtRelease,
              let timestamp = pendingSwitchTime,
              now.timeIntervalSince(timestamp) <= window else {
            return false
        }
        pendingSwitchTime = nil
        return true
    }

    mutating func reset() {
        isSessionActive = false
        pendingSwitchTime = nil
        optionHeldAtRelease = false
    }
}

final class AppSwitchEnhancer {
    var onCmdTabActivated: ((NSRunningApplication, Bool) -> Void)?

    private var tracker = CmdTabTracker()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var lastSpaceChangeAt = Date.distantPast
    private var fallbackWorkItem: DispatchWorkItem?
    private var evaluationWorkItem: DispatchWorkItem?
    private var lastReopenAt: [pid_t: Date] = [:]

    private static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.Spotlight"
    ]

    @discardableResult
    func start() -> Bool {
        let center = NSWorkspace.shared.notificationCenter
        if workspaceObserver == nil {
            workspaceObserver = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                guard self.tracker.consumePendingSwitch(at: Date()) else { return }
                self.fallbackWorkItem?.cancel()
                self.fallbackWorkItem = nil
                self.scheduleEvaluation(for: app)
            }
        }
        if spaceObserver == nil {
            spaceObserver = center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lastSpaceChangeAt = Date()
            }
        }

        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return CGEvent.tapIsEnabled(tap: tap)
        }

        let mask = [CGEventType.keyDown, .flagsChanged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            return Unmanaged<AppSwitchEnhancer>.fromOpaque(pointer).takeUnretainedValue().handleEvent(type, event)
        }

        let created = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        )
        guard let created else { return false }
        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func stop() {
        fallbackWorkItem?.cancel()
        fallbackWorkItem = nil
        evaluationWorkItem?.cancel()
        evaluationWorkItem = nil
        let center = NSWorkspace.shared.notificationCenter
        if let workspaceObserver {
            center.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let spaceObserver {
            center.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        lastSpaceChangeAt = .distantPast
        tracker.reset()
    }

    func canReopen(pid: pid_t, at now: Date = Date()) -> Bool {
        lastReopenAt = lastReopenAt.filter { now.timeIntervalSince($0.value) < 10 }
        if let last = lastReopenAt[pid], now.timeIntervalSince(last) < 1.5 {
            return false
        }
        lastReopenAt[pid] = now
        return true
    }

    private func handleEvent(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tracker.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let now = Date()
        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            tracker.handleKeyDown(keyCode: keyCode, flags: event.flags, at: now)
        case .flagsChanged:
            if tracker.handleFlagsChanged(flags: event.flags, at: now) {
                scheduleFallback()
            }
        case .leftMouseUp:
            if tracker.handleMouseUp(at: now) {
                scheduleFallback()
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func scheduleFallback() {
        fallbackWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.tracker.consumePendingSwitch(at: Date()),
                  let app = NSWorkspace.shared.frontmostApplication else {
                return
            }
            self.scheduleEvaluation(for: app)
        }
        fallbackWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func scheduleEvaluation(for app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        if let bundleID = app.bundleIdentifier, Self.excludedBundleIDs.contains(bundleID) {
            return
        }
        evaluationWorkItem?.cancel()
        let activationTime = Date()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let spaceChanged = self.lastSpaceChangeAt >= activationTime.addingTimeInterval(-0.05)
            self.onCmdTabActivated?(app, spaceChanged)
        }
        evaluationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }
}
