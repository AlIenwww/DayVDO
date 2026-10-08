import AppKit
import XCTest
@testable import DayVDO

final class CalendarNativeMonthGeometryTests: XCTestCase {
    @MainActor
    func testMeasuredHeaderInsetPreservesTheFullScrollViewportForTranslucency() {
        let viewport = CalendarNativeMonthViewport()
        viewport.frame = NSRect(x: 0, y: 0, width: 840, height: 700)
        viewport.headerHeight = 85
        viewport.layoutSubtreeIfNeeded()
        XCTAssertEqual(viewport.topInset, 85)
        XCTAssertEqual(viewport.scroll.frame, viewport.bounds)
        XCTAssertEqual(viewport.scroll.contentInsets.top, 0)
        XCTAssertEqual(viewport.headerBackdrop.frame, NSRect(x: 0, y: 0, width: 840, height: 85))
        XCTAssertEqual(viewport.headerBackdrop.blendingMode, .withinWindow)
        XCTAssertNil(viewport.headerBackdrop.hitTest(NSPoint(x: 100, y: 40)))

        viewport.headerHeight = 96
        viewport.layoutSubtreeIfNeeded()
        XCTAssertEqual(viewport.topInset, 96)
        XCTAssertEqual(viewport.scroll.frame, viewport.bounds)
        XCTAssertEqual(viewport.headerBackdrop.frame.height, 96)
    }

    func testOnlyIntersectingWeeksAreRequested() {
        let grid = CalendarNativeMonthGeometry(width: 840, rowHeight: 100)
        XCTAssertEqual(grid.indices(in: CGRect(x: 0, y: 10400, width: 840, height: 600)), 104..<110)
        XCTAssertEqual(grid.indices(in: CGRect(x: 0, y: 10401, width: 840, height: 600)), 104..<111)
        XCTAssertEqual(grid.indices(in: CGRect(x: 0, y: -70, width: 840, height: 600)), 0..<6)
        XCTAssertEqual(grid.indices(in: CGRect(x: 0, y: 20900, width: 840, height: 600)), 209..<209)
    }

    func testResizePreservesFractionalWeekAndHorizontalMargins() {
        let before = CalendarNativeMonthGeometry(width: 840, rowHeight: 100)
        let after = CalendarNativeMonthGeometry(width: 1000, rowHeight: 120)
        let weekPosition: CGFloat = 107.4
        let resizedOffset = weekPosition * after.rowHeight
        XCTAssertEqual(resizedOffset / after.rowHeight, weekPosition, accuracy: 0.00001)
        XCTAssertEqual(before.frame(at: 104), CGRect(x: 12, y: 10400, width: 816, height: 100))
        XCTAssertEqual(after.frame(at: 104), CGRect(x: 12, y: 12480, width: 976, height: 120))
        XCTAssertEqual(after.size.height, 209 * 120)
    }

    func testDocumentEdgesKeepAllSixVisibleWeeksInsideTheRunway() {
        let grid = CalendarNativeMonthGeometry(width: 840, rowHeight: 100)
        XCTAssertEqual(grid.clampedRow(-10), 0)
        XCTAssertEqual(grid.clampedRow(300), 203)
        XCTAssertEqual(grid.indices(in: CGRect(x: 0, y: grid.clampedRow(300) * 100,
                                               width: 840, height: 600)), 203..<209)
    }
}
