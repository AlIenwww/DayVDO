import Foundation
import XCTest
@testable import DayVDO

final class TimelineOverlapPlacementTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 6)

    func testPointerChoosesEveryColumnFromTwoThroughNineOverlappingArrangements() throws {
        for count in 2...9 {
            var schedules = (0..<count).map { schedule(start: 540 + $0, duration: 90) }
            let movingID = try XCTUnwrap(schedules.last?.id)
            for column in 0..<count {
                schedules[count - 1].setHorizontalPosition((Double(column) + 0.5) / Double(count))
                let placements = DayPlanningPolicy.placements(schedules, on: day, prioritizing: movingID)
                XCTAssertEqual(placements.first { $0.id == movingID }?.column, column)
                XCTAssertTrue(placements.allSatisfy { $0.columnCount == count })
                assertNoConflicts(placements)
            }
        }
    }

    func testHorizontalOnlyMovementOverridesPreviouslySavedColumnAndSurvivesRelease() throws {
        var left = schedule(start: 540, duration: 60)
        var moving = schedule(start: 550, duration: 60)
        left.setHorizontalPosition(0.1, at: Date(timeIntervalSince1970: 10))
        moving.setHorizontalPosition(0.9, at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(column(of: moving, in: [left, moving]), 1)
        moving.setHorizontalPosition(0.1, at: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(column(of: moving, in: [left, moving]), 0)
        XCTAssertEqual(column(of: left, in: [left, moving]), 1)
        let decoded = try JSONDecoder().decode(DaySchedule.self, from: JSONEncoder().encode(moving))
        XCTAssertEqual(column(of: decoded, in: [left, decoded]), 0)
    }

    func testPreviewTakesPriorityWithoutChangingCachedOrPersistedArrangements() {
        var stationary = schedule(start: 540, duration: 60)
        var moving = schedule(start: 550, duration: 60)
        stationary.setHorizontalPosition(0.1, at: .distantFuture)
        moving.setHorizontalPosition(0.1)
        let saved = DayPlanningPolicy.placements([stationary, moving], on: day)
        let preview = DayPlanningPolicy.placements([stationary, moving], on: day, prioritizing: moving.id)
        XCTAssertEqual(saved.first { $0.id == moving.id }?.column, 1)
        XCTAssertEqual(preview.first { $0.id == moving.id }?.column, 0)
        assertNoConflicts(preview)
        XCTAssertEqual(DayPlanningPolicy.placements([stationary, moving], on: day), saved)
    }

    func testChainedOverlapsDoNotCreateExtraColumnsAndTouchingEdgesBecomeFullWidth() {
        var schedules = [(480, 60), (510, 60), (540, 60), (600, 30)].map {
            schedule(start: $0.0, duration: $0.1)
        }
        schedules[1].setHorizontalPosition(1)
        let placements = DayPlanningPolicy.placements(schedules, on: day)
        XCTAssertEqual(placements.prefix(3).map(\.columnCount), [2, 2, 2])
        XCTAssertEqual(placements.last?.columnCount, 1)
        assertNoConflicts(placements)
    }

    func testPreferenceWorksAcrossMidnightAndDifferentOverlapCounts() {
        var night = schedule(start: 1380, duration: 120)
        night.setHorizontalPosition(0.95)
        let before = schedule(start: 1390, duration: 40)
        var next = schedule(start: 0, duration: 60)
        next.startDay = day.adding(days: 1)
        var third = next; third.id = UUID(); third.startMinute = 10
        let schedules = [night, before, next, third]
        XCTAssertEqual(column(of: night, in: schedules), 1)
        let placements = DayPlanningPolicy.placements(schedules, on: day.adding(days: 1))
        XCTAssertEqual(placements.first { $0.id == night.id }?.column, 2)
        assertNoConflicts(placements)
    }

    func testSourceOrderDoesNotChangeColumnPlacement() {
        var schedules = (0..<5).map { schedule(start: 540 + $0, duration: 60) }
        schedules[3].setHorizontalPosition(0.5)
        schedules[1].setHorizontalPosition(0.9)
        XCTAssertEqual(DayPlanningPolicy.placements(schedules, on: day),
                       DayPlanningPolicy.placements(schedules.reversed(), on: day))
    }

    func testPointerNormalizationUsesDayBoundsAndClampsOutsideEdges() {
        XCTAssertEqual(DayPlanningPolicy.horizontalPosition(x: 75, minX: 50, width: 100), 0.25)
        XCTAssertEqual(DayPlanningPolicy.horizontalPosition(x: 175, minX: 150, width: 100), 0.25)
        XCTAssertEqual(DayPlanningPolicy.horizontalPosition(x: -20, minX: 50, width: 100), 0)
        XCTAssertEqual(DayPlanningPolicy.horizontalPosition(x: 500, minX: 50, width: 100), 1)
        XCTAssertEqual(DayPlanningPolicy.horizontalPosition(x: 50, minX: 50, width: 0), 0.5)
    }

    func testHorizontalOnlyMovementPreservesMinutePreciseStartTime() {
        let original = schedule(start: 541, duration: 29)
        for dayDelta in [0, 2] {
            let moved = WeekSchedulePolicy.adjusted(original, mode: .move, dayDelta: dayDelta, minuteDelta: 0)
            XCTAssertEqual(moved.startDay, day.adding(days: dayDelta))
            XCTAssertEqual(moved.startMinute, 541)
            XCTAssertEqual(moved.durationMinutes, 29)
        }
    }

    func testOlderSchedulesDecodeWithoutPositionAndInvalidPositionIsRejected() throws {
        let original = schedule(start: 540, duration: 60)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "horizontalPosition")
        json.removeValue(forKey: "horizontalPositionUpdatedAt")
        let decoded = try JSONDecoder().decode(DaySchedule.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        for position in [-0.1, 1.1, .infinity, .nan] {
            var invalid = original
            invalid.horizontalPosition = position
            XCTAssertFalse(invalid.isValid)
        }
    }

    @MainActor
    func testPositionOnlyEditSupportsUndoRedoAndPersistence() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-overlap-\(UUID())/todos.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TodoStore(fileURL: url)
        let original = schedule(start: 540, duration: 60)
        XCTAssertTrue(store.upsertSchedule(original))
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        var moved = original; moved.setHorizontalPosition(0.9)
        undo.beginUndoGrouping(); XCTAssertTrue(store.upsertSchedule(moved)); undo.endUndoGrouping()
        undo.undo(); XCTAssertEqual(store.schedules, [original])
        undo.redo(); XCTAssertEqual(store.schedules, [moved])
        let flushed = await store.flushPersistence(); XCTAssertTrue(flushed)
        XCTAssertEqual(TodoStore(fileURL: url).schedules, [moved])
    }

    private func schedule(start: Int, duration: Int) -> DaySchedule {
        DaySchedule(startDay: day, startMinute: start, durationMinutes: duration,
                    content: .independent(title: "Arrangement", notes: ""))
    }

    private func column(of schedule: DaySchedule, in schedules: [DaySchedule]) -> Int? {
        DayPlanningPolicy.placements(schedules, on: day).first { $0.id == schedule.id }?.column
    }

    private func assertNoConflicts(_ placements: [DayPlanningPolicy.Placement],
                                   file: StaticString = #filePath, line: UInt = #line) {
        for first in placements {
            for second in placements where first.id != second.id && first.interval.overlaps(second.interval) {
                XCTAssertNotEqual(first.column, second.column, file: file, line: line)
            }
        }
    }
}
