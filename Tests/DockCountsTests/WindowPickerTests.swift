import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts
final class WindowPickerTests: XCTestCase {
    private func windows(_ count: Int) -> [WindowRecord] {
        (0..<count).map { WindowRecord(element: AXUIElementCreateApplication(1), title: "Window \($0)", minimized: $0 == 1) }
    }
    func testKeyboardSelectionWrapsAndRetainsWindowIdentity() {
        let records = windows(3)
        let state = WindowPickerState(windows: records)
        XCTAssertNil(state.selectedWindow, "Opening a menu should not paint a selection before user input")
        state.move(by: -1)
        XCTAssertEqual(state.selectedWindow?.title, "Window 2")
        state.move(by: 1)
        XCTAssertEqual(state.selectedWindow?.title, "Window 0")
        state.select(1)
        XCTAssertTrue(state.selectedWindow!.minimized)
        XCTAssertTrue(CFEqual(state.selectedWindow!.element, records[1].element))
        state.select(20)
        XCTAssertEqual(state.selectedIndex, 1)
    }
    func testEmptyPickerHasNoSelectableWindow() {
        let state = WindowPickerState(windows: [])
        state.move(by: 1); state.select(0)
        XCTAssertNil(state.selectedWindow)
    }
    func testPickerStaysOnDisplayForAllDockEdges() {
        let visible = CGRect(x: -1200, y: 20, width: 1150, height: 780)
        for edge in ["left", "right", "bottom"] {
            let rect = PickerPlacement.frame(icon: CGRect(x: -1200, y: 15, width: 40, height: 40), point: CGPoint(x: -1180, y: 25), size: CGSize(width: 340, height: 420), visible: visible, edge: edge)
            XCTAssertTrue(visible.contains(rect), "\(edge): \(rect)")
        }
    }
    func testPickerFitsSmallScreens() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 250)
        let rect = PickerPlacement.frame(icon: .zero, point: .zero, size: CGSize(width: 340, height: 420), visible: visible, edge: "bottom")
        XCTAssertTrue(visible.contains(rect))
    }
    func testPointerExitClearsHoverButNotKeyboardSelection() {
        let state = WindowPickerState(windows: windows(3))
        state.select(1); state.clearHover(1)
        XCTAssertNil(state.selectedIndex)
        state.move(by: 1)
        XCTAssertEqual(state.selectedIndex, 0)
        state.clearHover(0)
        XCTAssertEqual(state.selectedIndex, 0)
    }
    func testMenuSizesToContentRatherThanUsingAnOversizedFixedWidth() {
        let size = WindowPickerMetrics.size(name: "Test", windows: windows(3), scale: 2)
        XCTAssertLessThan(size.width, 300)
        XCTAssertLessThan(size.height, 120)
    }

}
