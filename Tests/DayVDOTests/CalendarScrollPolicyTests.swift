import XCTest
@testable import DayVDO

final class CalendarScrollPolicyTests: XCTestCase {
    func testRestoredNoonAnchorKeepsMonthNavigationOnTheCorrectWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        calendar.firstWeekday = 2
        let restored = LocalDay(year: 2026, month: 8, day: 31).date(timeZone: calendar.timeZone)

        for (year, month, expected) in [(2026, 10, 4), (2026, 11, 8), (2026, 12, 13), (2027, 1, 17)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: 1)))
            let target = try XCTUnwrap(CalendarMonthGrid.dates(containing: date, calendar: calendar).first)
            XCTAssertEqual(CalendarScrollPolicy.weekOffset(from: restored, to: target, calendar: calendar), expected)
            XCTAssertEqual(CalendarScrollPolicy.weekOffset(from: target, to: restored, calendar: calendar), -expected)
        }
    }

    func testWeekOffsetIgnoresTimeOfDayAcrossDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day) in [(3, 2), (10, 26)] {
            let anchor = LocalDay(year: 2026, month: month, day: day).date(timeZone: calendar.timeZone)
            let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: anchor))
            let target = calendar.startOfDay(for: later)
            XCTAssertEqual(CalendarScrollPolicy.weekOffset(from: anchor, to: target, calendar: calendar), 2)
            XCTAssertEqual(CalendarScrollPolicy.weekOffset(from: target, to: anchor, calendar: calendar), -2)
        }
    }

    func testShortVirtualRunwayStillCoversTheVisibleWeeksNearRebaseEdges() {
        let limits = -104...104
        for top in [-52, 47] {
            for direction in [CalendarScrollDirection.earlier, .later] {
                let range = CalendarScrollPolicy.cacheWindow(
                    around: top, direction: direction,
                    cacheCount: 30, visibleCount: 6, limits: limits
                )
                XCTAssertEqual(range.count, 30)
                XCTAssertTrue(range.contains(top))
                XCTAssertTrue(range.contains(top + 5))
            }
        }
    }

    func testViewportHeightChangesAreSeparatedFromScrollMovement() {
        XCTAssertFalse(
            CalendarScrollPolicy.viewportHeightChanged(from: nil, to: 100)
        )
        XCTAssertFalse(
            CalendarScrollPolicy.viewportHeightChanged(from: 100, to: 100.4)
        )
        XCTAssertTrue(
            CalendarScrollPolicy.viewportHeightChanged(from: 100, to: 101)
        )
        XCTAssertTrue(
            CalendarScrollPolicy.viewportHeightChanged(from: 100, to: 180)
        )
    }

    func testViewportResizeAnchorRejectsTransientGeometryUntilSettled() {
        XCTAssertFalse(
            CalendarScrollPolicy.viewportHasSettled(reportedRow: -23, at: 12)
        )
        XCTAssertTrue(
            CalendarScrollPolicy.viewportHasSettled(reportedRow: 12.05, at: 12)
        )
    }

    func testStationaryGestureDoesNotChooseANewDestination() {
        XCTAssertEqual(
            destination(start: 12, current: 12.005, duration: 0.2, velocity: 0),
            .none
        )
    }

    func testSlowShortAndLongGesturesSnapToNearestWeek() {
        XCTAssertEqual(
            destination(start: 12, current: 12.4, duration: 0.8, velocity: 0.5),
            .nearestWeek(direction: .later)
        )
        XCTAssertEqual(
            destination(start: 18, current: 10, duration: 3, velocity: -1),
            .nearestWeek(direction: .earlier)
        )
    }

    func testLongContactStaysAPrecisionDragDespiteAReleaseSpike() {
        XCTAssertEqual(
            destination(start: 12, current: 13.5, duration: 0.8, velocity: 5),
            .nearestWeek(direction: .later)
        )
    }

    func testFastShortFlickMovesOneAdjacentMonth() {
        XCTAssertEqual(
            destination(start: 12, current: 13.99, duration: 0.15, velocity: 3),
            .adjacentMonth(direction: .later)
        )
        XCTAssertEqual(
            destination(start: 12, current: 11.6, duration: 0.1, velocity: -7),
            .adjacentMonth(direction: .earlier)
        )
    }

    func testFastLongFlickUsesTheSystemMomentumDestination() {
        XCTAssertEqual(
            destination(start: 12, current: 14, duration: 0.2, velocity: 5),
            .momentumMonth(direction: .later)
        )
        XCTAssertEqual(
            destination(start: 16, current: 11.5, duration: 0.2, velocity: -8),
            .momentumMonth(direction: .earlier)
        )
    }

    func testReleaseDirectionWinsAfterReversingTheGesture() {
        XCTAssertEqual(
            destination(start: 12, current: 12.8, duration: 0.15, velocity: -5),
            .adjacentMonth(direction: .earlier)
        )
    }

    func testCoarseWheelAlwaysUsesWeekSnapping() {
        XCTAssertEqual(
            destination(
                start: 12,
                current: 16,
                duration: 0.1,
                velocity: 20,
                precise: false
            ),
            .nearestWeek(direction: .later)
        )
    }

    func testNearestWeekKeepsHalfWeekTieTowardGestureStart() {
        XCTAssertEqual(
            CalendarScrollPolicy.nearestWeekIndex(for: 13.5, direction: .later),
            13
        )
        XCTAssertEqual(
            CalendarScrollPolicy.nearestWeekIndex(for: 10.5, direction: .earlier),
            11
        )
    }

    func testNearestMonthUsesDirectionOnlyToBreakATie() {
        XCTAssertEqual(
            CalendarScrollPolicy.nearestMonthIndex(
                for: 12,
                candidates: [10, 14],
                direction: .later
            ),
            14
        )
        XCTAssertEqual(
            CalendarScrollPolicy.nearestMonthIndex(
                for: 12,
                candidates: [10, 14],
                direction: .earlier
            ),
            10
        )
        XCTAssertEqual(
            CalendarScrollPolicy.nearestMonthIndex(
                for: 11,
                candidates: [10, 14],
                direction: .later
            ),
            10
        )
    }

    func testFinalTargetUsesTheSystemProposedEndpointBeforeDeceleration() {
        XCTAssertEqual(
            CalendarScrollPolicy.targetIndex(
                for: .momentumMonth(direction: .later),
                currentRow: 14,
                proposedMomentumRow: 19.2,
                adjacentMonthIndex: 17,
                monthCandidates: [12, 17, 21]
            ),
            21
        )
        XCTAssertEqual(
            CalendarScrollPolicy.targetIndex(
                for: .adjacentMonth(direction: .later),
                currentRow: 13.6,
                proposedMomentumRow: 20,
                adjacentMonthIndex: 16,
                monthCandidates: [12, 16, 21]
            ),
            16
        )
        XCTAssertEqual(
            CalendarScrollPolicy.targetIndex(
                for: .nearestWeek(direction: .later),
                currentRow: 13.4,
                proposedMomentumRow: 20,
                adjacentMonthIndex: nil,
                monthCandidates: [12, 16, 21]
            ),
            13
        )
    }

    func testDirectionalCacheWindowKeepsThirtyWeeksLoadedAheadOfMovement() {
        let later = CalendarScrollPolicy.cacheWindow(
            around: 100,
            direction: .later,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(later, 96...125)
        XCTAssertEqual(later.count, 30)
        XCTAssertEqual(later.upperBound - (100 + 5), 20)

        let earlier = CalendarScrollPolicy.cacheWindow(
            around: 100,
            direction: .earlier,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(earlier, 80...109)
        XCTAssertEqual(earlier.count, 30)
        XCTAssertEqual(100 - earlier.lowerBound, 20)
    }

    func testCacheWindowRecentersForANewOrReversedGesture() {
        let centered = CalendarScrollPolicy.cacheWindow(
            around: -37,
            direction: nil,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(centered, -49 ... -20)

        let reversed = CalendarScrollPolicy.cacheWindow(
            around: -37,
            direction: .earlier,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(reversed, -57 ... -28)
    }

    func testCacheWindowClampsWithoutChangingItsSize() {
        XCTAssertEqual(
            CalendarScrollPolicy.cacheWindow(
                around: -1039,
                direction: .earlier,
                cacheCount: 30,
                visibleCount: 6,
                limits: -1040...1040
            ),
            -1040 ... -1011
        )
        XCTAssertEqual(
            CalendarScrollPolicy.cacheWindow(
                around: 1035,
                direction: .later,
                cacheCount: 30,
                visibleCount: 6,
                limits: -1040...1040
            ),
            1011...1040
        )
    }

    func testNavigationCacheCoversBothVisibleEndpoints() {
        let range = CalendarScrollPolicy.cacheWindowCovering(
            currentTop: 40,
            targetTop: 50,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(range.count, 30)
        XCTAssertTrue(range.contains(40))
        XCTAssertTrue(range.contains(45))
        XCTAssertTrue(range.contains(50))
        XCTAssertTrue(range.contains(55))
    }

    func testPredictiveCacheKeepsCurrentAndMomentumViewportsLoaded() {
        let later = CalendarScrollPolicy.predictiveCacheWindow(
            currentTop: 100,
            predictedTop: 112,
            direction: .later,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(later.count, 30)
        XCTAssertTrue(later.contains(100))
        XCTAssertTrue(later.contains(105))
        XCTAssertTrue(later.contains(112))
        XCTAssertTrue(later.contains(117))

        let earlier = CalendarScrollPolicy.predictiveCacheWindow(
            currentTop: -20,
            predictedTop: -32,
            direction: .earlier,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(earlier.count, 30)
        XCTAssertTrue(earlier.contains(-32))
        XCTAssertTrue(earlier.contains(-27))
        XCTAssertTrue(earlier.contains(-20))
        XCTAssertTrue(earlier.contains(-15))
    }

    func testPredictiveCacheClampsExtremeMomentumToTwelveWeeks() {
        let range = CalendarScrollPolicy.predictiveCacheWindow(
            currentTop: 0,
            predictedTop: 500,
            direction: .later,
            cacheCount: 30,
            visibleCount: 6,
            limits: -1040...1040
        )
        XCTAssertEqual(range.count, 30)
        XCTAssertTrue(range.contains(0))
        XCTAssertTrue(range.contains(17))
    }

    private func destination(
        start: CGFloat,
        current: CGFloat,
        duration: TimeInterval,
        velocity: CGFloat,
        precise: Bool = true
    ) -> CalendarScrollDestination {
        CalendarScrollPolicy.destination(
            for: CalendarGestureSnapshot(
                startRow: start,
                currentRow: current,
                duration: duration,
                releaseVelocityInWeeksPerSecond: velocity,
                usesPreciseDeltas: precise
            )
        )
    }
}
