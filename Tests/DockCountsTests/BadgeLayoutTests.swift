import XCTest
import AppKit
@testable import DockCounts

final class BadgeLayoutTests: XCTestCase {
    func testCompactAndStandardBadgesFitDockTileProportionally() {
        for size in BadgeSize.allCases {
            for side: CGFloat in [16, 24, 32, 48, 64, 100] {
                for scale: CGFloat in [1, 2] {
                    for counts in [
                        WindowCounts(minimized: 0, total: 1),
                        WindowCounts(minimized: 0, total: 3),
                        WindowCounts(minimized: 2, total: 5),
                        WindowCounts(minimized: 12, total: 25)
                    ] {
                        let metrics = BadgeMetrics.make(counts: counts, tileSide: side, scale: scale, size: size)
                        XCTAssertLessThanOrEqual(metrics.size.width, side)
                        XCTAssertLessThan(metrics.size.height, side)
                        XCTAssertLessThanOrEqual(metrics.contentSize.height, max(11, floor(side * 0.36)))
                        XCTAssertEqual(metrics.size.width * scale, (metrics.size.width * scale).rounded())
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

    func testVisibilityModesFilterNoiseProperly() {
        let single = WindowCounts(minimized: 0, total: 1)
        let singleMin = WindowCounts(minimized: 1, total: 1)
        let multi = WindowCounts(minimized: 0, total: 3)
        let multiMin = WindowCounts(minimized: 2, total: 4)

        XCTAssertFalse(BadgeVisibilityMode.smart.shouldShow(single))
        XCTAssertTrue(BadgeVisibilityMode.smart.shouldShow(singleMin))
        XCTAssertTrue(BadgeVisibilityMode.smart.shouldShow(multi))
        XCTAssertTrue(BadgeVisibilityMode.smart.shouldShow(multiMin))

        XCTAssertFalse(BadgeVisibilityMode.minimizedOnly.shouldShow(single))
        XCTAssertFalse(BadgeVisibilityMode.minimizedOnly.shouldShow(multi))
        XCTAssertTrue(BadgeVisibilityMode.minimizedOnly.shouldShow(singleMin))
        XCTAssertTrue(BadgeVisibilityMode.minimizedOnly.shouldShow(multiMin))

        XCTAssertTrue(BadgeVisibilityMode.always.shouldShow(single))
        XCTAssertFalse(BadgeVisibilityMode.always.shouldShow(WindowCounts(minimized: 0, total: 0)))
    }

    func testGeometryHasDistantPointerFallbackInterval() {
        let tile = CGRect(x: -50, y: 200, width: 40, height: 40)
        XCTAssertEqual(DockRefreshPolicy.geometryInterval(pointer: CGPoint(x: -20, y: 220), tiles: [tile]), 1.0 / 30.0)
        XCTAssertEqual(DockRefreshPolicy.geometryInterval(pointer: CGPoint(x: 700, y: 400), tiles: [tile]), 0.25)
    }
}
