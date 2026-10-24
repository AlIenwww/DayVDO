import XCTest
@testable import DayVDO

final class TodoDateFilterTests: XCTestCase {
    private let today = LocalDay(year: 2026, month: 10, day: 14)

    func testCustomRangeIncludesTouchingAndSpanningTaskDates() {
        var filter = TodoFilterState()
        filter.date = .custom(today...today.adding(days: 2))
        let dates = [(-5, -1, false), (-5, 0, true), (-5, 10, true), (2, 5, true), (3, 5, false)]
        for (start, end, expected) in dates {
            let item = TodoItem(title: "Range", startDate: today.adding(days: start).date(),
                                dueDate: today.adding(days: end).date())
            XCTAssertEqual(filter.includes(item, showCompletedPreference: true, today: today), expected)
        }
        XCTAssertFalse(filter.includes(TodoItem(title: "Undated"), showCompletedPreference: true))
        XCTAssertEqual(filter.activeCategoryCount, 1)
        filter.clear()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.date, .any)
    }

    func testUndatedAndOtherCriteriaCombineWithoutUsingCompletionDate() {
        var filter = TodoFilterState()
        filter.date = .undated
        filter.priorities = [.high]
        XCTAssertTrue(filter.includes(TodoItem(title: "Keep", priority: .high), showCompletedPreference: true))
        XCTAssertFalse(filter.includes(TodoItem(title: "Low", priority: .low), showCompletedPreference: true))
        XCTAssertFalse(filter.includes(TodoItem(title: "Dated", dueDate: today.date(), priority: .high),
                                       showCompletedPreference: true))
        filter.date = .today
        filter.statuses = [.completed]
        let completed = TodoItem(title: "Completed earlier", startDate: today.adding(days: -4).date(),
                                 dueDate: today.adding(days: 4).date(), priority: .high,
                                 isCompleted: true, completedAt: today.adding(days: -1).date())
        XCTAssertTrue(filter.includes(completed, showCompletedPreference: false, today: today))
    }

    func testRelativeRangesRespectWeekStartAndCalendarBoundaries() {
        let sunday = LocalDay(year: 2026, month: 10, day: 18)
        XCTAssertEqual(TodoDateFilter.thisWeek.range(today: sunday, startsOnMonday: true),
                       sunday.adding(days: -6)...sunday)
        XCTAssertEqual(TodoDateFilter.thisWeek.range(today: sunday, startsOnMonday: false),
                       sunday...sunday.adding(days: 6))
        let yearEnd = LocalDay(year: 2026, month: 12, day: 31)
        XCTAssertEqual(TodoDateFilter.nextWeek.range(today: yearEnd, startsOnMonday: true),
                       LocalDay(year: 2027, month: 1, day: 4)...LocalDay(year: 2027, month: 1, day: 10))
        XCTAssertEqual(TodoDateFilter.thisMonth.range(today: yearEnd, startsOnMonday: true),
                       LocalDay(year: 2026, month: 12, day: 1)...yearEnd)
        XCTAssertEqual(TodoDateFilter.thisMonth.range(today: .init(year: 2028, month: 2, day: 14), startsOnMonday: true),
                       LocalDay(year: 2028, month: 2, day: 1)...LocalDay(year: 2028, month: 2, day: 29))
        XCTAssertEqual(TodoDateFilter.tomorrow.range(today: yearEnd, startsOnMonday: true),
                       LocalDay(year: 2027, month: 1, day: 1)...LocalDay(year: 2027, month: 1, day: 1))
    }

    func testCalendarCacheIdentityRefreshesRelativeDatesAndWeekPreferences() {
        var filter = TodoFilterState()
        filter.date = .today
        let first = TodoFilterContext(filter: filter, showCompleted: true, today: today)
        let next = TodoFilterContext(filter: filter, showCompleted: true, today: today.adding(days: 1))
        XCTAssertNotEqual(first, next)
        filter.date = .thisWeek
        XCTAssertNotEqual(TodoFilterContext(filter: filter, showCompleted: true, startsOnMonday: true),
                          TodoFilterContext(filter: filter, showCompleted: true, startsOnMonday: false))
        filter.date = .custom(today...today.adding(days: 3))
        XCTAssertEqual(TodoFilterContext(filter: filter, showCompleted: true, today: today),
                       TodoFilterContext(filter: filter, showCompleted: true, today: today.adding(days: 1)))
    }

    @MainActor
    func testCalendarBarsInspectorAndLinkedSchedulesUseAssignedTodoDates() {
        let matching = TodoItem(title: "Matching", dueDate: today.date())
        let other = TodoItem(title: "Other", dueDate: today.adding(days: 5).date())
        var filter = TodoFilterState()
        filter.date = .today
        let context = TodoFilterContext(filter: filter, showCompleted: true, today: today)
        let snapshot = CalendarWindowSnapshot.build(key: .init(
            revision: 1, firstDay: today, lastDay: today.adding(days: 10),
            timeZoneIdentifier: "Asia/Shanghai", firstWeekday: 2, visibility: context
        ), items: [matching, other], tags: [])
        XCTAssertEqual(snapshot.rangedItems.map(\.id), [matching.id])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DateFilter-\(UUID()).json")
        let store = TodoStore(fileURL: url)
        store.upsert(matching); store.upsert(other)
        XCTAssertEqual(store.calendarItems(on: today.date(), visibility: context).map(\.id), [matching.id])
        let linked = DaySchedule(startDay: today.adding(days: 2), startMinute: 540, durationMinutes: 60, content: .todo(matching.id))
        let hidden = DaySchedule(startDay: today, startMinute: 600, durationMinutes: 60, content: .todo(other.id))
        let independent = DaySchedule(startDay: today, startMinute: 660, durationMinutes: 60,
                                      content: .independent(title: "Break", notes: ""))
        let result = CalendarWeekPresentationCache().value(for: .init(week: today, revision: 1, visibility: context),
            schedules: [linked, hidden, independent], preview: nil,
            todo: { id in [matching, other].first { $0.id == id } })
        XCTAssertEqual(Set(result.schedulesByID.keys), [linked.id, independent.id])
    }
}
