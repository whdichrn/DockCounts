import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class ClickInterceptorTests: XCTestCase {
    private let proxy: CGEventTapProxy? = nil

    private func event(_ type: CGEventType, _ x: CGFloat = 30, _ y: CGFloat = 70) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    }

    private func makeInterceptor(total: Int = 2, minimized: Int = 0) -> ClickInterceptor {
        let interceptor = ClickInterceptor()
        let windows = (0..<total).map {
            WindowRecord(element: AXUIElementCreateApplication(1), title: "Test \($0)", minimized: $0 < minimized)
        }
        let entry = DockEntry(
            pid: 1,
            name: "Test",
            url: URL(fileURLWithPath: "/Test.app"),
            frame: CGRect(x: 10, y: 50, width: 40, height: 40),
            windows: windows
        )
        interceptor.entries = [entry]
        interceptor.hitTest = { point, entries in
            entries.first { $0.frame.contains(point) && ($0.counts?.total ?? 0) > 0 }
        }
        return interceptor
    }

    func testClickConsumesBothEventsAndOpensCorrectApplicationOnce() {
        let interceptor = makeInterceptor(total: 2)
        let opened = expectation(description: "menu callback")
        interceptor.onClick = { entry, point in
            XCTAssertEqual(entry.name, "Test")
            XCTAssertEqual(point, CGPoint(x: 30, y: 70))
            opened.fulfill()
        }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertNil(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)))
        wait(for: [opened], timeout: 1)
    }

    func testModifiedAndUnrelatedClicksPassThrough() {
        let interceptor = makeInterceptor(total: 2)
        for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift] {
            let down = event(.leftMouseDown)
            down.flags = flag
            XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, down) != nil)
            XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
        }
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown, 900, 600)) != nil)
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp, 900, 600)) != nil)
    }

    func testZeroWindowApplicationRetainsDockBehavior() {
        let interceptor = makeInterceptor(total: 0)
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
    }

    func testDragReplaysDownBeforePassingDragAndRelease() {
        let interceptor = makeInterceptor(total: 2)
        var replayed: [CGEventType] = []
        interceptor.replay = { event, _ in replayed.append(event.type) }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDragged, event(.leftMouseDragged, 32, 71)))
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDragged, event(.leftMouseDragged, 45, 70)) != nil)
        XCTAssertEqual(replayed, [.leftMouseDown])
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp, 45, 70)) != nil)
    }

    func testReleaseOutsideIconRestoresOriginalSequence() {
        let interceptor = makeInterceptor(total: 2)
        var replayed = false
        interceptor.replay = { _, _ in replayed = true }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp, 70, 70)) != nil)
        XCTAssertTrue(replayed)
    }

    func testOccludedOrHiddenDockDoesNotIntercept() {
        let interceptor = makeInterceptor(total: 2)
        interceptor.hitTest = { _, _ in nil }
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
    }

    func testRightClickObservationDoesNotConsumeTheEvent() {
        let interceptor = makeInterceptor(total: 2)
        let observed = expectation(description: "outside-click observer")
        interceptor.onPointerDown = { point in
            XCTAssertEqual(point, CGPoint(x: 30, y: 70))
            observed.fulfill()
        }
        let right = event(.rightMouseDown)
        XCTAssertTrue(interceptor.handle(proxy, .rightMouseDown, right) != nil)
        wait(for: [observed], timeout: 1)
    }

    func testMultipleWindowsTriggerModePassesSingleWindowEvenIfMinimized() {
        let preferences = AppPreferences() // default .multipleWindows
        let singleNormal = makeInterceptor(total: 1, minimized: 0)
        singleNormal.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        XCTAssertTrue(singleNormal.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(singleNormal.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)

        let singleMinimized = makeInterceptor(total: 1, minimized: 1)
        singleMinimized.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        XCTAssertTrue(singleMinimized.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(singleMinimized.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
    }

    func testAnyWindowTriggerModeInterceptsSingleWindow() {
        var preferences = AppPreferences()
        preferences.triggerMode = .anyWindow
        let interceptor = makeInterceptor(total: 1)
        interceptor.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        let opened = expectation(description: "single-window selection")
        interceptor.onClick = { _, _ in opened.fulfill() }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertNil(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)))
        wait(for: [opened], timeout: 1)
    }

    func testActiveSingleWindowMinimizesWhileInactiveOrAlreadyMinimizedPassesThrough() {
        let preferences = AppPreferences() // multipleWindows + minimizeActiveSingleWindow
        let activeNormal = makeInterceptor(total: 1, minimized: 0)
        activeNormal.shouldIntercept = { entry in
            preferences.clickAction(windows: entry.windows ?? [], isAppActive: true) != .passThrough
        }
        let triggered = expectation(description: "active single window minimize interception")
        activeNormal.onClick = { _, _ in triggered.fulfill() }
        XCTAssertNil(activeNormal.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertNil(activeNormal.handle(proxy, .leftMouseUp, event(.leftMouseUp)))
        wait(for: [triggered], timeout: 1)

        let inactiveNormal = makeInterceptor(total: 1, minimized: 0)
        inactiveNormal.shouldIntercept = { entry in
            preferences.clickAction(windows: entry.windows ?? [], isAppActive: false) != .passThrough
        }
        XCTAssertTrue(inactiveNormal.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(inactiveNormal.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)

        let activeMinimized = makeInterceptor(total: 1, minimized: 1)
        activeMinimized.shouldIntercept = { entry in
            preferences.clickAction(windows: entry.windows ?? [], isAppActive: true) != .passThrough
        }
        XCTAssertTrue(activeMinimized.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(activeMinimized.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
    }

    func testDisablingPickerDoesNotConsumeClickEvenWhenBadgesRemainEnabled() {
        let interceptor = makeInterceptor(total: 3)
        var preferences = AppPreferences()
        preferences.windowSelectionEnabled = false
        XCTAssertTrue(preferences.badgesEnabled)
        interceptor.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
    }
}
