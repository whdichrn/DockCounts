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
        let installedWindows = AX.value(AXUIElementCreateApplication(installed.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
        let url = try XCTUnwrap(fixture.bundleURL)
        let entry = try XCTUnwrap(AX.dockEntries(applications: [url.standardizedFileURL: fixture.processIdentifier]).first)
        let badge = try XCTUnwrap(installedWindows.first { window in
            guard AX.string(window, kAXIdentifierAttribute) == "io.github.whdichrn.DockCounts.badge", let frame = AX.frame(window) else { return false }
            return entry.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }, "Installed application must render the fixture's real Dock badge")
        func labels(_ element: AXUIElement, depth: Int = 0) -> [String] {
            guard depth < 5 else { return [] }
            return [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute].compactMap { AX.string(element, $0) } + AX.children(element).flatMap { labels($0, depth: depth + 1) }
        }
        let badgeFrame = try XCTUnwrap(AX.frame(badge))
        XCTAssertNotNil(AX.clickedEntry(at: CGPoint(x: badgeFrame.midX, y: badgeFrame.midY), entries: [entry]), "The rendered badge must pass clicks through to the application icon")
        let rendered = labels(badge)
        XCTAssertTrue(rendered.contains("共 3 个窗口，已最小化 \(expected) 个") || (rendered.contains("3") && rendered.contains("\(expected)")), "Actual badge text: \(rendered)")
        print("INSTALLED BADGE:", rendered, "frame:", badgeFrame, "tile:", entry.frame)
    }

    func testNativeWindowSelectionResult() throws {
        guard ProcessInfo.processInfo.environment["DOCKCOUNTS_SELECTION_TEST"] == "1" else { throw XCTSkip("Requires a real input selection of the fixture's Beta window.") }
        let fixture = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.whdichrn.DockCountsFixture").first)
        let beta = try XCTUnwrap(AX.windows(pid: fixture.processIdentifier)?.first { $0.title == "DockCounts Test Beta" })
        let deadline = Date().addingTimeInterval(3)
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
        let focused = try XCTUnwrap(AX.value(AXUIElementCreateApplication(fixture.processIdentifier), kAXFocusedWindowAttribute))
        XCTAssertTrue(CFEqual(focused, beta.element))
        XCTAssertEqual(AX.windows(pid: fixture.processIdentifier)?.filter(\.minimized).count, 0)
        print("NATIVE MENU SELECTION: minimized=\(String(describing: AX.value(beta.element, kAXMinimizedAttribute))) main=\(String(describing: AX.value(beta.element, kAXMainAttribute))) fixtureActive=\(fixture.isActive)")
    }

}
