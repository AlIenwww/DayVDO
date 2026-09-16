import Foundation
import XCTest
@testable import DayVDO

final class TaskStatusAndDateRangeTests: XCTestCase {
    private let start = LocalDay(year: 2026, month: 9, day: 7)
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testDateRangeIsInclusiveAndOverdueAppearsOnlyOnActualToday() {
        let item = TodoItem(
            title: "Three days",
            startDate: start.date(timeZone: utc),
            dueDate: start.adding(days: 2).date(timeZone: utc)
        )
        let today = start.adding(days: 5)

        XCTAssertTrue(TaskDateRangePolicy.isVisible(item, on: start, today: today, includeCompleted: false, timeZone: utc))
        XCTAssertTrue(TaskDateRangePolicy.isVisible(item, on: start.adding(days: 1), today: today, includeCompleted: false, timeZone: utc))
        XCTAssertTrue(TaskDateRangePolicy.isVisible(item, on: start.adding(days: 2), today: today, includeCompleted: false, timeZone: utc))
        XCTAssertFalse(TaskDateRangePolicy.isVisible(item, on: start.adding(days: 3), today: today, includeCompleted: false, timeZone: utc))
        XCTAssertTrue(TaskDateRangePolicy.isVisible(item, on: today, today: today, includeCompleted: false, timeZone: utc))
        XCTAssertTrue(TaskDateRangePolicy.isOverdue(item, on: today, today: today))
        XCTAssertFalse(TaskDateRangePolicy.isVisible(item, on: today.adding(days: 1), today: today, includeCompleted: false, timeZone: utc))
    }

    func testCompletedRangeStopsAtCompletionDayAndUndatedTaskStaysOut() {
        var item = TodoItem(
            title: "Early finish",
            startDate: start.date(timeZone: utc),
            dueDate: start.adding(days: 4).date(timeZone: utc),
            status: .completed,
            completedAt: start.adding(days: 2).date(timeZone: utc)
        )

        XCTAssertEqual(
            TaskDateRangePolicy.visibleRange(for: item, includeCompleted: true, timeZone: utc),
            start...start.adding(days: 2)
        )
        XCTAssertNil(TaskDateRangePolicy.visibleRange(for: item, includeCompleted: false, timeZone: utc))
        XCTAssertFalse(TaskDateRangePolicy.isVisible(item, on: start.adding(days: 3), today: start.adding(days: 3), includeCompleted: true, timeZone: utc))

        item.startDay = nil
        item.dueDay = nil
        item.status = .notStarted
        item.completedAt = nil
        XCTAssertNil(TaskDateRangePolicy.visibleRange(for: item, includeCompleted: true, timeZone: utc))
        XCTAssertFalse(TaskDateRangePolicy.isVisible(item, on: start, today: start, includeCompleted: true, timeZone: utc))
    }

    func testCalendarKeepsCompletedTaskAcrossItsOriginalDateRange() {
        let item = TodoItem(
            title: "Keep on calendar",
            startDate: start.date(timeZone: utc),
            dueDate: start.adding(days: 4).date(timeZone: utc),
            status: .completed,
            completedAt: start.adding(days: 1).date(timeZone: utc)
        )

        XCTAssertFalse(
            TaskDateRangePolicy.isVisible(
                item,
                on: start.adding(days: 4),
                today: start,
                includeCompleted: true,
                timeZone: utc
            )
        )
        XCTAssertTrue(
            TaskDateRangePolicy.isVisibleInCalendar(
                item,
                on: start.adding(days: 4),
                today: start,
                includeCompleted: true,
                timeZone: utc
            )
        )
        XCTAssertFalse(
            TaskDateRangePolicy.isVisibleInCalendar(
                item,
                on: start.adding(days: 5),
                today: start,
                includeCompleted: true,
                timeZone: utc
            )
        )
        XCTAssertFalse(
            TaskDateRangePolicy.isVisibleInCalendar(
                item,
                on: start.adding(days: 2),
                today: start,
                includeCompleted: false,
                timeZone: utc
            )
        )
    }

    func testCalendarDoesNotCopyOverdueTasksIntoTodayCell() {
        let today = start.adding(days: 6)
        let singleDay = TodoItem(title: "Single overdue", dueDate: start.date(timeZone: utc))
        let ranged = TodoItem(
            title: "Ranged overdue",
            startDate: start.date(timeZone: utc),
            dueDate: start.adding(days: 2).date(timeZone: utc)
        )
        for item in [singleDay, ranged] {
            XCTAssertTrue(TaskDateRangePolicy.isVisible(item, on: today, today: today, includeCompleted: false, timeZone: utc))
            XCTAssertFalse(TaskDateRangePolicy.isVisibleInCalendar(item, on: today, today: today, includeCompleted: false, timeZone: utc))
            XCTAssertFalse(TaskDateRangePolicy.isVisibleInCalendar(item, on: today.adding(days: 1), today: today, includeCompleted: false, timeZone: utc))
        }
        XCTAssertTrue(TaskDateRangePolicy.isVisibleInCalendar(singleDay, on: start, today: today, includeCompleted: false, timeZone: utc))
        XCTAssertFalse(TaskDateRangePolicy.isVisibleInCalendar(singleDay, on: start.adding(days: 1), today: today, includeCompleted: false, timeZone: utc))
        for offset in 0...2 {
            XCTAssertTrue(TaskDateRangePolicy.isVisibleInCalendar(ranged, on: start.adding(days: offset), today: today, includeCompleted: false, timeZone: utc))
        }
    }

    @MainActor
    func testCalendarStoreAndTodayPanelUseSeparateOverduePolicies() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let today = LocalDay(.now)
        let assignedDay = today.adding(days: -3)
        let item = TodoItem(title: "Overdue", dueDate: assignedDay.date())
        XCTAssertTrue(store.upsert(item))

        XCTAssertEqual(store.calendarItems(on: assignedDay.date()).map(\.id), [item.id])
        XCTAssertTrue(store.calendarItems(on: today.date()).isEmpty)
        XCTAssertEqual(store.planningItems(on: today, today: today).map(\.id), [item.id])
    }

    @MainActor
    func testCalendarSidebarQueryKeepsCompletedTaskOnOriginalEndDate() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let item = TodoItem(
            title: "Finished early",
            startDate: start.date(),
            dueDate: start.adding(days: 4).date(),
            status: .completed,
            completedAt: start.adding(days: 1).date()
        )
        XCTAssertTrue(store.upsert(item))
        XCTAssertEqual(store.calendarItems(on: start.adding(days: 4).date()).map(\.id), [item.id])
        XCTAssertTrue(store.calendarItems(on: start.adding(days: 5).date()).isEmpty)
        store.settings.showCompleted = false
        XCTAssertTrue(store.calendarItems(on: start.adding(days: 4).date()).isEmpty)
    }

    func testSelectedTaskDateShowsSameDayEndAndSyncsUntilEndIsEdited() {
        let item = TodoItem(title: "One day", dueDate: start.date(timeZone: utc))
        var input = TaskDateInput(item: item)
        XCTAssertTrue(input.hasDate)
        XCTAssertTrue(input.showsEndDate)
        XCTAssertFalse(input.endDateWasEdited)
        XCTAssertEqual(input.startDay, item.startDay)
        XCTAssertEqual(input.deadline, item.dueDay)

        let chosen = start.adding(days: 1)
        input.chooseTaskDay(chosen)
        XCTAssertEqual(input.applying(to: item).startDay, chosen)
        XCTAssertEqual(input.applying(to: item).dueDay, chosen)

        input.chooseEndDay(start.adding(days: 3))
        XCTAssertTrue(input.endDateWasEdited)
        XCTAssertTrue(input.isValid)
        XCTAssertEqual(input.applying(to: item).dueDay, start.adding(days: 3))
        input.chooseTaskDay(start.adding(days: 4))
        XCTAssertEqual(input.deadline, start.adding(days: 3))
        XCTAssertFalse(input.isValid)
        XCTAssertFalse(input.applying(to: item).hasValidDateRange)
    }

    func testExistingRangeShowsEndImmediatelyAndPreservesItWhenTaskDateChanges() {
        let item = TodoItem(
            title: "Several days",
            startDate: start.date(timeZone: utc),
            dueDate: start.adding(days: 4).date(timeZone: utc)
        )
        var input = TaskDateInput(item: item)
        XCTAssertTrue(input.showsEndDate)
        XCTAssertTrue(input.endDateWasEdited)
        input.chooseTaskDay(start.adding(days: 2))
        XCTAssertEqual(input.deadline, start.adding(days: 4))
        XCTAssertTrue(input.isValid)

        input.setHasDate(false, defaultDay: start)
        XCTAssertNil(input.applying(to: item).startDay)
        XCTAssertNil(input.applying(to: item).dueDay)
        input.setHasDate(true, defaultDay: start.adding(days: 8))
        XCTAssertEqual(input.startDay, start.adding(days: 2))
        XCTAssertEqual(input.deadline, start.adding(days: 4))
        XCTAssertTrue(input.showsEndDate)
    }

    func testUndatedInputPrefillsTodayButRevealsEndOnlyAfterConfirmation() {
        let item = TodoItem(title: "Undated")
        var input = TaskDateInput(item: item)
        XCTAssertFalse(input.hasDate)
        XCTAssertNil(input.applying(to: item).startDay)
        XCTAssertNil(input.applying(to: item).dueDay)

        input.setHasDate(true, defaultDay: start)
        XCTAssertEqual(input.startDay, start)
        XCTAssertEqual(input.deadline, start)
        XCTAssertFalse(input.showsEndDate)
        XCTAssertTrue(input.isValid)
        XCTAssertEqual(input.applying(to: item).startDay, start)
        XCTAssertEqual(input.applying(to: item).dueDay, start)

        // Confirming the already-prefilled day must reveal the end field too.
        input.confirmTaskDay()
        XCTAssertTrue(input.showsEndDate)
        input.chooseTaskDay(start.adding(days: 1))
        XCTAssertEqual(input.deadline, start.adding(days: 1))
        input.chooseEndDay(start.adding(days: 3))
        XCTAssertEqual(input.deadline, start.adding(days: 3))
        input.setHasDate(false, defaultDay: start)
        XCTAssertFalse(input.showsEndDate)
        XCTAssertNil(input.applying(to: item).startDay)
        XCTAssertNil(input.applying(to: item).dueDay)
    }

    @MainActor
    func testThreeStatusesRestoreThePreviousIncompleteStateAndSupportUndo() throws {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let item = TodoItem(title: "Work", dueDate: start.date(timeZone: utc))
        XCTAssertTrue(store.upsert(item))
        XCTAssertTrue(store.setStatus(.inProgress, for: item))
        XCTAssertEqual(store.items.first?.status, .inProgress)

        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        undo.beginUndoGrouping()
        XCTAssertTrue(store.toggle(item))
        undo.endUndoGrouping()
        XCTAssertEqual(store.items.first?.status, .completed)
        XCTAssertEqual(store.items.first?.previousIncompleteStatus, .inProgress)
        XCTAssertNotNil(store.items.first?.completedAt)

        undo.undo()
        XCTAssertEqual(store.items.first?.status, .inProgress)
        XCTAssertNil(store.items.first?.completedAt)
        undo.redo()
        XCTAssertEqual(store.items.first?.status, .completed)

        store.undoManager = nil
        XCTAssertTrue(store.toggle(item))
        XCTAssertEqual(store.items.first?.status, .inProgress)
        XCTAssertNil(store.items.first?.completedAt)
    }

    @MainActor
    func testPlanningUnionDeduplicatesRangeAndScheduleAndGroupsOnlyBySelectedDay() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let item = TodoItem(
            title: "Ranged",
            startDate: start.date(timeZone: utc),
            dueDate: start.adding(days: 2).date(timeZone: utc)
        )
        XCTAssertTrue(store.upsert(item))
        let laterDay = start.adding(days: 8)
        let laterBlock = DaySchedule(
            startDay: laterDay,
            startMinute: 540,
            durationMinutes: 30,
            content: .todo(item.id)
        )
        XCTAssertTrue(store.upsertSchedule(laterBlock))

        let insideRange = store.planningItems(on: start.adding(days: 1), today: start)
        XCTAssertEqual(insideRange.map(\.id), [item.id])
        XCTAssertEqual(
            PlanningTodoPanelPolicy.sections(
                items: insideRange,
                schedules: store.schedules(on: start.adding(days: 1)),
                showCompleted: true
            ).map(\.kind),
            [.unscheduled]
        )

        let scheduledOutsideRange = store.planningItems(on: laterDay, today: start)
        XCTAssertEqual(scheduledOutsideRange.map(\.id), [item.id])
        XCTAssertEqual(
            PlanningTodoPanelPolicy.sections(
                items: scheduledOutsideRange,
                schedules: store.schedules(on: laterDay),
                showCompleted: true
            ).map(\.kind),
            [.scheduled]
        )
    }

    @MainActor
    func testInvalidOrPartialDateRangesCannotBeSaved() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        var reversed = TodoItem(
            title: "Invalid",
            startDate: start.adding(days: 1).date(timeZone: utc),
            dueDate: start.date(timeZone: utc)
        )
        XCTAssertFalse(reversed.hasValidDateRange)
        XCTAssertFalse(store.upsert(reversed))

        reversed.startDay = start
        reversed.dueDay = nil
        XCTAssertFalse(reversed.hasValidDateRange)
        XCTAssertFalse(store.upsert(reversed))
        XCTAssertTrue(store.items.isEmpty)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-TaskRangeTests-\(UUID()).json")
    }
}
