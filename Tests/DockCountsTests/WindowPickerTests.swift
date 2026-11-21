import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class WindowPickerTests: XCTestCase {
    private func windows() -> [WindowRecord] {
        let el = AXUIElementCreateApplication(1)
        return [
            WindowRecord(element: el, title: "Normal Window", minimized: false, isMain: false),
            WindowRecord(element: el, title: "Minimized Window", minimized: true, isMain: false),
            WindowRecord(element: el, title: "Main Window", minimized: false, isMain: true)
        ]
    }

    func testStateOrdersMainThenActiveThenMinimized() {
        let state = WindowPickerState(windows: windows())
        XCTAssertEqual(state.windows.map(\.title), ["Main Window", "Normal Window", "Minimized Window"])
        XCTAssertEqual(state.activeIndices, [0, 1])
        XCTAssertEqual(state.minimizedIndices, [2])
    }

    func testKeyboardSelectionWrapsNumericShortcutsAndRetainsIdentity() {
        let records = [
            WindowRecord(element: AXUIElementCreateApplication(1), title: "Window 0", minimized: false, isMain: true),
            WindowRecord(element: AXUIElementCreateApplication(1), title: "Window 1", minimized: true),
            WindowRecord(element: AXUIElementCreateApplication(1), title: "Window 2", minimized: false)
        ]
        let state = WindowPickerState(windows: records)
        XCTAssertNil(state.selectedWindow, "Opening a menu should not paint a selection before user input")
        state.move(by: -1)
        XCTAssertEqual(state.selectedWindow?.title, "Window 1")
        state.move(by: 1)
        XCTAssertEqual(state.selectedWindow?.title, "Window 0")
        XCTAssertEqual(state.windowForShortcut(1)?.title, "Window 0")
        XCTAssertEqual(state.windowForShortcut(2)?.title, "Window 2")
        XCTAssertEqual(state.windowForShortcut(3)?.title, "Window 1")
        XCTAssertNil(state.windowForShortcut(9))
        state.select(2)
        XCTAssertTrue(state.selectedWindow!.minimized)
        XCTAssertTrue(CFEqual(state.selectedWindow!.element, records[1].element))
        state.select(20)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testEmptyPickerHasNoSelectableWindow() {
        let state = WindowPickerState(windows: [])
        state.move(by: 1)
        state.select(0)
        XCTAssertNil(state.selectedWindow)
    }

    func testPickerStaysOnDisplayForAllDockEdges() {
        let visible = CGRect(x: -1200, y: 20, width: 1150, height: 780)
        for edge in ["left", "right", "bottom"] {
            let rect = PickerPlacement.frame(
                icon: CGRect(x: -1200, y: 15, width: 40, height: 40),
                point: CGPoint(x: -1180, y: 25),
                size: CGSize(width: 340, height: 420),
                visible: visible,
                edge: edge
            )
            XCTAssertTrue(visible.contains(rect), "\(edge): \(rect)")
        }
    }

    func testPickerFitsSmallScreens() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 250)
        let rect = PickerPlacement.frame(
            icon: .zero,
            point: .zero,
            size: CGSize(width: 340, height: 420),
            visible: visible,
            edge: "bottom"
        )
        XCTAssertTrue(visible.contains(rect))
    }

    func testPointerExitClearsHoverButNotKeyboardSelection() {
        let state = WindowPickerState(windows: windows())
        state.select(1)
        state.clearHover(1)
        XCTAssertNil(state.selectedIndex)
        state.move(by: 1)
        XCTAssertEqual(state.selectedIndex, 0)
        state.clearHover(0)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testMenuSizesToContentRatherThanOversizedFixedWidth() {
        let size = WindowPickerMetrics.size(name: "Test", windows: windows(), scale: 2)
        XCTAssertLessThan(size.width, 320)
        XCTAssertLessThan(size.height, 180)
    }
}
