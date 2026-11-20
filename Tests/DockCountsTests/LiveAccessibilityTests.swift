import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class LiveAccessibilityTests: XCTestCase {
    func testFixtureWindowInventoryAndDockMapping() throws {
        guard ProcessInfo.processInfo.environment["DOCKCOUNTS_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Run scripts/test-live.sh to test a real three-window fixture.")
        }
        XCTAssertTrue(AXIsProcessTrusted(), "Test runner needs Accessibility permission")
        let fixture = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCountsFixture").first)
        let windows = try XCTUnwrap(AX.windows(pid: fixture.processIdentifier))
        XCTAssertEqual(Set(windows.map(\.title)), Set(["DockCounts Test Alpha", "DockCounts Test Beta", "DockCounts Test Gamma"]))
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows.filter(\.minimized).count, 1)
        let url = try XCTUnwrap(fixture.bundleURL)
        let entry = try XCTUnwrap(AX.dockEntries(applications: [url.standardizedFileURL: fixture.processIdentifier]).first)
        XCTAssertEqual(entry.counts, WindowCounts(minimized: 1, total: 3))
        XCTAssertTrue(entry.frame.width > 0 && entry.frame.height > 0)
        XCTAssertNotNil(AX.clickedEntry(at: CGPoint(x: entry.frame.midX, y: entry.frame.midY), entries: [entry]))
        XCTAssertNotNil(AX.clickedEntry(at: CGPoint(x: entry.frame.maxX - 4, y: entry.frame.minY + 3), entries: [entry]), "Badge must not block the underlying icon's click target")
        XCTAssertTrue(AX.dockIsAt(CGPoint(x: entry.frame.midX, y: entry.frame.midY)))
        print("LIVE FIXTURE: total=3 minimized=1 dockFrame=\(entry.frame)")
    }
    func testRestoreMinimizedFixtureWindow() throws {
        guard ProcessInfo.processInfo.environment["DOCKCOUNTS_RESTORE_TEST"] == "1" else { throw XCTSkip("Requires a disposable live fixture.") }
        let fixture = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCountsFixture").first)
        let windows = try XCTUnwrap(AX.windows(pid: fixture.processIdentifier))
        let beta = try XCTUnwrap(windows.first { $0.title == "DockCounts Test Beta" })
        XCTAssertTrue(beta.minimized)
        XCTAssertTrue(WindowActivator.activate(pid: fixture.processIdentifier, window: beta))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && (AX.value(beta.element, kAXMinimizedAttribute) as? Bool != false || AX.value(beta.element, kAXMainAttribute) as? Bool != true || !fixture.isActive) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(AX.value(beta.element, kAXMinimizedAttribute) as? Bool, false)
        XCTAssertEqual(AX.value(beta.element, kAXMainAttribute) as? Bool, true)
        let app = AXUIElementCreateApplication(fixture.processIdentifier)
        let focused = try XCTUnwrap(AX.value(app, kAXFocusedWindowAttribute))
        XCTAssertTrue(CFEqual(focused, beta.element))
        XCTAssertTrue(fixture.isActive)
    }

}
