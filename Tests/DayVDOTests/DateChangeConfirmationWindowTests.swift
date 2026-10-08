import AppKit
import Observation
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class DateChangeConfirmationWindowTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 5)

    func testKeepAndDeleteButtonsApplyOnlyAffectedArrangementAndRefreshPanel() throws {
        for keep in [true, false] {
            let fixture = try makeWindow()
            defer { close(fixture) }
            let sheet = try XCTUnwrap(fixture.window.attachedSheet)
            let text = controls(NSTextField.self, in: try XCTUnwrap(sheet.contentView)).map(\.stringValue).joined(separator: "\n")
            XCTAssertTrue(text.contains("需要处理 1 段安排。"))
            XCTAssertTrue(text.contains("范围内的安排继续关联此待办"))
            let title = L10n.string(keep ? "保留为普通安排" : "删除安排")
            try XCTUnwrap(controls(NSButton.self, in: try XCTUnwrap(sheet.contentView)).first { $0.title == title }).performClick(nil)
            settle()
            XCTAssertNil(fixture.probe.request)
            XCTAssertNotNil(fixture.probe.saved)
            XCTAssertEqual(fixture.store.item(withID: fixture.item.id)?.startDay, day.adding(days: 1))
            XCTAssertEqual(fixture.store.schedules(for: fixture.item.id), [fixture.retained])
            XCTAssertTrue(fixture.store.planningItems(on: day, today: day).isEmpty)
            if keep {
                var converted = fixture.affected
                converted.content = .independent(title: "Math practice", notes: "New notes")
                XCTAssertEqual(fixture.store.schedules, [converted, fixture.retained])
                capture(fixture.window, name: "date-kept")
            } else {
                XCTAssertEqual(fixture.store.schedules, [fixture.retained])
                capture(fixture.window, name: "date-deleted")
            }
        }
    }

    func testEscapeCancelsConfirmationWithoutClosingParentOrSaving() throws {
        let fixture = try makeWindow()
        defer { close(fixture) }
        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        NSApp.postEvent(event, atStart: true)
        if let queued = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true) {
            NSApp.sendEvent(queued)
        }
        settle()
        XCTAssertNil(fixture.probe.request)
        XCTAssertNil(fixture.probe.saved)
        XCTAssertFalse(fixture.probe.parentClosed)
        XCTAssertEqual(fixture.store.item(withID: fixture.item.id), fixture.item)
        XCTAssertEqual(fixture.store.schedules, [fixture.affected, fixture.retained])
    }

    func testLocalizedConfirmationButtonsAndMessageFitForAllEightLanguages() throws {
        defer { L10n.configure(language: .system) }
        for language in AppLanguage.allCases where language != .system {
            let fixture = try makeWindow(language: language)
            defer { close(fixture) }
            let sheet = try XCTUnwrap(fixture.window.attachedSheet)
            let view = try XCTUnwrap(sheet.contentView)
            for key in ["保留为普通安排", "删除安排", "取消"] {
                let button = try XCTUnwrap(controls(NSButton.self, in: view).first { $0.title == L10n.string(key) }, language.rawValue)
                XCTAssertGreaterThanOrEqual(button.bounds.width + 1, button.cell?.cellSize.width ?? 0, "\(language): \(key)")
            }
            capture(sheet, name: "date-alert-\(language.rawValue)")
        }
    }

    private struct Fixture {
        var store: TodoStore
        var item: TodoItem
        var affected: DaySchedule
        var retained: DaySchedule
        var probe: DateConfirmationProbe
        var window: NSWindow
    }

    private func makeWindow(language: AppLanguage = .simplifiedChinese) throws -> Fixture {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-DateAlert-\(UUID())/todos.json"))
        store.settings.language = language
        let item = TodoItem(title: "Reading", notes: "Old notes", startDate: day.date(), dueDate: day.adding(days: 1).date())
        XCTAssertTrue(store.upsert(item))
        let affected = DaySchedule(startDay: day, startMinute: 540, durationMinutes: 60, content: .todo(item.id))
        let retained = DaySchedule(startDay: day.adding(days: 1), startMinute: 600, durationMinutes: 60, content: .todo(item.id))
        XCTAssertTrue(store.upsertSchedule(affected))
        XCTAssertTrue(store.upsertSchedule(retained))
        var candidate = item
        candidate.title = "Math practice"
        candidate.notes = "New notes"
        candidate.startDay = day.adding(days: 1)
        let request = try XCTUnwrap(store.dateChangeConfirmation(for: candidate))
        let probe = DateConfirmationProbe()
        let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 760, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DateConfirmationHarness(day: day, probe: probe).environmentObject(store))
        window.makeKeyAndOrderFront(nil)
        settle()
        probe.request = request
        settle()
        return Fixture(store: store, item: item, affected: affected, retained: retained, probe: probe, window: window)
    }

    private func close(_ fixture: Fixture) {
        if let sheet = fixture.window.attachedSheet { fixture.window.endSheet(sheet) }
        fixture.probe.request = nil
        settle()
        fixture.window.close()
        L10n.configure(language: .system)
    }

    private func controls<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { controls(type, in: $0) }
    }

    private func capture(_ window: NSWindow, name: String) {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/dayvdo-v700-\(name).png"))
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }
}

@MainActor
@Observable
private final class DateConfirmationProbe {
    var request: TodoStore.DateChangeConfirmation?
    var saved: TodoItem?
    var parentClosed = false
}

private struct DateConfirmationHarness: View {
    let day: LocalDay
    @Bindable var probe: DateConfirmationProbe
    @State private var presentation: SchedulePopoverRequest?

    var body: some View {
        HStack(spacing: 0) {
            DayTimelineView(day: day, hourHeight: .constant(90), restoredScrollMinute: .constant(480), now: day.date(),
                presentation: $presentation, create: { _, _, _ in }, dropTodo: { _, _, _ in }, editTodo: { _ in }, activityChanged: { _ in })
            Divider()
            PlanningTodoPanel(day: day, today: day, edit: { _ in }).frame(width: 280)
        }
        .editorEscapeDismissal(enabled: probe.request == nil) { probe.parentClosed = true }
        .dateChangeConfirmation($probe.request) { probe.saved = $0 }
    }
}
