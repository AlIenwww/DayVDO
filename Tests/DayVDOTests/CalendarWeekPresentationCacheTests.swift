import Foundation
import XCTest
@testable import DayVDO

@MainActor
final class CalendarWeekPresentationCacheTests: XCTestCase {
    private let monday = LocalDay(year: 2026, month: 9, day: 21)

    func testDragPreviewDoesNotReplaceTheCachedWeek() {
        let cache = CalendarWeekPresentationCache()
        let schedule = DaySchedule(
            startDay: monday, startMinute: 540, durationMinutes: 60,
            content: .independent(title: "Plan", notes: "")
        )
        let key = CalendarWeekPresentationCache.Key(
            week: monday, revision: 1, showCompleted: true
        )

        let original = cache.value(
            for: key, schedules: [schedule], preview: nil,
            isCompletedTodo: { _ in false }
        )
        XCTAssertEqual(original.placementsByDay[monday]?.map(\.id), [schedule.id])

        var preview = schedule
        preview.startDay = monday.adding(days: 1)
        let dragged = cache.value(
            for: key, schedules: [schedule], preview: preview,
            isCompletedTodo: { _ in false }
        )
        XCTAssertTrue(dragged.placementsByDay[monday]?.isEmpty == true)
        XCTAssertEqual(
            dragged.placementsByDay[monday.adding(days: 1)]?.map(\.id),
            [schedule.id]
        )

        let restored = cache.value(
            for: key, schedules: [schedule], preview: nil,
            isCompletedTodo: { _ in false }
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
            for: .init(week: monday, revision: 1, showCompleted: false),
            schedules: [schedule], preview: nil,
            isCompletedTodo: { $0 == todoID }
        )
        XCTAssertTrue(hidden.placementsByDay[monday]?.isEmpty == true)

        let shown = cache.value(
            for: .init(week: monday, revision: 1, showCompleted: true),
            schedules: [schedule], preview: nil,
            isCompletedTodo: { $0 == todoID }
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
            for: .init(week: monday, revision: 1, showCompleted: true),
            schedules: [schedule], preview: nil,
            isCompletedTodo: { _ in false }
        )
        XCTAssertEqual(first.placementsByDay[monday]?.map(\.id), [schedule.id])

        var moved = schedule
        moved.startDay = monday.adding(days: 1)
        let updated = cache.value(
            for: .init(week: monday, revision: 2, showCompleted: true),
            schedules: [moved], preview: nil,
            isCompletedTodo: { _ in false }
        )
        XCTAssertTrue(updated.placementsByDay[monday]?.isEmpty == true)
        XCTAssertEqual(updated.placementsByDay[monday.adding(days: 1)]?.map(\.id), [schedule.id])
    }
}
