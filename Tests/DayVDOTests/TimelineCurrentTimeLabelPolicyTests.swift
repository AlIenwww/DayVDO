import CoreGraphics
import XCTest
@testable import DayVDO

final class TimelineCurrentTimeLabelPolicyTests: XCTestCase {
    func testNonOverlappingPositionDoesNotMove() {
        XCTAssertEqual(position(minute: 21 * 60 + 30, hourHeight: 90), 21.5 * 90 - 7)
    }

    func testScreenshotTimeMovesBelowTheHourlyLabel() {
        XCTAssertEqual(position(minute: 21 * 60 + 9, hourHeight: 90), 21 * 90 - 7 + 14 + 3)
    }

    func testEquallyClosePositionsPreferMovingDown() {
        XCTAssertEqual(position(minute: 21 * 60, hourHeight: 90), 21 * 90 - 7 + 14 + 3)
        XCTAssertLessThan(position(minute: 21 * 60 - 1, hourHeight: 90), 21 * 90 - 7)
        XCTAssertGreaterThan(position(minute: 21 * 60 + 1, hourHeight: 90), 21 * 90 - 7)
    }

    func testEveryMinuteStaysInsideDayAndClearOfAllTicksAtSupportedZooms() {
        for hourHeight: CGFloat in [45, 90, 180] {
            for labelHeight: CGFloat in [12, 14, 16] {
                let ticks = frames(hourHeight: hourHeight, labelHeight: 16)
                for minute in 0..<1440 {
                    let natural = CGFloat(minute) * hourHeight / 60 - 7
                    let top = TimelineCurrentTimeLabelPolicy.top(for: natural, labelHeight: labelHeight,
                        avoiding: ticks, contentHeight: hourHeight * 24)
                    XCTAssertGreaterThanOrEqual(top, 0)
                    XCTAssertLessThanOrEqual(top + labelHeight, hourHeight * 24)
                    for tick in ticks {
                        XCTAssertTrue(top + labelHeight + 3 <= tick.minY + 0.000_001
                            || top >= tick.maxY + 3 - 0.000_001,
                            "Overlap at minute \(minute), zoom \(hourHeight), height \(labelHeight)")
                    }
                }
            }
        }
    }

    private func position(minute: Int, hourHeight: CGFloat) -> CGFloat {
        TimelineCurrentTimeLabelPolicy.top(for: CGFloat(minute) * hourHeight / 60 - 7,
            labelHeight: 14, avoiding: frames(hourHeight: hourHeight, labelHeight: 14),
            contentHeight: hourHeight * 24)
    }

    private func frames(hourHeight: CGFloat, labelHeight: CGFloat) -> [CGRect] {
        (0...24).map { CGRect(x: 0, y: CGFloat($0) * hourHeight - 7, width: 46, height: labelHeight) }
    }
}
