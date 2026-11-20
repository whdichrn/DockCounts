import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class LiveMenuTests: XCTestCase {
    func testLiveWindowMenu() throws {
        guard ProcessInfo.processInfo.environment["DOCKCOUNTS_MENU_TEST"] == "1" else { throw XCTSkip("Requires the debug --smoke-menu UI driver.") }
        func dump(_ element: AXUIElement, _ depth: Int) {
            if depth > 3 { return }
            print("MENU AX ", depth, AX.string(element, kAXRoleAttribute) ?? "?", AX.string(element, kAXTitleAttribute) ?? "?", String(describing: AX.frame(element)))
            for child in AX.children(element) { dump(child, depth + 1) }
        }
        let fixture = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCountsFixture").first)
        let url = try XCTUnwrap(fixture.bundleURL)
        let entry = try XCTUnwrap(AX.dockEntries(applications: [url.standardizedFileURL: fixture.processIdentifier]).first)
        var hit: AXUIElement?
        _ = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(entry.frame.midX + 5), Float(entry.frame.midY + 5), &hit)
        var menu = try XCTUnwrap(hit)
        if AX.string(menu, kAXRoleAttribute) == kAXMenuItemRole,
           let parent = AX.value(menu, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
            menu = parent as! AXUIElement
        }
        dump(menu, 0)
        XCTAssertEqual(AX.string(menu, kAXRoleAttribute), kAXMenuRole)
        XCTAssertEqual(Set(AX.children(menu).compactMap { AX.string($0, kAXTitleAttribute) }), Set(["DockCountsFixture", "DockCounts Test Gamma", "DockCounts Test Alpha", "DockCounts Test Beta  — 已最小化"]))
        let windows = try XCTUnwrap(AX.windows(pid: fixture.processIdentifier))
        print("WINDOWS: ", windows.map { ($0.title, $0.minimized) })
    }
}
