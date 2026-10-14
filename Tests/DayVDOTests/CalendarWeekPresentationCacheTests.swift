import Foundation
import XCTest
@testable import DayVDO

@MainActor
final class CalendarWeekPresentationCacheTests: XCTestCase {
    private let monday = LocalDay(year: 2026, month: 9, day: 21)

    func testNeighboringWeeksReusePlacementsInsteadOfEvictingEachOther() {
        let cache = CalendarWeekPresentationCache()
        let todo = TodoItem(title: "Cached")
        let schedules = (0..<3).map { offset in
            DaySchedule(startDay: monday.adding(days: offset * 7), startMinute: 540,
                durationMinutes: 30, content: .todo(todo.id))
        }
        var resolutions = 0
        for _ in 0..<10 {
            for offset in 0..<3 {
                _ = cache.value(for: .init(week: monday.adding(days: offset * 7), revision: 1,
                    visibility: .init(showCompleted: true)), schedules: schedules, preview: nil,
                    todo: { _ in resolutions += 1; return todo })
            }
        }
        XCTAssertEqual(resolutions, 3, "Rendering adjacent weeks must not recalculate each schedule every frame")
    }

    func testCreationPreviewParticipatesInOverlapWithoutPollutingTheCachedWeek() throws {
        let cache = CalendarWeekPresentationCache()
        let original = DaySchedule(startDay: monday, startMinute: 540, durationMinutes: 60,
                                   content: .independent(title: "Plan", notes: ""))
        var draft = DaySchedule(startDay: monday, startMinute: 550, durationMinutes: 30,
                                content: .independent(title: "", notes: ""))
        draft.setHorizontalPosition(0.95)
        let key = CalendarWeekPresentationCache.Key(week: monday, revision: 1, visibility: .init(showCompleted: true))
        _ = cache.value(for: key, schedules: [original], preview: nil, todo: { _ in nil })
        let preview = cache.value(for: key, schedules: [original], preview: draft,
                                  prioritizing: draft.id, todo: { _ in nil })
        let placements = try XCTUnwrap(preview.placementsByDay[monday])
        XCTAssertEqual(placements.first { $0.id == draft.id }?.column, 1)
        XCTAssertEqual(placements.first { $0.id == original.id }?.column, 0)
        XCTAssertTrue(placements.allSatisfy { $0.columnCount == 2 })
        let restored = cache.value(for: key, schedules: [original], preview: nil, todo: { _ in nil })
        XCTAssertEqual(restored.schedulesByID.count, 1)
        XCTAssertEqual(restored.placementsByDay[monday]?.first?.columnCount, 1)
    }

    func testHorizontalOnlyRevisionRefreshesTheCachedColumns() {
        let cache = CalendarWeekPresentationCache()
        let original = DaySchedule(startDay: monday, startMinute: 540, durationMinutes: 60,
                                   content: .independent(title: "Plan", notes: ""))
        var moving = DaySchedule(startDay: monday, startMinute: 550, durationMinutes: 30,
                                content: .independent(title: "Moving", notes: ""))
        let visibility = TodoFilterContext(showCompleted: true)
        _ = cache.value(for: .init(week: monday, revision: 1, visibility: visibility),
                        schedules: [original, moving], preview: nil, todo: { _ in nil })
        moving.setHorizontalPosition(0.1)
        let refreshed = cache.value(for: .init(week: monday, revision: 2, visibility: visibility),
                                    schedules: [original, moving], preview: nil, todo: { _ in nil })
        XCTAssertEqual(refreshed.placementsByDay[monday]?.first { $0.id == moving.id }?.column, 0)
        XCTAssertEqual(refreshed.placementsByDay[monday]?.first { $0.id == original.id }?.column, 1)
    }

    func testDragPreviewDoesNotReplaceTheCachedWeek() {
        let cache = CalendarWeekPresentationCache()
        let schedule = DaySchedule(
            startDay: monday, startMinute: 540, durationMinutes: 60,
            content: .independent(title: "Plan", notes: "")
        )
        let key = CalendarWeekPresentationCache.Key(
            week: monday, revision: 1, visibility: .init(showCompleted: true)
        )

        let original = cache.value(
            for: key, schedules: [schedule], preview: nil,
            todo: { _ in nil }
        )
        XCTAssertEqual(original.placementsByDay[monday]?.map(\.id), [schedule.id])

        var preview = schedule
        preview.startDay = monday.adding(days: 1)
        let dragged = cache.value(
            for: key, schedules: [schedule], preview: preview,
            todo: { _ in nil }
        )
        XCTAssertTrue(dragged.placementsByDay[monday]?.isEmpty == true)
        XCTAssertEqual(
            dragged.placementsByDay[monday.adding(days: 1)]?.map(\.id),
            [schedule.id]
        )

        let restored = cache.value(
            for: key, schedules: [schedule], preview: nil,
            todo: { _ in nil }
        )
        XCTAssertEqual(restored.placementsByDay[monday]?.map(\.id), [schedule.id])
        XCTAssertTrue(restored.placementsByDay[monday.adding(days: 1)]?.isEmpty == true)
    }

    func testCompletionPreferenceInvalidatesCachedPlacements() {
        let cache = CalendarWeekPresentationCache()
        let todoID = UUID()
        let schedule = DaySchedule(
            startDay: monday, startMinute: 540, durationMinutes: 60,
            content: .todo(todoID)
        )

        let hidden = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: false)),
            schedules: [schedule], preview: nil,
            todo: { $0 == todoID ? TodoItem(id: todoID, title: "Completed", isCompleted: true) : nil }
        )
        XCTAssertTrue(hidden.placementsByDay[monday]?.isEmpty == true)

        let shown = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: true)),
            schedules: [schedule], preview: nil,
            todo: { $0 == todoID ? TodoItem(id: todoID, title: "Completed", isCompleted: true) : nil }
        )
        XCTAssertEqual(shown.placementsByDay[monday]?.map(\.id), [schedule.id])
    }

    func testContentRevisionRefreshesSchedulePosition() {
        let cache = CalendarWeekPresentationCache()
        let schedule = DaySchedule(
            startDay: monday, startMinute: 540, durationMinutes: 60,
            content: .independent(title: "Plan", notes: "")
        )
        let first = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: true)),
            schedules: [schedule], preview: nil,
            todo: { _ in nil }
        )
        XCTAssertEqual(first.placementsByDay[monday]?.map(\.id), [schedule.id])

        var moved = schedule
        moved.startDay = monday.adding(days: 1)
        let updated = cache.value(
            for: .init(week: monday, revision: 2, visibility: .init(showCompleted: true)),
            schedules: [moved], preview: nil,
            todo: { _ in nil }
        )
        XCTAssertTrue(updated.placementsByDay[monday]?.isEmpty == true)
        XCTAssertEqual(updated.placementsByDay[monday.adding(days: 1)]?.map(\.id), [schedule.id])
    }
}
