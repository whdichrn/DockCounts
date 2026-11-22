import AppKit
import ApplicationServices

struct WindowRecord: Equatable {
    let element: AXUIElement
    let title: String
    let minimized: Bool
    let isMain: Bool
    let pid: pid_t
    let isFullScreen: Bool
    let canMinimize: Bool

    init(
        element: AXUIElement,
        title: String,
        minimized: Bool,
        isMain: Bool = false,
        pid: pid_t = 0,
        isFullScreen: Bool = false,
        canMinimize: Bool = true
    ) {
        self.element = element
        self.title = title
        self.minimized = minimized
        self.isMain = isMain
        self.pid = pid
        self.isFullScreen = isFullScreen
        self.canMinimize = canMinimize
    }

    static func == (lhs: WindowRecord, rhs: WindowRecord) -> Bool {
        CFEqual(lhs.element, rhs.element)
            && lhs.title == rhs.title
            && lhs.minimized == rhs.minimized
            && lhs.isMain == rhs.isMain
            && lhs.pid == rhs.pid
            && lhs.isFullScreen == rhs.isFullScreen
            && lhs.canMinimize == rhs.canMinimize
    }
}

struct DockEntry {
    let pid: pid_t
    let pids: [pid_t]
    let name: String
    let url: URL
    let frame: CGRect // Accessibility coordinates, origin at primary screen's top left.
    let windows: [WindowRecord]?

    init(pid: pid_t, pids: [pid_t]? = nil, name: String, url: URL, frame: CGRect, windows: [WindowRecord]?) {
        self.pid = pid
        self.pids = (pids?.isEmpty == false) ? pids! : [pid]
        self.name = name
        self.url = url
        self.frame = frame
        self.windows = windows
    }

    var counts: WindowCounts? {
        windows.map { WindowCounts(minimized: $0.filter(\.minimized).count, total: $0.count) }
    }
}

struct WindowCounts: Equatable {
    let minimized: Int
    let total: Int
    var label: String { minimized > 0 ? "\(total)↓\(minimized)" : "\(total)" }
}

enum Geometry {
    static func appKitRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    static func isVisible(_ rect: CGRect, screens: [CGRect]) -> Bool {
        rect.width > 4 && rect.height > 4 && screens.contains {
            $0.intersection(rect).width >= rect.width * 0.7 && $0.intersection(rect).height >= rect.height * 0.7
        }
    }
}

enum DockRefreshPolicy {
    static func geometryInterval(pointer: CGPoint, tiles: [CGRect]) -> TimeInterval {
        tiles.contains { $0.insetBy(dx: -70, dy: -70).contains(pointer) } ? 1.0 / 30.0 : 0.25
    }
}

enum AX {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    static func string(_ element: AXUIElement, _ key: String) -> String? {
        value(element, key) as? String
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func windows(pid: pid_t) -> [WindowRecord]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let elements = value(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        let mainWindow = value(app, kAXMainWindowAttribute).flatMap { ref -> AXUIElement? in
            CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil
        }
        return elements.compactMap { element in
            guard string(element, kAXRoleAttribute) == kAXWindowRole,
                  [kAXStandardWindowSubrole, kAXDialogSubrole].contains(string(element, kAXSubroleAttribute) ?? "") else {
                return nil
            }
            let minimized = value(element, kAXMinimizedAttribute) as? Bool ?? false
            // Filter ghost 0x0 or 1x1 hidden windows while keeping minimized windows intact.
            if !minimized, let rect = frame(element), rect.width < 2 || rect.height < 2 {
                return nil
            }
            let title = string(element, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.t("未命名窗口", "Untitled Window")
            let isMainAttr = value(element, kAXMainAttribute) as? Bool ?? false
            let isMain = isMainAttr || (mainWindow.map { CFEqual($0, element) } ?? false)
            let isFullScreen = (value(element, "AXFullScreen") as? Bool) ?? false
            let minimizeButton = value(element, kAXMinimizeButtonAttribute).flatMap { ref -> AXUIElement? in
                CFGetTypeID(ref) == AXUIElementGetTypeID() ? (ref as! AXUIElement) : nil
            }
            let canMinimize: Bool
            if let minimizeButton {
                canMinimize = (value(minimizeButton, kAXEnabledAttribute) as? Bool) ?? true
            } else {
                var settable = DarwinBoolean(false)
                let status = AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable)
                canMinimize = status == .success ? settable.boolValue : true
            }
            return WindowRecord(
                element: element,
                title: title,
                minimized: minimized,
                isMain: isMain,
                pid: pid,
                isFullScreen: isFullScreen,
                canMinimize: canMinimize
            )
        }
    }

    struct DockSnapshot {
        let pid: pid_t
        let frame: CGRect
        let entries: [DockEntry]
        let itemCount: Int
        let anchorFrames: [CGRect?]
    }

    static func dockSnapshot(
        applicationsByURL: [URL: [pid_t]],
        dockPID: pid_t? = nil,
        previous: DockSnapshot? = nil,
        refreshItems: Bool = true,
        windowProvider: ([pid_t]) -> [WindowRecord]? = { pids in
            var combined: [WindowRecord] = []
            var anySuccess = false
            for pid in pids {
                if let list = AX.windows(pid: pid) {
                    anySuccess = true
                    combined.append(contentsOf: list)
                }
            }
            return anySuccess ? combined : nil
        }
    ) -> DockSnapshot? {
        guard let pid = dockPID ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return nil
        }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.04)
        guard let roots = value(root, kAXChildrenAttribute) as? [AXUIElement],
              let list = roots.first(where: { string($0, kAXRoleAttribute) == kAXListRole }),
              let frame = frame(list),
              let items = value(list, kAXChildrenAttribute) as? [AXUIElement] else { return nil }

        let anchorFrames = items.isEmpty ? [] : Set([0, items.count / 2, items.count - 1]).sorted().map { self.frame(items[$0]) }
        if !refreshItems, let previous, previous.pid == pid,
           previous.frame == frame, previous.itemCount == items.count, previous.anchorFrames == anchorFrames {
            return previous
        }

        let entries: [DockEntry] = items.compactMap { item in
            guard string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
                  let url = value(item, kAXURLAttribute) as? URL,
                  let pids = applicationsByURL[url.standardizedFileURL], !pids.isEmpty,
                  let itemFrame = self.frame(item) else { return nil }
            return DockEntry(
                pid: pids[0],
                pids: pids,
                name: string(item, kAXTitleAttribute) ?? L10n.t("应用", "App"),
                url: url.standardizedFileURL,
                frame: itemFrame,
                windows: windowProvider(pids)
            )
        }
        return DockSnapshot(pid: pid, frame: frame, entries: entries, itemCount: items.count, anchorFrames: anchorFrames)
    }

    static func dockSnapshot(
        applications: [URL: pid_t],
        dockPID: pid_t? = nil,
        previous: DockSnapshot? = nil,
        refreshItems: Bool = true,
        windowProvider: (pid_t) -> [WindowRecord]? = { AX.windows(pid: $0) }
    ) -> DockSnapshot? {
        let grouped = applications.mapValues { [$0] }
        return dockSnapshot(
            applicationsByURL: grouped,
            dockPID: dockPID,
            previous: previous,
            refreshItems: refreshItems,
            windowProvider: { pids in
                guard let first = pids.first else { return nil }
                return windowProvider(first)
            }
        )
    }

    static func dockEntries(applications: [URL: pid_t], windowProvider: (pid_t) -> [WindowRecord]? = { AX.windows(pid: $0) }) -> [DockEntry] {
        dockSnapshot(applications: applications, windowProvider: windowProvider)?.entries ?? []
    }

    static func dockEvidence(_ snapshot: DockSnapshot, screenFrames: [CGRect]) -> DockEvidence {
        guard snapshot.frame.width.isFinite, snapshot.frame.height.isFinite,
              snapshot.frame.width > 1, snapshot.frame.height > 1 else { return .unknown }
        guard screenFrames.contains(where: { $0.intersection(snapshot.frame).width > 2 && $0.intersection(snapshot.frame).height > 2 }) else {
            return .hidden
        }
        let candidates = snapshot.entries.filter { entry in
            screenFrames.contains { $0.contains(CGPoint(x: entry.frame.midX, y: entry.frame.midY)) }
        }
        guard !candidates.isEmpty else { return .unknown }
        let indices = Set([0, candidates.count / 2, candidates.count - 1])
        for index in indices {
            let frame = candidates[index].frame
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
        guard pid == ownPID || running?.bundleIdentifier == "io.github.whdichrn.DockCounts" else { return nil }
        var ancestor = hit
        for _ in 0..<5 {
            if string(ancestor, kAXIdentifierAttribute) == "io.github.whdichrn.DockCounts.badge" {
                guard let dockPID = expectedDockPID ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
                    return nil
                }
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
        guard let item = dockItem(at: point),
              string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = value(item, kAXURLAttribute) as? URL,
              let entry = entries.first(where: { $0.url == url.standardizedFileURL && ($0.counts?.total ?? 0) > 0 }),
              let frame = frame(item) else { return nil }
        return DockEntry(pid: entry.pid, pids: entry.pids, name: entry.name, url: entry.url, frame: frame, windows: entry.windows)
    }

    /// Non-blocking hit test for real-time CGEventTap callbacks.
    /// Uses in-memory tile geometry + fast local WindowServer Z-order check instead of cross-process AX IPC.
    static func fastClickedEntry(at point: CGPoint, entries: [DockEntry], dockPID: pid_t? = nil) -> DockEntry? {
        guard let entry = entries.first(where: { $0.frame.contains(point) }) else { return nil }
        let resolvedDockPID = dockPID ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        guard let resolvedDockPID,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              !windowList.isEmpty else {
            return entry
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        for info in windowList {
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            if ownerPID == ownPID { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha <= 0.01 { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer < 0 { continue }
            let ownerName = info[kCGWindowOwnerName as String] as? String
            if ownerName == "Window Server" { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point) else {
                continue
            }
            if ownerPID == resolvedDockPID {
                // Dock bar lives at dockLevel (20); higher layers belong to Dock context menus/overlays.
                return layer <= dockLevel ? entry : nil
            }
            return nil
        }
        return entry
    }

    static func cgWindowSummary(pids: Set<pid_t>) -> (globalCount: Int, onScreenCount: Int) {
        guard !pids.isEmpty else { return (0, 0) }
        let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenIDs = Set(onScreen.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
        var globalCount = 0
        var onScreenCount = 0
        for info in all {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pids.contains(ownerPID),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0.01,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 50,
                  bounds.height >= 50 else {
                continue
            }
            globalCount += 1
            if let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
               onScreenIDs.contains(windowNumber) {
                onScreenCount += 1
            }
        }
        return (globalCount, onScreenCount)
    }

    static func pressDockItem(for bundleURL: URL, dockPID: pid_t? = nil) -> Bool {
        guard let pid = dockPID ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return false
        }
        let targetURL = bundleURL.standardizedFileURL
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.08)
        guard let roots = value(root, kAXChildrenAttribute) as? [AXUIElement],
              let list = roots.first(where: { string($0, kAXRoleAttribute) == kAXListRole }),
              let items = value(list, kAXChildrenAttribute) as? [AXUIElement] else {
            return false
        }
        for item in items {
            guard string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
                  let url = value(item, kAXURLAttribute) as? URL,
                  url.standardizedFileURL == targetURL else {
                continue
            }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
        return false
    }
}
