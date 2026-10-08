import XCTest
@testable import DayVDO

final class TimelineCreationPolicyTests: XCTestCase {
    func testBoundariesIncludeBothVisibleEdgesOnceInTimeOrder() {
        XCTAssertEqual(
            TimelineCreationPolicy.boundaries(in: [600..<641, 0..<42, 641..<701, 600..<641, 1413..<1440]),
            [0, 42, 600, 641, 701, 1413, 1440]
        )
        XCTAssertTrue(TimelineCreationPolicy.boundaries(in: []).isEmpty)
    }

    func testSelectedDayUsesClippedOvernightEdgesAndExcludesOtherDays() {
        let day = LocalDay(year: 2026, month: 10, day: 5)
        let schedules = [
            DaySchedule(startDay: day.adding(days: -1), startMinute: 1397, durationMinutes: 80,
                        content: .independent(title: "Overnight", notes: "")),
            DaySchedule(startDay: day, startMinute: 469, durationMinutes: 62,
                        content: .independent(title: "Today", notes: "")),
            DaySchedule(startDay: day.adding(days: 1), startMinute: 373, durationMinutes: 30,
                        content: .independent(title: "Tomorrow", notes: ""))
        ]
        let boundaries = TimelineCreationPolicy.boundaries(
            in: schedules.compactMap { $0.interval(on: day) }
        )
        XCTAssertEqual(boundaries, [0, 37, 469, 531])
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(at: 38, boundaries: boundaries, pointsPerMinute: 1.5),
            37
        )
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(at: 372, boundaries: boundaries, pointsPerMinute: 1.5),
            370
        )
    }

    func testCaptureDistanceRemainsSixPointsAtMinimumAndMaximumZoom() {
        // Hour heights 45, 90, and 180 correspond to 0.75, 1.5, and 3 points per minute.
        let zooms: [(pointsPerMinute: Double, outsideResult: Int)] = [
            (0.75, 495), (1.5, 490), (3, 490)
        ]
        for (pointsPerMinute, outsideResult) in zooms {
            let captureEdge = 487 + 6 / pointsPerMinute
            XCTAssertEqual(
                TimelineCreationPolicy.startMinute(
                    at: captureEdge, boundaries: [487], pointsPerMinute: pointsPerMinute
                ),
                487
            )
            XCTAssertEqual(
                TimelineCreationPolicy.startMinute(
                    at: captureEdge + 0.01 / pointsPerMinute,
                    boundaries: [487], pointsPerMinute: pointsPerMinute
                ),
                outsideResult
            )
        }
    }

    func testEnteringAndLeavingMagnetRestoresFiveMinuteGrid() {
        let samples: [(pointer: Double, start: Int)] = [
            (481, 480), (483, 487), (487, 487), (491, 487), (492, 490)
        ]
        for (pointer, start) in samples {
            XCTAssertEqual(
                TimelineCreationPolicy.startMinute(
                    at: pointer, boundaries: [487], pointsPerMinute: 1.5
                ),
                start
            )
        }
    }

    func testClosestBoundaryWinsAndEqualDistancesChooseEarlierMinute() {
        for boundaries in [[493, 487], [487, 493]] {
            XCTAssertEqual(
                TimelineCreationPolicy.startMinute(
                    at: 490, boundaries: boundaries, pointsPerMinute: 1.5
                ),
                487
            )
            XCTAssertEqual(
                TimelineCreationPolicy.startMinute(
                    at: 492, boundaries: boundaries, pointsPerMinute: 1.5
                ),
                493
            )
        }
    }

    func testOffGridBoundaryTakesPriorityOverCloserGridPoint() {
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(at: 490, boundaries: [487], pointsPerMinute: 1.5),
            487
        )
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(at: 490, boundaries: [], pointsPerMinute: 1.5),
            490
        )
    }

    func testMovingEdgeUsesAbsolutePointerTimeWithOffGridAnchor() {
        let start = TimelineCreationPolicy.startMinute(
            at: 484, boundaries: [487], pointsPerMinute: 1.5
        )
        XCTAssertEqual(start, 487)
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 484, anchoredAt: start, to: 521, boundaries: [487], pointsPerMinute: 1.5
            ),
            487..<520
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 484, anchoredAt: start, to: 451, boundaries: [487], pointsPerMinute: 1.5
            ),
            450..<487
        )
    }

    func testMovingEdgeSnapsToOffGridBoundariesInBothDirections() {
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 486, anchoredAt: 487, to: 522,
                boundaries: [487, 523], pointsPerMinute: 1.5
            ),
            487..<523
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 486, anchoredAt: 487, to: 451,
                boundaries: [449, 487], pointsPerMinute: 1.5
            ),
            449..<487
        )
    }

    func testDirectionChangesAtRawOriginEvenWhenAnchorWasSnapped() {
        // The pointer can cross its original position before crossing the snapped anchor.
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 489, anchoredAt: 487, to: 488, boundaries: [487], pointsPerMinute: 1.5
            ),
            480..<487
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 485, anchoredAt: 487, to: 486, boundaries: [487], pointsPerMinute: 1.5
            ),
            487..<495
        )
    }

    func testTooCloseBoundariesAreIgnoredWhileLegalFiveMinuteBoundaryCanSnap() {
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 486, anchoredAt: 487, to: 490,
                boundaries: [487, 490, 491, 492], pointsPerMinute: 1.5
            ),
            487..<492
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 486, anchoredAt: 487, to: 484,
                boundaries: [482, 483, 484, 487], pointsPerMinute: 1.5
            ),
            482..<487
        )
    }

    func testShortDragStillCreatesAtLeastFiveMinutesWithoutBoundary() {
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 486, anchoredAt: 487, to: 486, boundaries: [], pointsPerMinute: 1.5
            ),
            487..<495
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 486, anchoredAt: 487, to: 485, boundaries: [], pointsPerMinute: 1.5
            ),
            480..<487
        )
    }

    func testCreationStartStaysWithinDayAndLeavesRoomForMinimumDuration() {
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(
                at: -20, boundaries: [0, 1440], pointsPerMinute: 1.5
            ),
            0
        )
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(
                at: 1439, boundaries: [1438, 1440], pointsPerMinute: 1.5
            ),
            1435
        )
        XCTAssertEqual(
            TimelineCreationPolicy.startMinute(
                at: 1434, boundaries: [1434, 1440], pointsPerMinute: 1.5
            ),
            1434
        )
    }

    func testMovingEdgeClampsToMidnightAndRetainsValidMinimumRange() {
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 8, anchoredAt: 7, to: -20, boundaries: [0, 7], pointsPerMinute: 1.5
            ),
            0..<7
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 1433, anchoredAt: 1434, to: 1460,
                boundaries: [1434, 1440], pointsPerMinute: 1.5
            ),
            1434..<1440
        )
        XCTAssertEqual(
            TimelineCreationPolicy.range(
                from: 2, anchoredAt: 3, to: -1, boundaries: [0, 3], pointsPerMinute: 1.5
            ),
            3..<10
        )
    }
}
