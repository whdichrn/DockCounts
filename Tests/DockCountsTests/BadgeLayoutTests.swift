import XCTest
import AppKit
@testable import DockCounts
final class BadgeLayoutTests: XCTestCase {
    func testCompactBadgeFitsItsDockCellAcrossSizesAndRetinaScales() {
        for side: CGFloat in [16, 24, 32, 64, 100] {
            for scale: CGFloat in [1, 2] {
                for counts in [WindowCounts(minimized: 0, total: 1), WindowCounts(minimized: 12, total: 25), WindowCounts(minimized: 100, total: 120)] {
                    let metrics = BadgeMetrics.make(counts: counts, tileSide: side, scale: scale)
                    XCTAssertLessThanOrEqual(metrics.size.width, side)
                    XCTAssertLessThan(metrics.size.height, side)
                    XCTAssertEqual(metrics.size.width * scale, (metrics.size.width * scale).rounded())
                }
            }
        }
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
    func testGeometryHasADistantPointerFallbackForDesktopChanges() {
        let tile = CGRect(x: -50, y: 200, width: 40, height: 40)
        XCTAssertEqual(DockRefreshPolicy.geometryInterval(pointer: CGPoint(x: -20, y: 220), tiles: [tile]), 1.0 / 30.0)
        XCTAssertEqual(DockRefreshPolicy.geometryInterval(pointer: CGPoint(x: 700, y: 400), tiles: [tile]), 0.1)
    }
}
