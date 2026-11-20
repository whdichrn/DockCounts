import XCTest
@testable import DockCounts
final class ModelsTests: XCTestCase {
    func testCountsIncludeMinimizedInTotal() {
        XCTAssertEqual(WindowCounts(minimized: 2, total: 5).label, "5·2")
        XCTAssertEqual(WindowCounts(minimized: 0, total: 1).label, "1·0")
    }
    func testAccessibilityToAppKitCoordinatesAcrossDisplays() {
        XCTAssertEqual(Geometry.appKitRect(CGRect(x: -800, y: -100, width: 50, height: 40), primaryHeight: 900), CGRect(x: -800, y: 960, width: 50, height: 40))
        XCTAssertEqual(Geometry.appKitRect(CGRect(x: 100, y: 850, width: 40, height: 40), primaryHeight: 900).minY, 10)
    }
    func testHiddenDockIsNotVisible() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertFalse(Geometry.isVisible(CGRect(x: -45, y: 300, width: 50, height: 50), screens: screens))
        XCTAssertTrue(Geometry.isVisible(CGRect(x: 0, y: 300, width: 50, height: 50), screens: screens))
    }
}
