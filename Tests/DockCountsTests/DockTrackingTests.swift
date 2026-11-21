import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class DockTrackingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)
    func testBriefLostHitKeepsBadgesButExtendedUncertaintyDoesNotLeaveThemFloating() {
        var gate = DockVisibility()
        XCTAssertFalse(gate.update(.unknown, at: start))
        XCTAssertTrue(gate.update(.visible, at: start))
        XCTAssertTrue(gate.update(.unknown, at: start.addingTimeInterval(0.08)))
        XCTAssertFalse(gate.update(.unknown, at: start.addingTimeInterval(0.16)))
        XCTAssertTrue(gate.update(.visible, at: start.addingTimeInterval(0.2)))
    }
    func testConfirmedHiddenDockBypassesGraceAndCannotBeRevivedByAnUnknownSample() {
        var gate = DockVisibility()
        XCTAssertTrue(gate.update(.visible, at: start))
        XCTAssertFalse(gate.update(.hidden, at: start.addingTimeInterval(0.01)))
        XCTAssertFalse(gate.update(.unknown, at: start.addingTimeInterval(0.02)))
        XCTAssertTrue(gate.update(.visible, at: start.addingTimeInterval(0.03)))
        gate.reset()
        XCTAssertFalse(gate.update(.unknown, at: start.addingTimeInterval(0.04)))
    }
    func testDesktopMovementStartsFastTrackingEvenWithADistantPointerAndSettlesBack() {
        var motion = DockMotion()
        let far = CGPoint(x: 1200, y: 20)
        let url = URL(fileURLWithPath: "/Applications/Test.app")
        let initial = DockEntry(pid: 1, name: "Test", url: url, frame: CGRect(x: 0, y: 200, width: 40, height: 40), windows: nil)
        let moved = DockEntry(pid: 1, name: "Test", url: url, frame: CGRect(x: 0, y: 240, width: 40, height: 40), windows: nil)
        let dock = CGRect(x: 0, y: 50, width: 50, height: 600)
        XCTAssertTrue(motion.observe(entries: [initial], dockFrame: dock, at: start))
        XCTAssertEqual(motion.interval(pointer: far, entries: [initial], at: start), 1.0 / 30)
        XCTAssertEqual(motion.interval(pointer: far, entries: [initial], at: start.addingTimeInterval(1)), 0.1)
        XCTAssertTrue(motion.observe(entries: [moved], dockFrame: dock, at: start.addingTimeInterval(1.1)))
        XCTAssertEqual(motion.interval(pointer: far, entries: [moved], at: start.addingTimeInterval(1.2)), 1.0 / 30)
        XCTAssertFalse(motion.observe(entries: [moved], dockFrame: dock, at: start.addingTimeInterval(1.3)))
        XCTAssertEqual(motion.interval(pointer: far, entries: [moved], at: start.addingTimeInterval(2)), 0.1)
        motion.wake(at: start.addingTimeInterval(3))
        XCTAssertEqual(motion.interval(pointer: far, entries: [moved], at: start.addingTimeInterval(3.1)), 1.0 / 30)
    }
    func testInventoryFailureGraceDoesNotConflateUnknownWithZeroOrKeepStaleWindowsForever() {
        var cache = WindowInventoryCache()
        let record = WindowRecord(element: AXUIElementCreateApplication(1), title: "Example", minimized: true)
        XCTAssertNil(cache.windows(pid: 1, at: start))
        cache.record(pid: 1, windows: [record], at: start)
        XCTAssertEqual(cache.windows(pid: 1, at: start.addingTimeInterval(1))?.count, 1)
        XCTAssertNil(cache.windows(pid: 1, at: start.addingTimeInterval(2.1)))
        cache.record(pid: 1, windows: [], at: start.addingTimeInterval(3))
        XCTAssertEqual(cache.windows(pid: 1, at: start.addingTimeInterval(3))?.count, 0)
        cache.retain([])
        XCTAssertNil(cache.windows(pid: 1, at: start.addingTimeInterval(3)))
    }
}
