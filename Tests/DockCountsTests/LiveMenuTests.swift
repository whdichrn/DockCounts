import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class LiveMenuTests: XCTestCase {
    func testLiveWindowMenu() throws {
        guard ProcessInfo.processInfo.environment["DOCKCOUNTS_MENU_TEST"] == "1" else {
            throw XCTSkip("Requires a visible fixture window picker.")
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCounts").first)
        let windows = try XCTUnwrap(AX.value(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement])
        let picker = try XCTUnwrap(windows.first { AX.string($0, kAXIdentifierAttribute) == "io.github.whdichrn.DockCounts.window-picker" })
        func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
            guard depth < 10 else { return [] }
            return [element] + AX.children(element).flatMap { descendants($0, depth: depth + 1) }
        }
        let rowButtons = descendants(picker).filter {
            AX.string($0, kAXRoleAttribute) == kAXButtonRole
                && (AX.string($0, kAXIdentifierAttribute)?.hasPrefix("window-row-") ?? false)
        }
        let labels = rowButtons.compactMap { AX.string($0, kAXDescriptionAttribute) ?? AX.string($0, kAXTitleAttribute) }
        XCTAssertEqual(rowButtons.count, 3)
        XCTAssertEqual(Set(labels), Set(["DockCounts Test Gamma", "DockCounts Test Alpha", "DockCounts Test Beta — 已最小化"]))
        print("LIVE WINDOW PICKER:", labels, "frame:", String(describing: AX.frame(picker)))
    }
}
