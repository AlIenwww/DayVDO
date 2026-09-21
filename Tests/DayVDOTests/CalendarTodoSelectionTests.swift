import AppKit
import XCTest
@testable import DayVDO

final class CalendarTodoSelectionTests: XCTestCase {
    @MainActor
    func testClipboardPasteUsesSelectedDayPreservesSpanAndDoesNotCopySchedules() {
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("CalendarCopy-\(UUID()).json"))
        let start = LocalDay(year: 2026, month: 12, day: 30)
        let item = TodoItem(title: "Copy me", notes: "Notes", startDate: start.date(), dueDate: start.adding(days: 3).date(), status: .completed)
        XCTAssertTrue(store.upsert(item))
        XCTAssertTrue(store.upsertSchedule(.init(startDay: start, startMinute: 600, durationMinutes: 60, content: .todo(item.id))))
        let selection = CalendarTodoSelection()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        selection.selectedID = item.id
        selection.copy(store, to: board)
        selection.selectedID = nil
        selection.day = LocalDay(year: 2028, month: 2, day: 28)
        selection.paste(store, from: board)
        let copy = store.item(withID: selection.selectedID)
        XCTAssertNotEqual(copy?.id, item.id)
        XCTAssertEqual(copy?.title, item.title)
        XCTAssertEqual(copy?.notes, item.notes)
        XCTAssertEqual(copy?.startDay, selection.day)
        XCTAssertEqual(copy?.dueDay, LocalDay(year: 2028, month: 3, day: 2))
        XCTAssertEqual(copy?.status, .notStarted)
        XCTAssertNil(copy?.completedAt)
        XCTAssertEqual(store.schedules.count, 1)
        selection.selectedID = item.id
        selection.paste(store, from: board)
        XCTAssertEqual(store.item(withID: selection.selectedID)?.startDay, start)
    }

    @MainActor
    func testDeleteUsesConfirmationPreferenceAndStoreUndo() {
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("CalendarDelete-\(UUID()).json"))
        let undo = UndoManager(); undo.groupsByEvent = false; store.undoManager = undo
        let item = TodoItem(title: "Delete", dueDate: .now)
        undo.beginUndoGrouping(); _ = store.upsert(item); undo.endUndoGrouping(); undo.removeAllActions()
        let selection = CalendarTodoSelection(); selection.selectedID = item.id
        selection.requestDelete(store)
        XCTAssertEqual(selection.pendingDelete?.id, item.id)
        XCTAssertNotNil(store.item(withID: item.id))
        selection.pendingDelete = nil
        undo.beginUndoGrouping(); _ = store.delete(item); undo.endUndoGrouping()
        XCTAssertNil(store.item(withID: item.id))
        undo.undo(); XCTAssertNotNil(store.item(withID: item.id))
    }
}
