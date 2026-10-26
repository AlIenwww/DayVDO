import AppKit
import Combine
import XCTest
@testable import DayVDO

@MainActor
final class ExperienceOptimizationTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 19)

    func testNoOpDoesNotInvalidateCalendarOrRegisterUndo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Experience-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let item = TodoItem(title: "Task", dueDate: day.date())
        store.upsert(item)
        let saved = await store.flushPersistence(); XCTAssertTrue(saved)
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        let revision = store.contentRevision, dates = store.dateContentRevision, timeline = store.timelineContentRevision
        XCTAssertFalse(store.upsert(item))
        XCTAssertEqual(store.contentRevision, revision)
        XCTAssertEqual(store.dateContentRevision, dates)
        XCTAssertEqual(store.timelineContentRevision, timeline)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(store.hasPendingPersistence)
    }

    func testRevisionDomainsAndUndoKeepDatesAndSchedulesFresh() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Experience-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        var project = TodoProject(title: "Project")
        store.upsertProject(project)
        let dates = store.dateContentRevision, timeline = store.timelineContentRevision
        project.notes = "Metadata only"; store.upsertProject(project)
        XCTAssertEqual(store.dateContentRevision, dates)
        XCTAssertEqual(store.timelineContentRevision, timeline)
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        let schedule = DaySchedule(startDay: day, startMinute: 600, durationMinutes: 40,
            content: .independent(title: "Schedule", notes: ""))
        undo.beginUndoGrouping(); store.upsertSchedule(schedule); undo.endUndoGrouping()
        XCTAssertEqual(store.dateContentRevision, dates)
        XCTAssertGreaterThan(store.timelineContentRevision, timeline)
        let addedRevision = store.timelineContentRevision
        undo.undo()
        XCTAssertTrue(store.schedules(on: day).isEmpty)
        XCTAssertEqual(store.dateContentRevision, dates)
        XCTAssertGreaterThan(store.timelineContentRevision, addedRevision)
        undo.redo(); XCTAssertEqual(store.schedules(on: day), [schedule])
        undo.beginUndoGrouping()
        store.upsert(TodoItem(title: "Task", dueDate: day.date()))
        undo.endUndoGrouping()
        XCTAssertGreaterThan(store.dateContentRevision, dates)
    }

    func testDayLayoutCacheMatchesReferenceAndReusesUnchangedGeometry() {
        let schedules = arrangements()
        let cache = TimelineLayoutCache()
        for offset in 0..<8 {
            let day = day.adding(days: offset)
            for active in [nil, schedules.first?.id] {
                let expected = DayPlanningPolicy.placements(schedules, on: day, prioritizing: active)
                let result = cache.value(day: day, schedules: schedules, prioritizing: active)
                XCTAssertEqual(result.placements, expected)
                let count = cache.buildCount
                for _ in 0..<50 { _ = cache.value(day: day, schedules: schedules, prioritizing: active) }
                XCTAssertEqual(cache.buildCount, count)
            }
        }
    }

    func testWeekPreviewMatchesFullRebuildForMoveResizeMidnightAndFiltering() {
        let original = arrangements()
        for completed in [true, false] {
            let todo = TodoItem(title: "Done", isCompleted: true)
            var schedules = original
            schedules[0].content = .todo(todo.id)
            let visibility = TodoFilterContext(showCompleted: completed)
            let cache = CalendarWeekPresentationCache()
            let key = CalendarWeekPresentationCache.Key(week: day, revision: 1, visibility: visibility)
            for index in [0, 1, 7, 13] {
                for shift in [-1, 0, 1, 7] {
                    var preview = schedules[index]
                    preview.startDay = preview.startDay.adding(days: shift)
                    preview.startMinute = shift == 0 ? 1410 : 500
                    preview.durationMinutes = 90
                    preview.setHorizontalPosition(0.8)
                    let result = cache.value(for: key, schedulesOnDay: { target in
                        schedules.filter { $0.interval(on: target) != nil }
                    }, preview: preview, prioritizing: preview.id, todo: { _ in todo })
                    var expected = schedules.filter { $0.id != preview.id }; expected.append(preview)
                    expected = expected.filter { $0.todoID == nil || visibility.includes(todo) }
                    for offset in 0..<7 {
                        let target = day.adding(days: offset)
                        XCTAssertEqual(result.placementsByDay[target], DayPlanningPolicy.placements(expected, on: target, prioritizing: preview.id))
                    }
                }
            }
        }
    }

    func testPreviewRebuildsOnlyAffectedDatesAndIdenticalInputIsReused() {
        let cache = CalendarWeekPresentationCache()
        let schedules = arrangements()
        let key = CalendarWeekPresentationCache.Key(week: day, revision: 1, visibility: .init(showCompleted: true))
        _ = cache.value(for: key, schedules: schedules, preview: nil, todo: { _ in nil })
        let baseline = cache.layoutBuildCount
        var preview = schedules[1]; preview.startMinute += 5
        _ = cache.value(for: key, schedules: schedules, preview: preview, todo: { _ in nil })
        XCTAssertEqual(cache.layoutBuildCount - baseline, 1)
        let updated = cache.layoutBuildCount
        _ = cache.value(for: key, schedules: schedules, preview: preview, todo: { _ in nil })
        XCTAssertEqual(cache.layoutBuildCount, updated)
        _ = cache.value(for: key, schedules: schedules, preview: nil, todo: { _ in nil })
        XCTAssertEqual(cache.layoutBuildCount, updated)
    }

    func testCoalescerKeepsLastInputFlushesReleaseAndDropsCancellation() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scheduler = FrameUpdateScheduler()
        scheduler.view = window.contentView
        defer { scheduler.cancel(); window.close() }
        var values: [Int] = []
        for index in 0..<20 { scheduler.submit { values.append(index) } }
        XCTAssertTrue(values.isEmpty)
        scheduler.flush()
        XCTAssertEqual(values, [19])
        scheduler.submit { values.append(20) }; scheduler.cancel(); scheduler.flush()
        XCTAssertEqual(values, [19])
    }

    func testComparisonPoliciesHaveStableThresholdsAndTimeIndependentZoom() {
        var snap = InteractionComparisonPolicy.Snap()
        XCTAssertEqual(snap.value(pointer: 95, boundaries: [100], enabled: true), 100)
        XCTAssertEqual(snap.value(pointer: 108, boundaries: [100], enabled: true), 100)
        XCTAssertEqual(snap.value(pointer: 110, boundaries: [100], enabled: true), 110)
        XCTAssertEqual(snap.value(pointer: 108, boundaries: [100], enabled: true), 108)
        snap.reset()
        XCTAssertEqual(snap.value(pointer: 108, boundaries: [100], enabled: false), 108)
        XCTAssertFalse(InteractionComparisonPolicy.crossesRow(pointer: 103, midpoint: 100, movingDown: true))
        XCTAssertTrue(InteractionComparisonPolicy.crossesRow(pointer: 105, midpoint: 100, movingDown: true))
        XCTAssertTrue(InteractionComparisonPolicy.crossesRow(pointer: 95, midpoint: 100, movingDown: false))
        XCTAssertEqual(InteractionComparisonPolicy.edgeVelocity(pointer: 0, height: 500), -240)
        XCTAssertEqual(InteractionComparisonPolicy.edgeVelocity(pointer: 250, height: 500), 0)
        XCTAssertEqual(InteractionComparisonPolicy.edgeVelocity(pointer: 500, height: 500), 240)
        let once = InteractionComparisonPolicy.zoom(current: 90, target: 150, elapsed: 0.016)
        let half = InteractionComparisonPolicy.zoom(current: 90, target: 150, elapsed: 0.008)
        XCTAssertEqual(once, InteractionComparisonPolicy.zoom(current: half, target: 150, elapsed: 0.008), accuracy: 0.000001)
    }
    private func arrangements() -> [DaySchedule] {
        (0..<21).map { index in
            DaySchedule(startDay: day.adding(days: index % 7), startMinute: 480 + index % 5 * 20,
                durationMinutes: 60, content: .independent(title: "Plan \(index)", notes: ""))
        }
    }
}
