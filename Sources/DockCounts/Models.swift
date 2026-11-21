import AppKit
import ApplicationServices

struct WindowRecord {
    let element: AXUIElement
    let title: String
    let minimized: Bool
}
struct DockEntry {
    let pid: pid_t
    let name: String
    let url: URL
    let frame: CGRect // Accessibility coordinates, origin at primary screen's top left.
    let windows: [WindowRecord]?
    var counts: WindowCounts? { windows.map { WindowCounts(minimized: $0.filter(\.minimized).count, total: $0.count) } }
}
struct WindowCounts: Equatable {
    let minimized: Int
    let total: Int
    var label: String { "\(total)·\(minimized)" }
}
enum Geometry {
    static func appKitRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    static func isVisible(_ rect: CGRect, screens: [CGRect]) -> Bool {
        rect.width > 4 && rect.height > 4 && screens.contains { $0.intersection(rect).width >= rect.width * 0.7 && $0.intersection(rect).height >= rect.height * 0.7 }
    }
}
enum DockRefreshPolicy {
    static func geometryInterval(pointer: CGPoint, tiles: [CGRect]) -> TimeInterval {
        tiles.contains { $0.insetBy(dx: -70, dy: -70).contains(pointer) } ? 1.0 / 30.0 : 0.1
    }
}

enum AX {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func string(_ element: AXUIElement, _ key: String) -> String? { value(element, key) as? String }
    static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func windows(pid: pid_t) -> [WindowRecord]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let elements = value(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return elements.filter { element in
            string(element, kAXRoleAttribute) == kAXWindowRole && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(string(element, kAXSubroleAttribute) ?? "")
        }.map { element in
            WindowRecord(element: element, title: string(element, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? "未命名窗口", minimized: value(element, kAXMinimizedAttribute) as? Bool ?? false)
        }
    }
    struct DockSnapshot {
        let pid: pid_t
        let frame: CGRect
        let entries: [DockEntry]
        let itemCount: Int
        let anchorFrames: [CGRect?]
    }
    static func dockSnapshot(applications: [URL: pid_t], dockPID: pid_t? = nil, previous: DockSnapshot? = nil, refreshItems: Bool = true, windowProvider: (pid_t) -> [WindowRecord]? = { AX.windows(pid: $0) }) -> DockSnapshot? {
        guard let pid = dockPID ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.04)
        guard let roots = value(root, kAXChildrenAttribute) as? [AXUIElement],
              let list = roots.first(where: { string($0, kAXRoleAttribute) == kAXListRole }),
              let frame = frame(list),
              let items = value(list, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        // Probe both Dock bounds and icon anchors: Show Desktop can move items
        // within an unchanged list. A distant pointer must not delay this change
        // until the slower full inventory refresh.
        let anchorFrames = items.isEmpty ? [] : Set([0, items.count / 2, items.count - 1]).sorted().map { self.frame(items[$0]) }
        if !refreshItems, let previous, previous.pid == pid,
           previous.frame == frame, previous.itemCount == items.count, previous.anchorFrames == anchorFrames {
            return previous
        }
        let entries: [DockEntry] = items.compactMap { item in
            guard string(item, kAXSubroleAttribute) == "AXApplicationDockItem", let url = value(item, kAXURLAttribute) as? URL,
                  let pid = applications[url.standardizedFileURL], let frame = self.frame(item) else { return nil }
            return DockEntry(pid: pid, name: string(item, kAXTitleAttribute) ?? "应用", url: url.standardizedFileURL, frame: frame, windows: windowProvider(pid))
        }
        return DockSnapshot(pid: pid, frame: frame, entries: entries, itemCount: items.count, anchorFrames: anchorFrames)
    }
    static func dockEntries(applications: [URL: pid_t], windowProvider: (pid_t) -> [WindowRecord]? = { AX.windows(pid: $0) }) -> [DockEntry] {
        dockSnapshot(applications: applications, windowProvider: windowProvider)?.entries ?? []
    }
    static func dockEvidence(_ snapshot: DockSnapshot, screenFrames: [CGRect]) -> DockEvidence {
        guard snapshot.frame.width.isFinite, snapshot.frame.height.isFinite,
              snapshot.frame.width > 1, snapshot.frame.height > 1 else { return .unknown }
        // Require only an intersection: the visible part of a sliding Dock should
        // not cross the former arbitrary 70% threshold and pop counters in/out.
        guard screenFrames.contains(where: { $0.intersection(snapshot.frame).width > 2 && $0.intersection(snapshot.frame).height > 2 }) else { return .hidden }
        let candidates = snapshot.entries.filter { entry in
            screenFrames.contains { $0.contains(CGPoint(x: entry.frame.midX, y: entry.frame.midY)) }
        }
        guard !candidates.isEmpty else { return .unknown }
        let indices = Set([0, candidates.count / 2, candidates.count - 1])
        for index in indices {
            let frame = candidates[index].frame
            // Mission Control may expose a Dock-owned container rather than the
            // icon leaf. Ownership is sufficient for visibility, while click
            // interception below still requires a real application Dock item.
            if dockItem(at: CGPoint(x: frame.midX, y: frame.midY), expectedDockPID: snapshot.pid) != nil { return .visible }
        }
        return .unknown
    }
    static func dockItem(at point: CGPoint, expectedDockPID: pid_t? = nil) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.025)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        if pid == expectedDockPID { return hit }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let running = pid == ownPID ? nil : NSRunningApplication(processIdentifier: pid)
        if running?.bundleIdentifier == "com.apple.dock" { return hit }
        // AX hit testing can see our mouse-transparent badge. Only bypass our tagged
        // badge hierarchy; settings, menus and other applications must still occlude Dock.
        guard pid == ownPID || running?.bundleIdentifier == "io.github.whdichrn.DockCounts" else { return nil }
        var ancestor = hit
        for _ in 0..<5 {
            if string(ancestor, kAXIdentifierAttribute) == "io.github.whdichrn.DockCounts.badge" {
                guard let dockPID = expectedDockPID ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else { return nil }
                let root = AXUIElementCreateApplication(dockPID)
                AXUIElementSetMessagingTimeout(root, 0.025)
                var underlying: AXUIElement?
                guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &underlying) == .success else { return nil }
                return underlying
            }
            guard let parent = value(ancestor, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            ancestor = parent as! AXUIElement
        }
        return nil
    }
    static func dockIsAt(_ point: CGPoint) -> Bool { dockItem(at: point) != nil }
    static func clickedEntry(at point: CGPoint, entries: [DockEntry]) -> DockEntry? {
        guard let item = dockItem(at: point), string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = value(item, kAXURLAttribute) as? URL,
              let entry = entries.first(where: { $0.url == url.standardizedFileURL && ($0.counts?.total ?? 0) > 0 }),
              let frame = frame(item) else { return nil }
        return DockEntry(pid: entry.pid, name: entry.name, url: entry.url, frame: frame, windows: entry.windows)
    }
}
