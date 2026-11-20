import AppKit
import ApplicationServices

/// The same activation path is used by menu actions and the real-window integration test.
enum WindowActivator {
    @discardableResult
    static func activate(pid: pid_t, window: WindowRecord) -> Bool {
        let unminimize = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.unhide()
            app.activate()
        }
        let raise = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        return raise == .success || unminimize == .success
    }
}
