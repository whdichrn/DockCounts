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

    func testInstalledEndToEndWindowState() throws {
        guard let raw = ProcessInfo.processInfo.environment["DOCKCOUNTS_E2E_EXPECT_MINIMIZED"], let expected = Int(raw) else { throw XCTSkip("Requires native input acceptance against the installed app.") }
        let fixture = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCountsFixture").first)
        let windows = try XCTUnwrap(AX.windows(pid: fixture.processIdentifier))
        let beta = try XCTUnwrap(windows.first { $0.title == "DockCounts Test Beta" })
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows.filter(\.minimized).count, expected)
        if expected == 0 {
            XCTAssertFalse(beta.minimized)
            XCTAssertEqual(AX.value(beta.element, kAXMainAttribute) as? Bool, true)
        }
        print("NATIVE INPUT RESULT:", windows.map { ($0.title, $0.minimized) }, "fixtureActive:", fixture.isActive)
        let installed = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCounts").first)
        for window in AX.value(AXUIElementCreateApplication(installed.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if AX.string(window, kAXTitleAttribute) == "DockCounts" { print("SETTINGS FRAME:", String(describing: AX.frame(window))) }
        }
    }

    func testAwaitNativeWindowSelection() throws {
        guard ProcessInfo.processInfo.environment["DOCKCOUNTS_AWAIT_NATIVE_SELECTION"] == "1" else { throw XCTSkip("Requires interactive selection of the fixture's Beta window.") }
        let fixture = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCountsFixture").first)
        let beta = try XCTUnwrap(AX.windows(pid: fixture.processIdentifier)?.first { $0.title == "DockCounts Test Beta" })
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline && AX.value(beta.element, kAXMinimizedAttribute) as? Bool != false {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let activationDeadline = Date().addingTimeInterval(3)
        while Date() < activationDeadline && !fixture.isActive {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(AX.value(beta.element, kAXMinimizedAttribute) as? Bool, false)
        XCTAssertEqual(AX.value(beta.element, kAXMainAttribute) as? Bool, true)
        XCTAssertTrue(fixture.isActive)
        XCTAssertEqual(AX.windows(pid: fixture.processIdentifier)?.filter(\.minimized).count, 0)
        print("NATIVE MENU SELECTION: Beta restored, main window, fixtureActive=\(fixture.isActive)")
    }

}
