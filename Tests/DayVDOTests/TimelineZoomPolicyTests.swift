import XCTest
@testable import DayVDO

final class TimelineZoomPolicyTests: XCTestCase {
    func testExtremeZoomConvergesWithoutOvershootingAndReversesImmediately() {
        var height: CGFloat = 45
        for _ in 0..<30 {
            let next = TimelineZoomPolicy.nextFrame(current: height, target: 180)
            XCTAssertGreaterThanOrEqual(next, height)
            XCTAssertLessThanOrEqual(next, 180)
            height = next
        }
        XCTAssertEqual(height, 180)
        XCTAssertLessThan(TimelineZoomPolicy.nextFrame(current: height, target: 45), height)
        for _ in 0..<30 {
            let next = TimelineZoomPolicy.nextFrame(current: height, target: 45)
            XCTAssertLessThanOrEqual(next, height)
            XCTAssertGreaterThanOrEqual(next, 45)
            height = next
        }
        XCTAssertEqual(height, 45)
    }

    func testHourHeightIsClampedAtBothExtremes() {
        XCTAssertEqual(TimelineZoomPolicy.clampedHourHeight(1), 45)
        XCTAssertEqual(TimelineZoomPolicy.clampedHourHeight(90), 90)
        XCTAssertEqual(TimelineZoomPolicy.clampedHourHeight(1_000), 180)
    }

    func testZoomKeepsTheSameMinuteAtTheViewportCenter() {
        let anchor = TimelineZoomPolicy.anchor(
            scrollOffset: 600,
            viewportHeight: 400,
            hourHeight: 90
        )
        let offset = TimelineZoomPolicy.scrollOffset(
            keeping: anchor,
            hourHeight: 150,
            viewportHeight: 400
        )

        let minuteAtCenter = (offset + 200 - TimelineZoomPolicy.verticalContentInset)
            / (150 / 60)
        XCTAssertEqual(minuteAtCenter, anchor.minute, accuracy: 0.001)
    }

    func testZoomOffsetClampsAtTimelineEdges() {
        let top = TimelineZoomAnchor(minute: 0, viewportY: 300)
        XCTAssertEqual(
            TimelineZoomPolicy.scrollOffset(
                keeping: top,
                hourHeight: 90,
                viewportHeight: 600
            ),
            0
        )

        let bottom = TimelineZoomAnchor(minute: 1_440, viewportY: 0)
        XCTAssertEqual(
            TimelineZoomPolicy.scrollOffset(
                keeping: bottom,
                hourHeight: 90,
                viewportHeight: 600
            ),
            1_584
        )
    }
}
