import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class AppSwitchEnhancerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 50_000)

    func testCmdTabAndCmdShiftTabTriggerOnCommandReleaseAndConsumeOnce() {
        var tracker = CmdTabTracker()
        tracker.handleKeyDown(keyCode: 48, flags: .maskCommand, at: base)
        XCTAssertTrue(tracker.isSessionActive)
        XCTAssertFalse(tracker.handleFlagsChanged(flags: [.maskCommand, .maskShift], at: base.addingTimeInterval(0.5)))
        XCTAssertTrue(tracker.isSessionActive)
        XCTAssertTrue(tracker.handleFlagsChanged(flags: [], at: base.addingTimeInterval(3.5)))
        XCTAssertFalse(tracker.isSessionActive)

        XCTAssertTrue(tracker.consumePendingSwitch(at: base.addingTimeInterval(3.6)))
        XCTAssertFalse(tracker.consumePendingSwitch(at: base.addingTimeInterval(3.7)), "Must consume only once")

        tracker.handleKeyDown(keyCode: 48, flags: [.maskCommand, .maskShift], at: base.addingTimeInterval(5))
        XCTAssertTrue(tracker.isSessionActive)
        XCTAssertTrue(tracker.handleFlagsChanged(flags: [], at: base.addingTimeInterval(5.2)))
        XCTAssertTrue(tracker.consumePendingSwitch(at: base.addingTimeInterval(5.3)))
    }

    func testEscapeAndOptionHoldCancelSwitchEnhancement() {
        var tracker = CmdTabTracker()
        tracker.handleKeyDown(keyCode: 48, flags: .maskCommand, at: base)
        tracker.handleKeyDown(keyCode: 53, flags: .maskCommand, at: base.addingTimeInterval(0.1))
        XCTAssertFalse(tracker.isSessionActive)
        XCTAssertFalse(tracker.handleFlagsChanged(flags: [], at: base.addingTimeInterval(0.2)))
        XCTAssertFalse(tracker.consumePendingSwitch(at: base.addingTimeInterval(0.3)))

        tracker.handleKeyDown(keyCode: 48, flags: .maskCommand, at: base.addingTimeInterval(1))
        XCTAssertFalse(tracker.handleFlagsChanged(flags: .maskAlternate, at: base.addingTimeInterval(1.2)))
        XCTAssertFalse(tracker.consumePendingSwitch(at: base.addingTimeInterval(1.3)))
    }

    func testMouseClickInSwitcherHUDAndExpirationWindow() {
        var tracker = CmdTabTracker()
        tracker.handleKeyDown(keyCode: 48, flags: .maskCommand, at: base)
        XCTAssertTrue(tracker.handleMouseUp(at: base.addingTimeInterval(0.4)))
        XCTAssertFalse(tracker.isSessionActive)
        XCTAssertFalse(tracker.consumePendingSwitch(at: base.addingTimeInterval(1.5)), "Expired pending switch must not fire")
    }

    func testCmdTabActionHandlesMinimizedEmptySpaceSwitchAndOnScreenGuards() {
        let el = AXUIElementCreateApplication(1)
        let min1 = WindowRecord(element: el, title: "Min 1", minimized: true, isMain: false, pid: 10)
        let min2 = WindowRecord(element: el, title: "Min 2", minimized: true, isMain: false, pid: 10)
        let vis = WindowRecord(element: el, title: "Visible", minimized: false, isMain: true, pid: 10)

        var prefs = AppPreferences()

        // Single minimized -> restoreSingle
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [min1], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: true),
            .restoreSingle(min1)
        )

        // Multiple minimized -> showPicker by default
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [min1, min2], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: true),
            .showPicker([min1, min2])
        )

        // Multiple minimized -> restoreRecent restores first
        prefs.cmdTabMultiMinimizedBehavior = .restoreRecent
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [min1, min2], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: true),
            .restoreFirst(min1)
        )

        // Mixed (one minimized, one visible) -> none
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [min1, vis], onScreenWindowCount: 1, spaceChangedRecently: false, isRegularApp: true),
            .none
        )

        // On-screen window present -> none (even if AX returns empty)
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [], onScreenWindowCount: 1, spaceChangedRecently: false, isRegularApp: true),
            .none
        )

        // Space just changed via workspaces-auto-swoosh -> MUST NOT trigger empty reopen or minimized restore
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [], onScreenWindowCount: 0, spaceChangedRecently: true, isRegularApp: true),
            .none
        )
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [min1], onScreenWindowCount: 0, spaceChangedRecently: true, isRegularApp: true),
            .none
        )

        // Empty AX + no on-screen window + no space change -> reopenApp (even if app holds hidden closed window in memory)
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: true),
            .reopenApp
        )

        // Non-regular app -> none
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: false),
            .none
        )

        // Disabled toggles -> none
        prefs.cmdTabRestoreMinimized = false
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [min1], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: true),
            .none
        )
        prefs.cmdTabReopenEmptyApp = false
        XCTAssertEqual(
            prefs.cmdTabAction(windows: [], onScreenWindowCount: 0, spaceChangedRecently: false, isRegularApp: true),
            .none
        )
    }
}
