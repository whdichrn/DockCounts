import AppKit
import ApplicationServices
import OSLog

/// Missing AX replies are not evidence that Dock or an application's windows vanished.
struct WindowInventoryCache {
    private struct Sample { let windows: [WindowRecord]; let date: Date }
    private var samples: [pid_t: Sample] = [:]
    let lifetime: TimeInterval = 2
    mutating func record(pid: pid_t, windows: [WindowRecord], at date: Date) {
        samples[pid] = Sample(windows: windows, date: date)
    }
    func windows(pid: pid_t, at date: Date) -> [WindowRecord]? {
        guard let sample = samples[pid], date.timeIntervalSince(sample.date) <= lifetime else { return nil }
        return sample.windows
    }
    mutating func retain(_ pids: Set<pid_t>) { samples = samples.filter { pids.contains($0.key) } }
    mutating func reset() { samples.removeAll() }
}

enum DockEvidence: String { case visible, hidden, unknown }
enum DockPhase: String { case visible, moving, hidden, unknown }

struct DockVisibility {
    private var lastVisible: Date?
    private(set) var isVisible = false
    // A lost hit test during a transition gets a bounded grace period. A confirmed
    // off-screen Dock hides immediately and never leaves a floating counter behind.
    mutating func update(_ evidence: DockEvidence, at date: Date) -> Bool {
        switch evidence {
        case .visible: lastVisible = date; isVisible = true
        case .hidden: lastVisible = nil; isVisible = false
        case .unknown: isVisible = lastVisible.map { date.timeIntervalSince($0) < 0.14 } ?? false
        }
        return isVisible
    }
    mutating func reset() { lastVisible = nil; isVisible = false }
}

struct DockMotion {
    private var previous: [pid_t: CGRect] = [:]
    private var previousDockFrame: CGRect?
    private(set) var fastUntil = Date.distantPast
    mutating func wake(at date: Date) { fastUntil = max(fastUntil, date.addingTimeInterval(0.8)) }
    mutating func observe(entries: [DockEntry], dockFrame: CGRect, at date: Date) -> Bool {
        let next = Dictionary(entries.map { ($0.pid, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let changed = previous != next || previousDockFrame != dockFrame
        previous = next; previousDockFrame = dockFrame
        if changed { wake(at: date) }
        return changed
    }
    func interval(pointer: CGPoint, entries: [DockEntry], at date: Date) -> TimeInterval {
        date < fastUntil ? 1.0 / 30.0 : DockRefreshPolicy.geometryInterval(pointer: pointer, tiles: entries.map(\.frame))
    }
}

enum DockTrace {
    private static let enabled = ProcessInfo.processInfo.environment["DOCKCOUNTS_DIAGNOSTICS"] == "1"
    private static let logger = Logger(subsystem: "io.github.whdichrn.DockCounts", category: "DockTracking")
    static func event(_ message: String) {
        guard enabled else { return }
        logger.notice("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.systemUptime) \(message)\n".utf8))
    }
}

/// Public notifications are hints; Dock need not support every AX notification.
/// Independent geometry polling remains the fallback, including with a distant pointer.
final class DockEventMonitor {
    var onChange: (() -> Void)?
    var onApplicationsChange: (() -> Void)?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var observer: AXObserver?
    private(set) var dockPID: pid_t?
    func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            tokens.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if name == NSWorkspace.didLaunchApplicationNotification || name == NSWorkspace.didTerminateApplicationNotification { self?.onApplicationsChange?() }
                self?.onChange?()
            }))
        }
        let center = NotificationCenter.default
        tokens.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.onChange?() }))
        reconnect()
    }
    func reconnect() {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        guard pid != dockPID || observer == nil else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; dockPID = pid
        guard let pid, AXIsProcessTrusted() else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            Unmanaged<DockEventMonitor>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        let elements = [app] + AX.children(app)
        for element in elements {
            for name in [kAXMovedNotification, kAXResizedNotification, kAXLayoutChangedNotification] {
                _ = AXObserverAddNotification(created, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }
    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; dockPID = nil
    }
    deinit { stop() }
}
