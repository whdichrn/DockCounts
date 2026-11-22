import XCTest
import AppKit
@testable import DockCounts

final class BadgeLayoutTests: XCTestCase {
    func testCompactAndStandardBadgesFitDockTileProportionally() {
        for mode in BadgeVisibilityMode.allCases {
            for size in BadgeSize.allCases {
                for side: CGFloat in [16, 24, 32, 48, 64, 100] {
                    for scale: CGFloat in [1, 2] {
                        for counts in [
                            WindowCounts(minimized: 0, total: 1),
                            WindowCounts(minimized: 1, total: 1),
                            WindowCounts(minimized: 0, total: 3),
                            WindowCounts(minimized: 2, total: 5),
                            WindowCounts(minimized: 3, total: 3),
                            WindowCounts(minimized: 12, total: 25)
                        ] {
                            let metrics = BadgeMetrics.make(counts: counts, tileSide: side, scale: scale, size: size, visibilityMode: mode)
                            XCTAssertLessThanOrEqual(metrics.size.width, side)
                            XCTAssertLessThan(metrics.size.height, side)
                            XCTAssertLessThanOrEqual(metrics.contentSize.height, max(11, floor(side * 0.36)))
                            XCTAssertEqual(metrics.size.width * scale, (metrics.size.width * scale).rounded())
                        }
                    }
                }
            }
        }
    }

    func testSingleCountBadgeWithoutMinimizedFormsCompactCircle() {
        let metrics = BadgeMetrics.make(counts: WindowCounts(minimized: 0, total: 3), tileSide: 48, scale: 2, size: .compact)
        XCTAssertEqual(metrics.contentSize.width, metrics.contentSize.height)
    }

    func testBadgeUsesLowerCornerAndLeavesNotificationCornerFree() {
        let tile = CGRect(x: 20, y: 40, width: 44, height: 32)
        let metrics = BadgeMetrics.make(counts: WindowCounts(minimized: 1, total: 3), tileSide: 32, scale: 2)
        let frame = BadgePlacement.frame(tile: tile, size: metrics.size, scale: 2)
        XCTAssertTrue(tile.contains(CGPoint(x: frame.midX, y: frame.midY)))
        XCTAssertLessThanOrEqual(frame.midY, tile.midY)
        XCTAssertLessThan(frame.maxY, tile.maxY - 3)
        XCTAssertEqual(frame.minX * 2, (frame.minX * 2).rounded())
        XCTAssertEqual(frame.minY * 2, (frame.minY * 2).rounded())
    }

    func testBadgeDisplayRulesForTotalAndMinimizedCounts() {
        let zero = WindowCounts(minimized: 0, total: 0)
        let singleOpen = WindowCounts(minimized: 0, total: 1)
        let singleAllMin = WindowCounts(minimized: 1, total: 1)
        let multiOpen = WindowCounts(minimized: 0, total: 3)
        let multiPartialMin = WindowCounts(minimized: 1, total: 3)
        let multiAllMin = WindowCounts(minimized: 3, total: 3)

        // .auto: show a iff total > 0 && minimized < total; always show b iff minimized > 0
        XCTAssertEqual(BadgeVisibilityMode.auto.display(for: zero), BadgeDisplay(showTotal: false, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.auto.display(for: singleOpen), BadgeDisplay(showTotal: true, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.auto.display(for: singleAllMin), BadgeDisplay(showTotal: false, showMinimized: true))
        XCTAssertEqual(BadgeVisibilityMode.auto.display(for: multiOpen), BadgeDisplay(showTotal: true, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.auto.display(for: multiPartialMin), BadgeDisplay(showTotal: true, showMinimized: true))
        XCTAssertEqual(BadgeVisibilityMode.auto.display(for: multiAllMin), BadgeDisplay(showTotal: false, showMinimized: true))

        // .always: show a iff total > 0; show b iff minimized > 0
        XCTAssertEqual(BadgeVisibilityMode.always.display(for: zero), BadgeDisplay(showTotal: false, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.always.display(for: singleOpen), BadgeDisplay(showTotal: true, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.always.display(for: singleAllMin), BadgeDisplay(showTotal: true, showMinimized: true))
        XCTAssertEqual(BadgeVisibilityMode.always.display(for: multiAllMin), BadgeDisplay(showTotal: true, showMinimized: true))

        // .hidden: never show a; show b iff minimized > 0
        XCTAssertEqual(BadgeVisibilityMode.hidden.display(for: zero), BadgeDisplay(showTotal: false, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.hidden.display(for: singleOpen), BadgeDisplay(showTotal: false, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.hidden.display(for: multiOpen), BadgeDisplay(showTotal: false, showMinimized: false))
        XCTAssertEqual(BadgeVisibilityMode.hidden.display(for: singleAllMin), BadgeDisplay(showTotal: false, showMinimized: true))
        XCTAssertEqual(BadgeVisibilityMode.hidden.display(for: multiPartialMin), BadgeDisplay(showTotal: false, showMinimized: true))
        XCTAssertEqual(BadgeVisibilityMode.hidden.display(for: multiAllMin), BadgeDisplay(showTotal: false, showMinimized: true))
    }

    func testGeometryHasDistantPointerFallbackInterval() {
        let tile = CGRect(x: -50, y: 200, width: 40, height: 40)
        XCTAssertEqual(DockRefreshPolicy.geometryInterval(pointer: CGPoint(x: -20, y: 220), tiles: [tile]), 1.0 / 30.0)
        XCTAssertEqual(DockRefreshPolicy.geometryInterval(pointer: CGPoint(x: 700, y: 400), tiles: [tile]), 0.25)
    }
}
