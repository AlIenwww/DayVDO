import Foundation
import XCTest
@testable import DayVDO

final class DayPlanningTests: XCTestCase {
    private let friday = LocalDay(year: 2026, month: 9, day: 4)

    func testCrossMidnightClippingAndExactMidnightEnd() {
        var value = DaySchedule(startDay: friday, startMinute: 1380, durationMinutes: 120,
                                content: .independent(title: "Evening", notes: ""))
        XCTAssertEqual(value.interval(on: friday), 1380..<1440)
        XCTAssertEqual(value.interval(on: friday.adding(days: 1)), 0..<60)
        XCTAssertNil(value.interval(on: friday.adding(days: -1)))
        XCTAssertNil(value.interval(on: friday.adding(days: 2)))
        value.durationMinutes = 60
        XCTAssertNil(value.interval(on: friday.adding(days: 1)))
        value.durationMinutes = 1440
        XCTAssertEqual(value.interval(on: friday.adding(days: 1)), 0..<1380)
        XCTAssertTrue(value.isValid)
        value.durationMinutes += 1
        XCTAssertFalse(value.isValid)
    }

    func testOverlapColumnsSeparateConflictsButNotTouchingEdges() {
        let blocks = [(480, 60), (510, 60), (540, 60), (600, 30)].map {
            DaySchedule(startDay: friday, startMinute: $0.0, durationMinutes: $0.1,
                        content: .independent(title: "Plan", notes: ""))
        }
        let result = DayPlanningPolicy.placements(blocks, on: friday)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.last?.columnCount, 1)
        for a in result {
            for b in result where a.id != b.id && a.interval.overlaps(b.interval) {
                XCTAssertNotEqual(a.column, b.column)
                XCTAssertEqual(a.columnCount, b.columnCount)
            }
        }
        XCTAssertEqual(result.prefix(3).map(\.columnCount), [2, 2, 2])
    }

    func testEstimatesAndMinutePrecision() {
        XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: nil, scheduled: 90), 30)
        XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: 60, scheduled: 30), 30)
        XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: 60, scheduled: 60), 30)
        XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: 3000, scheduled: 0), 1440)
        XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: 31, scheduled: 30), 1)
        XCTAssertEqual(DayPlanningPolicy.snapped(482), 480)
        XCTAssertEqual(DayPlanningPolicy.snapped(484), 485)
    }

    func testInitialTimelinePositionUsesEarliestVisibleArrangement() {
        let late = DaySchedule(startDay: friday, startMinute: 900, durationMinutes: 60,
                               content: .independent(title: "Afternoon", notes: ""))
        let early = DaySchedule(startDay: friday, startMinute: 547, durationMinutes: 30,
                                content: .todo(UUID()))
        let anotherDay = DaySchedule(startDay: friday.adding(days: -1), startMinute: 60,
                                     durationMinutes: 30, content: .todo(UUID()))
        XCTAssertEqual(DayPlanningPolicy.initialScrollMinute(schedules: [late, anotherDay, early], on: friday), 547)
        XCTAssertEqual(DayPlanningPolicy.initialScrollMinute(schedules: [anotherDay], on: friday), 0)
        XCTAssertEqual(DayPlanningPolicy.initialScrollMinute(schedules: [], on: friday), 0)

        let overnight = DaySchedule(startDay: friday.adding(days: -1), startMinute: 1380,
                                    durationMinutes: 120, content: .todo(UUID()))
        XCTAssertEqual(DayPlanningPolicy.initialScrollMinute(schedules: [late, overnight, early], on: friday), 0)
    }

    func testInProgressUsesCurrentDayAndHalfOpenScheduleInterval() {
        let placement = DayPlanningPolicy.Placement(
            id: UUID(),
            interval: 540..<600,
            column: 0,
            columnCount: 1
        )
        XCTAssertFalse(DayPlanningPolicy.isInProgress(placement, at: 539, onCurrentDay: true))
        XCTAssertTrue(DayPlanningPolicy.isInProgress(placement, at: 540, onCurrentDay: true))
        XCTAssertTrue(DayPlanningPolicy.isInProgress(placement, at: 599, onCurrentDay: true))
        XCTAssertFalse(DayPlanningPolicy.isInProgress(placement, at: 600, onCurrentDay: true))
        XCTAssertFalse(DayPlanningPolicy.isInProgress(placement, at: 570, onCurrentDay: false))
    }

    func testDragSnapsToLegalGridAtDayAndDurationBoundaries() {
        XCTAssertEqual(DayPlanningPolicy.snapped(1442, within: 0...1439), 1435)
        XCTAssertEqual(DayPlanningPolicy.snapped(-20, within: 0...1439), 0)
        XCTAssertEqual(DayPlanningPolicy.snapped(721, within: 722...2161), 725)
        XCTAssertEqual(DayPlanningPolicy.snapped(3000, within: 722...2161), 2160)
        XCTAssertEqual(DayPlanningPolicy.snapped(723, within: 0...722), 720)
        // A precise 24-hour plan ending at 23:59 has no legal grid-aligned start.
        XCTAssertNil(DayPlanningPolicy.snapped(1435, within: 1439...1439))
    }

    func testEscapeStaysCancelledThroughRepeatsUntilMouseRelease() {
        var cancellation = TimelineDragCancellation()
        cancellation.cancel(isDragging: true)
        XCTAssertTrue(cancellation.isSuppressed)
        // Clearing the preview removes the active interaction, but a repeated
        // Escape or an early gesture-end callback must not restart movement.
        cancellation.cancel(isDragging: false)
        XCTAssertFalse(cancellation.observeMouseButton(isPressed: true))
        XCTAssertTrue(cancellation.isSuppressed)
        XCTAssertTrue(cancellation.observeMouseButton(isPressed: false))
        XCTAssertFalse(cancellation.isSuppressed)
        cancellation.cancel(isDragging: false)
        XCTAssertFalse(cancellation.isSuppressed)
    }

    func testPlanningPanelGroupsCompactRowsByScheduleAndCompletion() {
        XCTAssertTrue(PlanningTodoSectionKind.unscheduled.isExpandedByDefault)
        XCTAssertTrue(PlanningTodoSectionKind.scheduled.isExpandedByDefault)
        XCTAssertTrue(PlanningTodoSectionKind.completed.isExpandedByDefault)

        let unscheduled = TodoItem(title: "Inbox", dueDate: friday.date())
        let scheduled = TodoItem(title: "Planned", dueDate: friday.date())
        var completed = TodoItem(title: "Done", dueDate: friday.date())
        completed.isCompleted = true
        let block = DaySchedule(startDay: friday, startMinute: 540, durationMinutes: 30,
                                content: .todo(scheduled.id))

        let sections = PlanningTodoPanelPolicy.sections(
            items: [unscheduled, scheduled, completed], schedules: [block], showCompleted: true
        )
        XCTAssertEqual(sections.map(\.kind), [.unscheduled, .scheduled, .completed])
        XCTAssertEqual(sections.map { $0.items.map(\.id) }, [[unscheduled.id], [scheduled.id], [completed.id]])

        let hidden = PlanningTodoPanelPolicy.sections(
            items: [unscheduled, scheduled, completed], schedules: [block], showCompleted: false
        )
        XCTAssertEqual(hidden.map(\.kind), [.unscheduled, .scheduled])
    }

    func testSchedulePopoverRequestsDistinguishDetailsAndEditingPresentations() {
        let scheduleID = UUID()
        let details = SchedulePopoverRequest.details(scheduleID)
        let editor = SchedulePopoverRequest.editor(scheduleID)
        XCTAssertEqual(details.scheduleID, scheduleID)
        XCTAssertEqual(details.mode, .details)
        XCTAssertEqual(editor.mode, .editor)
        XCTAssertNotEqual(details.id, editor.id)
    }

    @MainActor
    func testIndependentScheduleCanBeEditedWithoutAReferencedTodo() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = DaySchedule(
            startDay: friday, startMinute: 540, durationMinutes: 30,
            content: .independent(title: "Draft plan", notes: "First note")
        )
        XCTAssertTrue(store.upsertSchedule(original))
        XCTAssertNil(original.todoID)

        var edited = original
        edited.startDay = friday.adding(days: 1)
        edited.startMinute = 600
        edited.durationMinutes = 75
        edited.content = .independent(title: "  Revised plan  ", notes: "Updated note")
        XCTAssertTrue(store.upsertSchedule(edited))
        XCTAssertEqual(store.schedules.count, 1)
        XCTAssertEqual(store.schedules.first?.id, original.id)
        XCTAssertEqual(store.schedules.first?.startDay, edited.startDay)
        XCTAssertEqual(store.schedules.first?.startMinute, 600)
        XCTAssertEqual(store.schedules.first?.durationMinutes, 75)
        XCTAssertEqual(store.schedules.first?.content, .independent(title: "Revised plan", notes: "Updated note"))
    }

    func testMidnightFollowsOnlyTodayAndCalendarArithmeticIgnoresDST() {
        let tomorrow = friday.adding(days: 1)
        XCTAssertEqual(DayPlanningPolicy.followedDay(selected: friday, previousToday: friday, today: tomorrow), tomorrow)
        let past = friday.adding(days: -2)
        XCTAssertEqual(DayPlanningPolicy.followedDay(selected: past, previousToday: friday, today: tomorrow), past)
        let dst = LocalDay(year: 2026, month: 3, day: 8)
        XCTAssertEqual(dst.distance(to: dst.adding(days: 1)), 1)
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1), LocalDay(year: 2027, month: 1, day: 1))
    }

    @MainActor
    func testReturningOneSegmentToListKeepsTodoAndOtherSegmentsAcrossUndoAndReload() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let todo = TodoItem(title: "Split work", dueDate: friday.date(), estimatedMinutes: 90)
        XCTAssertTrue(store.upsert(todo))
        let first = DaySchedule(startDay: friday, startMinute: 540, durationMinutes: 30, content: .todo(todo.id))
        let second = DaySchedule(startDay: friday, startMinute: 780, durationMinutes: 60, content: .todo(todo.id))
        XCTAssertTrue(store.upsertSchedule(first))
        XCTAssertTrue(store.upsertSchedule(second))
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        undo.beginUndoGrouping()
        XCTAssertTrue(store.deleteSchedule(first.id))
        undo.endUndoGrouping()
        XCTAssertEqual(store.schedules, [second])
        XCTAssertEqual(store.scheduledMinutes(for: todo.id), 60)
        XCTAssertEqual(store.item(withID: todo.id), todo)
        undo.undo()
        XCTAssertEqual(store.scheduledMinutes(for: todo.id), 90)
        undo.redo()
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
        let restored = TodoStore(fileURL: url)
        XCTAssertEqual(restored.schedules, [second])
        XCTAssertEqual(restored.item(withID: todo.id), todo)
    }

    @MainActor
    func testScheduleMovementKeepsTaskDatesAndUndo() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let todo = TodoItem(title: "Task", dueDate: friday.date(), estimatedMinutes: 90)
        XCTAssertTrue(store.upsert(todo))
        let block = DaySchedule(startDay: friday, startMinute: 1380, durationMinutes: 120, content: .todo(todo.id))
        XCTAssertTrue(store.upsertSchedule(block))
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        var moved = block
        moved.startDay = friday.adding(days: 4)
        undo.beginUndoGrouping()
        XCTAssertTrue(store.upsertSchedule(moved))
        undo.endUndoGrouping()
        XCTAssertEqual(store.items.first, todo)
        XCTAssertEqual(store.schedules, [moved])
        undo.undo()
        XCTAssertEqual(store.items.first, todo)
        XCTAssertEqual(store.schedules, [block])
        undo.redo()
        XCTAssertEqual(store.items.first, todo)
        XCTAssertEqual(store.schedules, [moved])
        _ = await store.flushPersistence()
    }

    @MainActor
    func testDeletingTaskOrProjectCascadesButKeepingChildrenPreservesPlans() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let project = TodoProject(title: "Project")
        store.upsertProject(project)
        let todo = TodoItem(title: "Child", dueDate: friday.date(), projectID: project.id)
        store.upsert(todo)
        let block = DaySchedule(startDay: friday, startMinute: 500, durationMinutes: 40, content: .todo(todo.id))
        store.upsertSchedule(block)
        store.deleteProject(project, strategy: .keepTasks)
        XCTAssertNil(store.items.first?.projectID)
        XCTAssertEqual(store.schedules, [block])
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        undo.beginUndoGrouping(); store.delete(todo); undo.endUndoGrouping()
        XCTAssertTrue(store.schedules.isEmpty)
        undo.undo()
        XCTAssertEqual(store.schedules, [block])
        store.undoManager = nil
        store.upsertProject(project)
        store.upsert(todo)
        store.deleteProject(project, strategy: .deleteTasks)
        XCTAssertTrue(store.schedules.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        _ = await store.flushPersistence()
    }

    @MainActor
    func testCompletedAndOvernightSchedulesAreIndependentOfVisibility() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let todo = TodoItem(title: "Night", dueDate: friday.date())
        store.upsert(todo)
        store.upsert(TodoItem(title: "Undated"))
        let a = DaySchedule(startDay: friday, startMinute: 1380, durationMinutes: 120, content: .todo(todo.id))
        var b = a; b.id = UUID(); b.startMinute = 1390
        store.upsertSchedule(a); store.upsertSchedule(b)
        XCTAssertEqual(store.scheduledMinutes(for: todo.id), 240)
        store.toggle(todo)
        store.settings.showCompleted = false
        XCTAssertTrue(store.items(on: friday.date()).isEmpty)
        XCTAssertEqual(store.allItems(on: friday).count, 1)
        XCTAssertEqual(store.schedules(on: friday.adding(days: 1)).count, 2)
        XCTAssertTrue(store.allItems(on: friday.adding(days: 1)).isEmpty)
        store.deleteSchedule(a.id)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.scheduledMinutes(for: todo.id), 120)
        _ = await store.flushPersistence()
    }

    @MainActor
    func testV2MigrationAndV4RoundTrip() async throws {
        let (initial, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        initial.upsert(TodoItem(title: "Legacy", dueDate: friday.date()))
        _ = await initial.flushPersistence()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["version"] = 2; object.removeValue(forKey: "schedules")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let store = TodoStore(fileURL: url)
        XCTAssertNil(store.items.first?.estimatedMinutes)
        XCTAssertEqual(store.items.first?.status, .notStarted)
        XCTAssertEqual(store.items.first?.startDay, friday)
        XCTAssertEqual(store.items.first?.dueDay, friday)
        XCTAssertTrue(store.schedules.isEmpty)
        var item = try XCTUnwrap(store.items.first)
        item.estimatedMinutes = 93; store.upsert(item)
        let block = DaySchedule(startDay: friday, startMinute: 901, durationMinutes: 37, content: .todo(item.id))
        XCTAssertTrue(store.upsertSchedule(block))
        let flushed = await store.flushPersistence(); XCTAssertTrue(flushed)
        let reopened = TodoStore(fileURL: url)
        XCTAssertEqual(reopened.schedules, [block])
        XCTAssertEqual(reopened.items.first?.estimatedMinutes, 93)
        XCTAssertEqual(reopened.items.first?.startDay, friday)
        XCTAssertEqual(reopened.items.first?.status, .notStarted)
    }

    @MainActor
    func testVersionsOneThroughThreeMigrateStatusesRangesAndRelationshipsWithoutLosingSchedules() throws {
        let project = TodoProject(title: "Legacy project")
        let completionDate = friday.adding(days: 1).date()
        let active = TodoItem(title: "Active", dueDate: friday.date(), projectID: project.id)
        let completed = TodoItem(
            title: "Completed",
            dueDate: friday.adding(days: 1).date(),
            isCompleted: true,
            completedAt: completionDate,
            projectID: project.id
        )
        let schedule = DaySchedule(
            startDay: friday.adding(days: 5),
            startMinute: 615,
            durationMinutes: 45,
            content: .todo(active.id)
        )

        for version in 1...3 {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("DayVDO-v\(version)-migration-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: url) }

            let legacyItems = try [active, completed].map { item -> [String: Any] in
                var object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: JSONEncoder().encode(item))
                        as? [String: Any]
                )
                object.removeValue(forKey: "startDate")
                object.removeValue(forKey: "status")
                object.removeValue(forKey: "previousIncompleteStatus")
                return object
            }
            var snapshot: [String: Any] = [
                "version": version,
                "items": legacyItems,
                "projects": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(project))],
                "tags": [],
                "settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings()))
            ]
            if version == 3 {
                snapshot["schedules"] = [
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode(schedule))
                ]
            }
            try JSONSerialization.data(withJSONObject: snapshot).write(to: url)

            let migrated = TodoStore(fileURL: url)
            XCTAssertEqual(migrated.items.count, 2)
            XCTAssertEqual(migrated.items.first(where: { $0.id == active.id })?.status, .notStarted)
            XCTAssertEqual(migrated.items.first(where: { $0.id == active.id })?.startDay, friday)
            XCTAssertEqual(migrated.items.first(where: { $0.id == active.id })?.dueDay, friday)
            let migratedCompleted = try XCTUnwrap(
                migrated.items.first(where: { $0.id == completed.id })
            )
            XCTAssertEqual(migratedCompleted.status, .completed)
            XCTAssertEqual(migratedCompleted.previousIncompleteStatus, .notStarted)
            XCTAssertEqual(migratedCompleted.completedAt, completionDate)
            XCTAssertEqual(migratedCompleted.projectID, project.id)
            XCTAssertEqual(migrated.projects.map(\.id), [project.id])
            XCTAssertEqual(migrated.schedules, version == 3 ? [schedule] : [])
        }
    }

    @MainActor
    func testRecoveryRestoresSchedulesAndReadOnlyRejectsMutations() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let block = DaySchedule(startDay: friday, startMinute: 300, durationMinutes: 30,
                                content: .independent(title: "Rest", notes: "Note"))
        store.upsertSchedule(block); _ = await store.flushPersistence()
        var second = block; second.id = UUID()
        store.upsertSchedule(second); _ = await store.flushPersistence()
        try Data("corrupt".utf8).write(to: url)
        let recovered = TodoStore(fileURL: url)
        XCTAssertFalse(recovered.canModify)
        XCTAssertFalse(recovered.upsertSchedule(second))
        XCTAssertFalse(recovered.deleteSchedule(block.id))
        await recovered.restoreLatestBackupNow()
        XCTAssertTrue(recovered.canModify)
        XCTAssertEqual(recovered.schedules, [block])
    }

    @MainActor
    func testDuplicateIdentifiersEnterRecoveryInsteadOfCrashing() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.upsert(TodoItem(title: "Task", dueDate: friday.date()))
        store.upsertSchedule(DaySchedule(startDay: friday, startMinute: 60, durationMinutes: 30,
                                        content: .independent(title: "Plan", notes: "")))
        _ = await store.flushPersistence()
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        for key in ["items", "schedules"] {
            var invalid = original
            let values = original[key] as! [[String: Any]]
            invalid[key] = values + values
            let bytes = try JSONSerialization.data(withJSONObject: invalid)
            try bytes.write(to: url)
            let reopened = TodoStore(fileURL: url)
            XCTAssertFalse(reopened.canModify, "Duplicate \(key) must not be loaded")
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor
    func testLinkedMetadataAndEstimateEditsKeepExistingPlan() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var todo = TodoItem(title: "Original", dueDate: friday.date(), estimatedMinutes: 60)
        store.upsert(todo)
        let block = DaySchedule(startDay: friday, startMinute: 1380, durationMinutes: 120, content: .todo(todo.id))
        store.upsertSchedule(block)
        todo.title = "Renamed"
        todo.notes = "Updated notes"
        todo.estimatedMinutes = 15
        XCTAssertTrue(store.upsert(todo))
        XCTAssertEqual(store.schedules, [block])
        XCTAssertEqual(store.scheduledMinutes(for: todo.id), 120)
        XCTAssertEqual(SchedulePresentation.title(block, store: store), "Renamed")
        XCTAssertEqual(SchedulePresentation.notes(block, store: store), "Updated notes")
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        var moved = block; moved.startMinute = 1400; moved.durationMinutes = 100
        undo.beginUndoGrouping()
        XCTAssertTrue(store.upsertSchedule(moved))
        undo.endUndoGrouping()
        XCTAssertEqual(store.schedules, [moved])
        undo.undo()
        XCTAssertEqual(store.schedules, [block])
        XCTAssertEqual(store.items.first?.estimatedMinutes, 15)
        undo.redo()
        XCTAssertEqual(store.schedules, [moved])
        _ = await store.flushPersistence()
    }

    @MainActor
    func testInvalidOrOrphanedPlansAreRejectedWithoutChangingSnapshot() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let valid = DaySchedule(startDay: friday, startMinute: 90, durationMinutes: 1,
                                content: .independent(title: "Short", notes: ""))
        XCTAssertTrue(store.upsertSchedule(valid))
        for duration in [0, -1, 1441] {
            var invalid = valid; invalid.durationMinutes = duration
            XCTAssertFalse(store.upsertSchedule(invalid))
        }
        for minute in [-1, 1440] {
            var invalid = valid; invalid.startMinute = minute
            XCTAssertFalse(store.upsertSchedule(invalid))
        }
        var orphan = valid; orphan.content = .todo(UUID())
        XCTAssertFalse(store.upsertSchedule(orphan))
        XCTAssertEqual(store.schedules, [valid])
        _ = await store.flushPersistence()
        XCTAssertEqual(TodoStore(fileURL: url).schedules, [valid])
    }

    @MainActor
    private func makeStore() -> (TodoStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayPlanningTests-\(UUID())")
        let url = directory.appendingPathComponent("todos.json")
        return (TodoStore(fileURL: url), url)
    }
}
