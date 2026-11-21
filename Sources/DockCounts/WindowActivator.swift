import AppKit
import ApplicationServices

/// The same activation path is used by menu actions and the real-window integration test.
enum WindowActivator {
    @discardableResult
    static func activate(pid: pid_t, window: WindowRecord) -> Bool {
        let targetPID = window.pid != 0 ? window.pid : pid
        let unminimize = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if let app = NSRunningApplication(processIdentifier: targetPID) {
            app.unhide()
            app.activate()
        }
        let raise = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)

        // Minimized restore animations can swallow the immediate raise/focus request;
        // re-assert focus briefly after unminimizing.
        if window.minimized {
            let element = window.element
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NSRunningApplication(processIdentifier: targetPID)?.activate()
                _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
        }
        return raise == .success || unminimize == .success
    }

    static func activateAll(pid: pid_t, windows: [WindowRecord]) {
        let pids = Set(windows.map { $0.pid != 0 ? $0.pid : pid })
        for targetPID in pids {
            if let app = NSRunningApplication(processIdentifier: targetPID) {
                app.unhide()
                app.activate()
            }
        }
        for window in windows.reversed() {
            if window.minimized {
                _ = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
        if let main = windows.first(where: \.isMain) ?? windows.first {
            _ = AXUIElementPerformAction(main.element, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(main.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    @discardableResult
    static func minimize(window: WindowRecord) -> Bool {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    @discardableResult
    static func toggleMinimize(pid: pid_t, window: WindowRecord) -> Bool {
        if window.minimized {
            return activate(pid: pid, window: window)
        }
        return minimize(window: window)
    }

    @discardableResult
    static func close(window: WindowRecord) -> Bool {
        guard let closeButton = AX.value(window.element, kAXCloseButtonAttribute),
              CFGetTypeID(closeButton) == AXUIElementGetTypeID() else {
            return false
        }
        return AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString) == .success
    }
}
