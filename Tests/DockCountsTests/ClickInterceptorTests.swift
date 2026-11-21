import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class ClickInterceptorTests: XCTestCase {
    private let proxy: CGEventTapProxy? = nil
    private func event(_ type: CGEventType, _ x: CGFloat = 30, _ y: CGFloat = 70) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    }
    private func makeInterceptor(total: Int = 1) -> ClickInterceptor {
        let interceptor = ClickInterceptor()
        let windows = (0..<total).map { WindowRecord(element: AXUIElementCreateApplication(1), title: "Test \($0)", minimized: false) }
        let entry = DockEntry(pid: 1, name: "Test", url: URL(fileURLWithPath: "/Test.app"), frame: CGRect(x: 10, y: 50, width: 40, height: 40), windows: windows)
        interceptor.entries = [entry]
        interceptor.hitTest = { point, entries in entries.first { $0.frame.contains(point) && ($0.counts?.total ?? 0) > 0 } }
        return interceptor
    }
    func testClickConsumesBothEventsAndOpensCorrectApplicationOnce() {
        let interceptor = makeInterceptor()
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
        let interceptor = makeInterceptor()
        for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift] {
            let down = event(.leftMouseDown); down.flags = flag
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
        let interceptor = makeInterceptor()
        var replayed: [CGEventType] = []
        interceptor.replay = { event, _ in replayed.append(event.type) }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDragged, event(.leftMouseDragged, 32, 71)))
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDragged, event(.leftMouseDragged, 45, 70)) != nil)
        XCTAssertEqual(replayed, [.leftMouseDown])
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp, 45, 70)) != nil)
    }
    func testReleaseOutsideIconRestoresOriginalSequence() {
        let interceptor = makeInterceptor()
        var replayed = false
        interceptor.replay = { _, _ in replayed = true }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp, 70, 70)) != nil)
        XCTAssertTrue(replayed)
    }
    func testOccludedOrHiddenDockDoesNotIntercept() {
        let interceptor = makeInterceptor()
        interceptor.hitTest = { _, _ in nil }
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
    }
    func testRightClickObservationDoesNotConsumeTheEvent() {
        let interceptor = makeInterceptor()
        let observed = expectation(description: "outside-click observer")
        interceptor.onPointerDown = { point in
            XCTAssertEqual(point, CGPoint(x: 30, y: 70))
            observed.fulfill()
        }
        let right = event(.rightMouseDown)
        XCTAssertTrue(interceptor.handle(proxy, .rightMouseDown, right) != nil)
        wait(for: [observed], timeout: 1)
    }

    func testSingleWindowOptionPassesBothEventsToDockWithoutOpeningPicker() {
        let interceptor = makeInterceptor(total: 1)
        var preferences = AppPreferences(); preferences.selectSingleWindow = false
        interceptor.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
    }
    func testDisablingPickerDoesNotConsumeClickEvenWhenBadgesRemainEnabled() {
        let interceptor = makeInterceptor(total: 3)
        var preferences = AppPreferences(); preferences.windowSelectionEnabled = false
        XCTAssertTrue(preferences.badgesEnabled)
        interceptor.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)) != nil)
        XCTAssertTrue(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)) != nil)
    }
    func testMultiWindowPickerStillWorksWithSingleWindowOptionOffAndBadgesOff() {
        let interceptor = makeInterceptor(total: 3)
        var preferences = AppPreferences(); preferences.selectSingleWindow = false; preferences.badgesEnabled = false
        interceptor.shouldIntercept = { preferences.selectsWindow(total: $0.counts?.total ?? 0) }
        let opened = expectation(description: "multi-window selection")
        interceptor.onClick = { _, _ in opened.fulfill() }
        XCTAssertNil(interceptor.handle(proxy, .leftMouseDown, event(.leftMouseDown)))
        XCTAssertNil(interceptor.handle(proxy, .leftMouseUp, event(.leftMouseUp)))
        wait(for: [opened], timeout: 1)
    }

}
