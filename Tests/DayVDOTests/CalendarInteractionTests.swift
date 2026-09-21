import XCTest
@testable import DayVDO

final class CalendarInteractionTests: XCTestCase {
    private let friday = LocalDay(year: 2026, month: 9, day: 18)

    func testDateCreationMoveAndResizeAcrossWeekMonthYearAndLeapDay() {
        let tuesday = friday.adding(days: 4)
        XCTAssertEqual(CalendarDatePolicy.range(start: friday, end: friday, anchor: tuesday,
            target: friday, mode: .create), friday...tuesday)
        let moved = CalendarDatePolicy.range(start: friday, end: tuesday, anchor: friday.adding(days: 2),
            target: friday.adding(days: 4), mode: .move)
        XCTAssertEqual(moved, friday.adding(days: 2)...tuesday.adding(days: 2))
        XCTAssertEqual(CalendarDatePolicy.range(start: friday, end: tuesday, anchor: friday,
            target: tuesday.adding(days: 10), mode: .start), tuesday...tuesday)
        XCTAssertEqual(CalendarDatePolicy.range(start: friday, end: friday, anchor: friday,
            target: tuesday, mode: .end), friday...tuesday)
        let december = LocalDay(year: 2026, month: 12, day: 31)
        XCTAssertEqual(december.adding(days: 1), LocalDay(year: 2027, month: 1, day: 1))
        XCTAssertEqual(LocalDay(year: 2028, month: 2, day: 28).adding(days: 2), LocalDay(year: 2028, month: 3, day: 1))
    }

    func testLanesClippingAndTrueEndpoints() {
        let week = friday.adding(days: -4)
        let items = [(friday, friday.adding(days: 4)), (friday, friday), (week, week.adding(days: 2))].map {
            CalendarWindowSnapshot.Item(id: UUID(), startDay: $0.0, dueDay: $0.1,
                title: "Range", status: .notStarted, hasProject: false, tagColor: nil)
        }
        let first = CalendarDatePolicy.segments(items, week: week)
        XCTAssertEqual(first[0].firstColumn, 4)
        XCTAssertEqual(first[0].lastColumn, 6)
        XCTAssertTrue(first[0].startsHere)
        XCTAssertFalse(first[0].endsHere)
        XCTAssertEqual(first.map(\.lane), [0, 1, 0])
        let second = CalendarDatePolicy.segments(items, week: week.adding(days: 7))
        XCTAssertEqual(second.count, 1)
        XCTAssertFalse(second[0].startsHere)
        XCTAssertTrue(second[0].endsHere)
        XCTAssertEqual(second[0].lastColumn, 1)
    }

    func testWeekScheduleMovementAndMidnightResize() {
        let value = DaySchedule(startDay: friday, startMinute: 1380, durationMinutes: 120,
                                content: .independent(title: "Night", notes: ""))
        let moved = WeekSchedulePolicy.adjusted(value, mode: .move, dayDelta: 2, minuteDelta: -15)
        XCTAssertEqual(moved.startDay, friday.adding(days: 2))
        XCTAssertEqual(moved.startMinute, 1365)
        XCTAssertEqual(moved.durationMinutes, 120)
        let extended = WeekSchedulePolicy.adjusted(value, mode: .end, dayDelta: 3, minuteDelta: 0)
        XCTAssertEqual(extended.durationMinutes, 1440)
        let shortened = WeekSchedulePolicy.adjusted(value, mode: .start, dayDelta: 1, minuteDelta: -1350)
        XCTAssertEqual(shortened.startDay, friday.adding(days: 1))
        XCTAssertEqual(shortened.startMinute, 30)
        XCTAssertEqual(shortened.durationMinutes, 30)
        XCTAssertTrue(shortened.isValid)
    }

    func testPreciseExistingScheduleResizesOnlyToLegalFiveMinutePoints() {
        let value = DaySchedule(startDay: friday, startMinute: 721, durationMinutes: 1,
                                content: .independent(title: "Precise", notes: ""))
        let start = WeekSchedulePolicy.adjusted(value, mode: .start, dayDelta: 0, minuteDelta: 100)
        XCTAssertEqual(start.startMinute, 720)
        XCTAssertEqual(start.durationMinutes, 2)
        let end = WeekSchedulePolicy.adjusted(value, mode: .end, dayDelta: 0, minuteDelta: -100)
        XCTAssertEqual(end.endMinute, 725)
        XCTAssertTrue(start.isValid)
        XCTAssertTrue(end.isValid)
    }

    @MainActor
    func testDateDragUsesVisibleGeometryAndCancelsUntilMouseRelease() {
        let interaction = CalendarDateInteraction()
        let week = friday.adding(days: -4)
        interaction.viewport = CGSize(width: 700, height: 200)
        interaction.frames = [week: CGRect(x: 0, y: 0, width: 700, height: 100),
                              week.adding(days: 7): CGRect(x: 0, y: 100, width: 700, height: 100)]
        var created: ClosedRange<LocalDay>?
        let create: (LocalDay, LocalDay) -> Void = { created = $0...$1 }
        interaction.update(origin: CGPoint(x: 450, y: 50), location: CGPoint(x: 150, y: 150), item: nil, mode: .create)
        XCTAssertEqual(interaction.drag?.range, friday...friday.adding(days: 4))
        interaction.cancel()
        interaction.update(origin: CGPoint(x: 450, y: 50), location: CGPoint(x: 150, y: 150), item: nil, mode: .create)
        interaction.finish(at: CGPoint(x: 150, y: 150), create: create, change: { _ in XCTFail() })
        XCTAssertNil(created)
        interaction.release()
        interaction.update(origin: CGPoint(x: 150, y: 150), location: CGPoint(x: 450, y: 50), item: nil, mode: .create)
        interaction.finish(at: CGPoint(x: 450, y: 50), create: create, change: { _ in XCTFail() })
        XCTAssertEqual(created, friday...friday.adding(days: 4))
        created = nil
        interaction.update(origin: CGPoint(x: 450, y: 50), location: CGPoint(x: 150, y: 150), item: nil, mode: .create)
        interaction.finish(at: CGPoint(x: 150, y: 250), create: create, change: { _ in XCTFail() })
        XCTAssertNil(created)
        XCTAssertNil(interaction.drag)
    }

    @MainActor
    func testConfirmationIsAtomicUndoableAndCannotBeBypassed() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CalendarTest-\(UUID())/todos.json")
        let store = TodoStore(fileURL: url)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        var item = TodoItem(title: "Task", startDate: friday.date(), dueDate: friday.adding(days: 4).date())
        undo.beginUndoGrouping()
        XCTAssertTrue(store.upsert(item))
        for day in [friday, friday.adding(days: 1)] {
            XCTAssertTrue(store.upsertSchedule(DaySchedule(startDay: day, startMinute: 600, durationMinutes: 60, content: .todo(item.id))))
        }
        let independent = DaySchedule(startDay: friday, startMinute: 900, durationMinutes: 30,
                                      content: .independent(title: "Independent", notes: ""))
        XCTAssertTrue(store.upsertSchedule(independent))
        undo.endUndoGrouping()
        undo.removeAllActions()
        let original = item
        let originalSchedules = store.schedules
        item.startDay = friday.adding(days: 1)
        XCTAssertFalse(store.upsert(item))
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: item))
        XCTAssertEqual(request.schedules.count, 2)
        XCTAssertEqual(store.item(withID: item.id), original)
        undo.beginUndoGrouping()
        XCTAssertTrue(store.confirmDateChange(request))
        undo.endUndoGrouping()
        XCTAssertEqual(store.schedules, [independent])
        XCTAssertEqual(store.item(withID: item.id)?.startDay, item.startDay)
        undo.undo()
        XCTAssertEqual(store.item(withID: item.id), original)
        XCTAssertEqual(store.schedules, originalSchedules)
        undo.redo()
        XCTAssertEqual(store.schedules, [independent])
        let persisted = await store.flushPersistence()
        XCTAssertTrue(persisted)
        let loaded = TodoStore(fileURL: url)
        for _ in 0..<100 where loaded.isInitialLoading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(loaded.items, store.items)
        XCTAssertEqual(loaded.schedules, [independent])
    }

    @MainActor
    func testStaleConfirmationAndUndatingProtection() throws {
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("CalendarTest-\(UUID())/todos.json"))
        let item = TodoItem(title: "Task", dueDate: friday.date())
        XCTAssertTrue(store.upsert(item))
        var schedule = DaySchedule(startDay: friday, startMinute: 600, durationMinutes: 60, content: .todo(item.id))
        XCTAssertTrue(store.upsertSchedule(schedule))
        var candidate = item
        candidate.startDay = nil; candidate.dueDay = nil
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
        schedule.startMinute = 700
        XCTAssertTrue(store.upsertSchedule(schedule))
        XCTAssertFalse(store.confirmDateChange(request))
        XCTAssertFalse(store.upsert(candidate))
        XCTAssertEqual(store.items, [item])
        var renamed = item
        renamed.title = "Changed title"
        XCTAssertTrue(store.upsert(renamed))
        XCTAssertEqual(store.schedules, [schedule])
        XCTAssertFalse(store.confirmDateChange(request))
    }
}
