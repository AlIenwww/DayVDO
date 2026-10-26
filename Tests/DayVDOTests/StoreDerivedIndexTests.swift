import XCTest
@testable import DayVDO

@MainActor
final class StoreDerivedIndexTests: XCTestCase {
    func testScheduleQueriesFollowMoveRelinkUndoDeleteAndReload() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Index-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TodoStore(fileURL: file)
        let day = LocalDay(year: 2026, month: 10, day: 24)
        let first = TodoItem(title: "First"), second = TodoItem(title: "Second")
        store.upsert(first); store.upsert(second)
        var schedule = DaySchedule(startDay: day, startMinute: 1410, durationMinutes: 60, content: .todo(first.id))
        store.upsertSchedule(schedule)
        let original = schedule
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        assertQueries(store, around: day, todoIDs: [first.id, second.id])

        schedule.startDay = day.adding(days: 1)
        schedule.startMinute = 600
        schedule.durationMinutes = 120
        schedule.content = .todo(second.id)
        undo.beginUndoGrouping()
        XCTAssertTrue(store.upsertSchedule(schedule))
        undo.endUndoGrouping()
        XCTAssertEqual(store.schedule(withID: schedule.id), schedule)
        XCTAssertTrue(store.schedules(on: day).isEmpty)
        XCTAssertEqual(store.scheduledMinutes(for: first.id), 0)
        assertQueries(store, around: day, todoIDs: [first.id, second.id])
        undo.undo()
        XCTAssertEqual(store.schedule(withID: schedule.id), original)
        assertQueries(store, around: day, todoIDs: [first.id, second.id])
        undo.redo()
        assertQueries(store, around: day, todoIDs: [first.id, second.id])
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
        let reloaded = TodoStore(fileURL: file)
        assertQueries(reloaded, around: day, todoIDs: [first.id, second.id])
        XCTAssertEqual(reloaded.schedule(withID: schedule.id), schedule)
        undo.beginUndoGrouping()
        XCTAssertTrue(store.delete(second))
        undo.endUndoGrouping()
        XCTAssertNil(store.schedule(withID: schedule.id))
        assertQueries(store, around: day, todoIDs: [first.id, second.id])
        undo.undo()
        assertQueries(store, around: day, todoIDs: [first.id, second.id])
    }

    func testTaskOrderAndSummariesStayFreshWhenDifferentCollectionsChange() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Index-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TodoStore(fileURL: file)
        var project = TodoProject(title: "Project")
        store.upsertProject(project)
        let day = LocalDay(year: 2026, month: 10, day: 24)
        let tasks = (0..<5).map { TodoItem(title: "Task \($0)", dueDate: day.adding(days: $0).date(), projectID: project.id) }
        for task in tasks { store.upsert(task) }
        XCTAssertEqual(store.items(in: project).map(\.id), tasks.map(\.id))
        XCTAssertTrue(store.moveProjectItem(tasks[4].id, before: tasks[0].id, in: project.id))
        project = try XCTUnwrap(store.project(withID: project.id))
        XCTAssertEqual(store.items(in: project).first?.id, tasks[4].id)
        for task in tasks { store.setStatus(.completed, for: task) }
        XCTAssertTrue(store.projectIsCompleted(project))
        XCTAssertEqual(store.projectProgress(project).completed, tasks.count)
        XCTAssertEqual(store.items(in: project).first?.id, tasks[4].id)
        XCTAssertTrue(store.items(in: project).allSatisfy(\.isCompleted))
        store.settings.showCompleted = false
        XCTAssertTrue(store.visibleItems.isEmpty)
        store.settings.showCompleted = true
        XCTAssertEqual(store.visibleItems.count, tasks.count)
        XCTAssertTrue(store.deleteProject(project, strategy: .keepTasks))
        XCTAssertTrue(store.items(in: project).isEmpty)
        XCTAssertTrue(store.items.allSatisfy { $0.projectID == nil })
    }

    func testPlanningPreservesDateVisibleFirstWhenSortFieldsTie() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Index-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TodoStore(fileURL: file)
        let day = LocalDay(year: 2026, month: 10, day: 24)
        let timestamp = Date.now
        let scheduledOnly = TodoItem(title: "Scheduled", startDate: day.adding(days: 1).date(),
                                     dueDate: day.adding(days: 2).date(), createdAt: timestamp)
        let visible = TodoItem(title: "Date visible", startDate: day.date(),
                               dueDate: day.adding(days: 2).date(), createdAt: timestamp)
        store.upsert(scheduledOnly); store.upsert(visible)
        store.upsertSchedule(DaySchedule(startDay: day, startMinute: 600, durationMinutes: 30, content: .todo(scheduledOnly.id)))
        XCTAssertEqual(store.planningItems(on: day, today: day).map(\.id), [visible.id, scheduledOnly.id])
    }

    private func assertQueries(_ store: TodoStore, around day: LocalDay, todoIDs: [UUID],
                               file: StaticString = #filePath, line: UInt = #line) {
        for offset in -1...4 {
            let target = day.adding(days: offset)
            XCTAssertEqual(store.schedules(on: target), store.schedules.filter { $0.interval(on: target) != nil }, file: file, line: line)
        }
        for id in todoIDs {
            let reference = store.schedules.filter { $0.todoID == id }.sorted {
                if $0.startDay != $1.startDay { return $0.startDay < $1.startDay }
                return $0.startMinute < $1.startMinute
            }
            XCTAssertEqual(store.schedules(for: id), reference, file: file, line: line)
            XCTAssertEqual(store.scheduledMinutes(for: id), reference.reduce(0) { $0 + $1.durationMinutes }, file: file, line: line)
        }
        for schedule in store.schedules {
            XCTAssertEqual(store.schedule(withID: schedule.id), schedule, file: file, line: line)
        }
    }
}
