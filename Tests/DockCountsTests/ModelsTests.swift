import XCTest
import ApplicationServices
@testable import DockCounts

final class ModelsTests: XCTestCase {
    func testCountsLabelUsesCompactSemanticFormatting() {
        XCTAssertEqual(WindowCounts(minimized: 0, total: 1).label, "1")
        XCTAssertEqual(WindowCounts(minimized: 0, total: 3).label, "3")
        XCTAssertEqual(WindowCounts(minimized: 2, total: 5).label, "5↓2")
    }

    func testDockEntryAggregatesMultiplePIDs() {
        let e1 = AXUIElementCreateApplication(101)
        let e2 = AXUIElementCreateApplication(102)
        let w1 = WindowRecord(element: e1, title: "Main", minimized: false, isMain: true, pid: 101)
        let w2 = WindowRecord(element: e2, title: "Draft", minimized: true, isMain: false, pid: 102)
        let entry = DockEntry(
            pid: 101,
            pids: [101, 102],
            name: "Multi",
            url: URL(fileURLWithPath: "/Applications/Multi.app"),
            frame: CGRect(x: 0, y: 0, width: 48, height: 48),
            windows: [w1, w2]
        )
        XCTAssertEqual(entry.pids, [101, 102])
        XCTAssertEqual(entry.counts, WindowCounts(minimized: 1, total: 2))
    }

    func testAccessibilityToAppKitCoordinatesAcrossDisplays() {
        XCTAssertEqual(
            Geometry.appKitRect(CGRect(x: -800, y: -100, width: 50, height: 40), primaryHeight: 900),
            CGRect(x: -800, y: 960, width: 50, height: 40)
        )
        XCTAssertEqual(
            Geometry.appKitRect(CGRect(x: 100, y: 850, width: 40, height: 40), primaryHeight: 900).minY,
            10
        )
    }

    func testHiddenDockIsNotVisible() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertFalse(Geometry.isVisible(CGRect(x: -45, y: 300, width: 50, height: 50), screens: screens))
        XCTAssertTrue(Geometry.isVisible(CGRect(x: 0, y: 300, width: 50, height: 50), screens: screens))
    }
}
