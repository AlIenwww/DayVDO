import Foundation
import XCTest
@testable import DayVDO

@MainActor
final class ScheduleDateChangeTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 5)

    private func makeStore() -> (TodoStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-DateChange-\(UUID())/todos.json")
        return (TodoStore(fileURL: url), url)
    }

    private func block(_ item: TodoItem, day: LocalDay, minute: Int = 600, duration: Int = 60) -> DaySchedule {
        DaySchedule(startDay: day, startMinute: minute, durationMinutes: duration, content: .todo(item.id))
    }

    func testKeepOnlyOutsideArrangementsUsesSavedContentAndRestoresWithUndo() async throws {
        let (store, url) = makeStore()
        let original = TodoItem(title: "Reading", notes: "Old notes", startDate: day.date(), dueDate: day.adding(days: 4).date())
        XCTAssertTrue(store.upsert(original))
        let early = block(original, day: day)
        let retained = block(original, day: day.adding(days: 1))
        let late = block(original, day: day.adding(days: 4))
        let independent = DaySchedule(startDay: day, startMinute: 900, durationMinutes: 30,
                                      content: .independent(title: "Lunch", notes: ""))
        let anotherTask = TodoItem(title: "Other", dueDate: day.date())
        XCTAssertTrue(store.upsert(anotherTask))
        let otherBlock = block(anotherTask, day: day)
        for schedule in [early, retained, late, independent, otherBlock] {
            XCTAssertTrue(store.upsertSchedule(schedule))
        }
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        var candidate = original
        candidate.startDay = day.adding(days: 1)
        candidate.dueDay = day.adding(days: 2)
        candidate.title = "  Math practice  "
        candidate.notes = "New notes"
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
        XCTAssertEqual(request.affectedSchedules, [early, late])
        XCTAssertFalse(store.upsert(candidate))
        XCTAssertEqual(store.item(withID: original.id), original)
        XCTAssertEqual(store.schedules, [early, retained, late, independent, otherBlock])
        undo.beginUndoGrouping()
        XCTAssertTrue(store.confirmDateChange(request, scheduleAction: .keepAsIndependent))
        undo.endUndoGrouping()
        var saved = candidate
        saved.title = "Math practice"
        var keptEarly = early
        var keptLate = late
        keptEarly.content = .independent(title: saved.title, notes: saved.notes)
        keptLate.content = keptEarly.content
        let expected = [keptEarly, retained, keptLate, independent, otherBlock]
        XCTAssertEqual(store.schedules, expected)
        XCTAssertEqual(store.item(withID: original.id), saved)
        XCTAssertEqual(store.schedules(for: original.id), [retained])
        XCTAssertEqual(store.scheduledMinutes(for: original.id), 60)
        XCTAssertFalse(store.planningItems(on: day, today: day).contains { $0.id == original.id })
        XCTAssertFalse(store.planningItems(on: day.adding(days: 4), today: day).contains { $0.id == original.id })
        XCTAssertTrue(store.planningItems(on: day.adding(days: 1), today: day).contains { $0.id == original.id })
        undo.undo()
        XCTAssertEqual(store.item(withID: original.id), original)
        XCTAssertEqual(store.schedules, [early, retained, late, independent, otherBlock])
        undo.redo()
        XCTAssertEqual(store.schedules, expected)
        let persisted = await store.flushPersistence()
        XCTAssertTrue(persisted)
        let loaded = TodoStore(fileURL: url)
        for _ in 0..<100 where loaded.isInitialLoading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(loaded.items, store.items)
        XCTAssertEqual(loaded.schedules, expected)
    }

    func testPartialOvernightArrangementsAreHandledWholeButMidnightEndIsExclusive() throws {
        let (store, _) = makeStore()
        let original = TodoItem(title: "Overnight", startDate: day.date(), dueDate: day.adding(days: 2).date())
        XCTAssertTrue(store.upsert(original))
        let crossesStart = block(original, day: day, minute: 1410, duration: 60)
        let endsAtOldMidnight = block(original, day: day, minute: 1410, duration: 30)
        let endsAtNewMidnight = block(original, day: day.adding(days: 1), minute: 1410, duration: 30)
        let crossesEnd = block(original, day: day.adding(days: 1), minute: 1410, duration: 60)
        for schedule in [crossesStart, endsAtOldMidnight, endsAtNewMidnight, crossesEnd] {
            XCTAssertTrue(store.upsertSchedule(schedule))
        }
        var candidate = original
        candidate.startDay = day.adding(days: 1)
        candidate.dueDay = candidate.startDay
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
        XCTAssertEqual(Set(request.affectedSchedules.map(\.id)), Set([crossesStart.id, endsAtOldMidnight.id, crossesEnd.id]))
        XCTAssertTrue(store.confirmDateChange(request, scheduleAction: .delete))
        XCTAssertEqual(store.schedules, [endsAtNewMidnight])
        XCTAssertFalse(store.planningItems(on: day, today: day).contains { $0.id == original.id })
    }

    func testExpandedDatesSaveWithoutPromptAndKeepAllArrangements() {
        let (store, _) = makeStore()
        let original = TodoItem(title: "Task", dueDate: day.date())
        XCTAssertTrue(store.upsert(original))
        let arrangement = block(original, day: day)
        XCTAssertTrue(store.upsertSchedule(arrangement))
        var candidate = original
        candidate.startDay = day.adding(days: -1)
        candidate.dueDay = day.adding(days: 1)
        XCTAssertNil(store.dateChangeConfirmation(for: candidate))
        XCTAssertTrue(store.upsert(candidate))
        XCTAssertEqual(store.schedules, [arrangement])
        candidate.title = "Renamed"
        XCTAssertNil(store.dateChangeConfirmation(for: candidate))
        XCTAssertTrue(store.upsert(candidate))
        XCTAssertEqual(store.schedules, [arrangement])
    }

    func testRemovingDatesHandlesAllArrangementsForEitherChoice() throws {
        for action in [TodoStore.DateChangeScheduleAction.keepAsIndependent, .delete] {
            let (store, _) = makeStore()
            let original = TodoItem(title: "Task", notes: "Notes", dueDate: day.date())
            XCTAssertTrue(store.upsert(original))
            let first = block(original, day: day)
            let second = block(original, day: day.adding(days: 1))
            XCTAssertTrue(store.upsertSchedule(first))
            XCTAssertTrue(store.upsertSchedule(second))
            var candidate = original
            candidate.startDay = nil
            candidate.dueDay = nil
            let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
            XCTAssertEqual(request.affectedSchedules, [first, second])
            XCTAssertTrue(store.confirmDateChange(request, scheduleAction: action))
            XCTAssertEqual(store.items, [candidate])
            XCTAssertTrue(store.schedules(for: original.id).isEmpty)
            switch action {
            case .delete: XCTAssertTrue(store.schedules.isEmpty)
            case .keepAsIndependent:
                XCTAssertEqual(store.schedules.map(\.id), [first.id, second.id])
                XCTAssertEqual(store.schedules.map(\.content), Array(repeating: .independent(title: "Task", notes: "Notes"), count: 2))
            }
            XCTAssertTrue(store.planningItems(on: day, today: day).isEmpty)
        }
    }

    func testMovingToYesterdayKeepsTodayOverdueVisibility() throws {
        let (store, _) = makeStore()
        let original = TodoItem(title: "Overdue", dueDate: day.date())
        XCTAssertTrue(store.upsert(original))
        let arrangement = block(original, day: day)
        XCTAssertTrue(store.upsertSchedule(arrangement))
        var candidate = original
        candidate.startDay = day.adding(days: -1)
        candidate.dueDay = candidate.startDay
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
        XCTAssertTrue(store.confirmDateChange(request, scheduleAction: .keepAsIndependent))
        XCTAssertEqual(store.planningItems(on: day, today: day).map(\.id), [original.id])
        let sections = PlanningTodoPanelPolicy.sections(items: store.planningItems(on: day, today: day),
                                                       schedules: store.schedules(on: day), showCompleted: true)
        XCTAssertEqual(sections.map(\.kind), [.unscheduled])
    }

    func testConfirmationRejectsChangesToEvenAnUnaffectedArrangement() throws {
        let (store, _) = makeStore()
        let original = TodoItem(title: "Task", startDate: day.date(), dueDate: day.adding(days: 1).date())
        XCTAssertTrue(store.upsert(original))
        let early = block(original, day: day)
        var retained = block(original, day: day.adding(days: 1))
        XCTAssertTrue(store.upsertSchedule(early))
        XCTAssertTrue(store.upsertSchedule(retained))
        var candidate = original
        candidate.startDay = candidate.dueDay
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
        retained.startMinute = 800
        XCTAssertTrue(store.upsertSchedule(retained))
        for action in [TodoStore.DateChangeScheduleAction.keepAsIndependent, .delete] {
            XCTAssertFalse(store.confirmDateChange(request, scheduleAction: action))
        }
        XCTAssertEqual(store.items, [original])
        XCTAssertEqual(store.schedules, [early, retained])
    }
}
