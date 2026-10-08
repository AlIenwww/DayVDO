import Foundation
import XCTest
@testable import DayVDO

final class CalendarFilterTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 1)

    private func key(_ context: TodoFilterContext, revision: UInt64 = 1) -> CalendarWindowSnapshot.Key {
        .init(revision: revision, firstDay: day.adding(days: -7), lastDay: day.adding(days: 7),
              timeZoneIdentifier: "Asia/Shanghai", firstWeekday: 2, visibility: context)
    }

    func testUnassignedAndUntaggedStillRequireEveryOtherCategory() {
        let tagID = UUID()
        var filter = TodoFilterState()
        filter.includesUnassignedProject = true
        filter.tagIDs = [tagID]
        filter.priorities = [.high]
        filter.urgencies = [.today]
        filter.overdueOnly = true
        let matching = TodoItem(title: "Match", dueDate: day.adding(days: -1).date(),
                                priority: .high, urgency: .today, tagID: tagID)
        let context = TodoFilterContext(filter: filter, showCompleted: true, today: day)
        XCTAssertTrue(context.includes(matching))
        var wrong = matching
        wrong.tagID = nil
        XCTAssertFalse(context.includes(wrong))
        wrong = matching; wrong.priority = .low
        XCTAssertFalse(context.includes(wrong))
        wrong = matching; wrong.dueDay = day
        XCTAssertFalse(context.includes(wrong))

        filter.tagIDs = []; filter.includesUntagged = true
        let untaggedContext = TodoFilterContext(filter: filter, showCompleted: true, today: day)
        var untagged = matching; untagged.tagID = nil
        XCTAssertTrue(untaggedContext.includes(untagged))
        untagged.urgency = .canWait
        XCTAssertFalse(untaggedContext.includes(untagged))
    }

    @MainActor
    func testCompletedSelectionOverridesPreferenceInSnapshotAndInspector() {
        var filter = TodoFilterState(); filter.statuses = [.completed]
        let context = TodoFilterContext(filter: filter, showCompleted: false, today: day)
        let completed = TodoItem(title: "Done", startDate: day.adding(days: -2).date(),
                                 dueDate: day.adding(days: 2).date(), isCompleted: true,
                                 completedAt: day.adding(days: -1).date())
        let active = TodoItem(title: "Active", dueDate: day.date())
        let snapshot = CalendarWindowSnapshot.build(key: key(context), items: [completed, active], tags: [])
        XCTAssertEqual(snapshot.items(on: day).map(\.id), [completed.id])
        XCTAssertEqual(snapshot.items(on: day.adding(days: 2)).map(\.id), [completed.id])
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("CalendarFilter-\(UUID()).json"))
        store.settings.showCompleted = false
        _ = store.upsert(completed); _ = store.upsert(active)
        XCTAssertEqual(store.calendarItems(on: day.date(), visibility: context).map(\.id), [completed.id])
        XCTAssertEqual(store.calendarItems(on: day.date()).map(\.id), [active.id])
    }

    func testOverdueContextChangesAtMidnightAndRetainsAssignedDates() {
        var filter = TodoFilterState(); filter.overdueOnly = true
        let before = TodoFilterContext(filter: filter, showCompleted: true, today: day)
        let after = TodoFilterContext(filter: filter, showCompleted: true, today: day.adding(days: 1))
        let item = TodoItem(title: "Due today", dueDate: day.date())
        XCTAssertFalse(key(before).covers(key(after)))
        XCTAssertTrue(CalendarWindowSnapshot.build(key: key(before), items: [item], tags: []).rangedItems.isEmpty)
        let snapshot = CalendarWindowSnapshot.build(key: key(after), items: [item], tags: [])
        XCTAssertEqual(snapshot.items(on: day).map(\.id), [item.id])
        XCTAssertTrue(snapshot.items(on: day.adding(days: 1)).isEmpty)
        XCTAssertEqual(TodoFilterContext(showCompleted: true, today: day),
                       TodoFilterContext(showCompleted: true, today: day.adding(days: 1)))
    }

    @MainActor
    func testRapidFilterChangePublishesOnlyLatestCriteria() async {
        let cache = CalendarWindowCache()
        let projectA = UUID(), projectB = UUID()
        let items = (0..<1_000).map { TodoItem(title: "Task \($0)", dueDate: day.date(), projectID: $0 % 2 == 0 ? projectA : projectB) }
        var a = TodoFilterState(); a.projectIDs = [projectA]
        var b = TodoFilterState(); b.projectIDs = [projectB]
        let aKey = key(.init(filter: a, showCompleted: true))
        let bKey = key(.init(filter: b, showCompleted: true))
        cache.prepare(.init(key: aKey, items: items, tags: []))
        cache.prepare(.init(key: bKey, items: items, tags: []))
        let ready = await cache.waitForSnapshot(covering: bKey, until: .now + .seconds(3))
        XCTAssertTrue(ready)
        XCTAssertEqual(cache.snapshot?.key, bKey)
        XCTAssertEqual(cache.snapshot?.items(on: day).map(\.id).count, 500)
        XCTAssertFalse(cache.hasSnapshot(covering: aKey))

        // Returning to an already cached filter must also cancel the in-flight other filter.
        cache.prepare(.init(key: aKey, items: items, tags: []))
        cache.prepare(.init(key: bKey, items: items, tags: []))
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(cache.snapshot?.key, bKey)
    }

    @MainActor
    func testSchedulesUseTodoAttributesOutsideWeekAndKeepIndependentBlocks() {
        let cache = CalendarWeekPresentationCache()
        let projectA = UUID(), projectB = UUID()
        let matching = TodoItem(title: "Match", dueDate: day.adding(days: -30).date(), projectID: projectA)
        let other = TodoItem(title: "Other", dueDate: day.date(), projectID: projectB)
        let linked = DaySchedule(startDay: day, startMinute: 540, durationMinutes: 60, content: .todo(matching.id))
        let hidden = DaySchedule(startDay: day, startMinute: 600, durationMinutes: 60, content: .todo(other.id))
        let independent = DaySchedule(startDay: day, startMinute: 660, durationMinutes: 60, content: .independent(title: "Break", notes: ""))
        var filter = TodoFilterState(); filter.projectIDs = [projectA]
        let context = TodoFilterContext(filter: filter, showCompleted: false, today: day)
        let result = cache.value(for: .init(week: day, revision: 1, visibility: context),
                                 schedules: [linked, hidden, independent], preview: nil,
                                 todo: { id in [matching, other].first { $0.id == id } })
        XCTAssertEqual(Set(result.schedulesByID.keys), [linked.id, independent.id])
        XCTAssertEqual(Set(result.placementsByDay[day]?.map(\.id) ?? []), [linked.id, independent.id])
        let cleared = cache.value(for: .init(week: day, revision: 1, visibility: .init(showCompleted: false)),
                                  schedules: [linked, hidden, independent], preview: nil,
                                  todo: { id in [matching, other].first { $0.id == id } })
        XCTAssertEqual(cleared.schedulesByID.count, 3)
    }

    @MainActor
    func testLinkedCompletedScheduleAndEditedTodoRefreshVisibility() {
        let cache = CalendarWeekPresentationCache()
        var item = TodoItem(title: "Done", isCompleted: true)
        let schedule = DaySchedule(startDay: day, startMinute: 540, durationMinutes: 60, content: .todo(item.id))
        var filter = TodoFilterState(); filter.statuses = [.completed]
        let context = TodoFilterContext(filter: filter, showCompleted: false, today: day)
        let visible = cache.value(for: .init(week: day, revision: 1, visibility: context),
                                  schedules: [schedule], preview: nil, todo: { _ in item })
        XCTAssertEqual(visible.schedulesByID.count, 1)
        item.status = .inProgress
        let hidden = cache.value(for: .init(week: day, revision: 2, visibility: context),
                                 schedules: [schedule], preview: nil, todo: { _ in item })
        XCTAssertTrue(hidden.schedulesByID.isEmpty)
        item.status = .completed
        let undone = cache.value(for: .init(week: day, revision: 3, visibility: context),
                                 schedules: [schedule], preview: nil, todo: { _ in item })
        XCTAssertEqual(undone.schedulesByID.count, 1)
    }

    func testPreparedLayoutsAndOverflowOnlyContainMatchingTasks() {
        let project = UUID()
        let week = LocalDay(year: 2026, month: 9, day: 28)
        let matching = TodoItem(title: "Keep", startDate: week.date(), dueDate: day.date(), projectID: project)
        let others = (0..<20).map { TodoItem(title: "Other \($0)", dueDate: day.date()) }
        var filter = TodoFilterState(); filter.projectIDs = [project]
        let filtered = CalendarWindowSnapshot.build(key: key(.init(filter: filter, showCompleted: true)),
                                                    items: others + [matching], tags: [])
        XCTAssertEqual(filtered.items(inWeek: week).map(\.id), [matching.id])
        XCTAssertEqual(filtered.dateLayoutsByWeek[week]?.segments.map(\.id), [matching.id])
        XCTAssertFalse(filtered.key.matchesContent(of: key(.init(showCompleted: true))))
    }
}
