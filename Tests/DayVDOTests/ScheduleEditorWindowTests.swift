import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class ScheduleEditorWindowTests: XCTestCase {
    func testNativeTimeFieldsSaveMinutePrecisionAcrossMidnight() async throws {
        try await checkNativeFieldEdits(save: true)
    }

    func testDismissalDoesNotSaveNativeFieldEdits() async throws {
        try await checkNativeFieldEdits(save: false)
    }

    private func checkNativeFieldEdits(save: Bool) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-ScheduleEditor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let schedule = DaySchedule(startDay: LocalDay(year: 2026, month: 11, day: 1),
                                   startMinute: 1425, durationMinutes: 60,
                                   content: .independent(title: "Read", notes: "Notes"))
        XCTAssertTrue(store.upsertSchedule(schedule))
        let host = NSHostingView(rootView: AnyView(ScheduleEditorView(schedule: schedule,
            close: {}, editTodo: { _ in }).environmentObject(store)
            .environment(\.locale, Locale(identifier: "en_US"))))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await settle(host)

        let pickers = descendants(in: host).compactMap { $0 as? NSDatePicker }
        let timeFields = pickers.filter { $0.datePickerElements.contains(.hourMinute) }
        XCTAssertEqual(timeFields.count, 2, "Both times must use native date/time controls")
        XCTAssertEqual(pickers.filter { $0.datePickerElements.contains(.yearMonthDay) }.count, 1)
        let start = try XCTUnwrap(timeFields.first)
        let end = try XCTUnwrap(timeFields.last)
        XCTAssertEqual(start.dateValue, Date(timeIntervalSinceReferenceDate: 1425 * 60))
        XCTAssertEqual(end.dateValue, Date(timeIntervalSinceReferenceDate: 45 * 60))
        // Send the controls' real actions, as when a person edits their fields.
        start.dateValue = Date(timeIntervalSinceReferenceDate: 1437 * 60)
        XCTAssertTrue(start.sendAction(start.action, to: start.target))
        end.dateValue = Date(timeIntervalSinceReferenceDate: 7 * 60)
        XCTAssertTrue(end.sendAction(end.action, to: end.target))
        try await settle(host)
        if save {
            // This is the submission sent when Return reaches the timeline.
            NotificationCenter.default.post(name: .scheduleEditorSubmit, object: schedule.id)
            try await settle(host)
        }
        // Removal must never save the draft again after cancellation.
        host.rootView = AnyView(EmptyView())
        try await settle(host)
        let saved = try XCTUnwrap(store.schedules.first)
        XCTAssertEqual(saved.startDay, schedule.startDay)
        XCTAssertEqual(saved.startMinute, save ? 1437 : schedule.startMinute)
        XCTAssertEqual(saved.durationMinutes, save ? 10 : schedule.durationMinutes)
        XCTAssertEqual(saved.content, schedule.content)
        let persisted = await store.flushPersistence()
        XCTAssertTrue(persisted)
    }

    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(in: $0) }
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
