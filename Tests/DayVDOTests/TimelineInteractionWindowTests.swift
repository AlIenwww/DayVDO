import AppKit
import Observation
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TimelineInteractionWindowTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 5)

    func testSavedHorizontalPositionUpdatesNativeCardHitRegions() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        for index in 0..<2 {
            XCTAssertTrue(fixture.store.upsertSchedule(DaySchedule(startDay: day, startMinute: 540,
                durationMinutes: 60, content: .independent(title: "Overlap \(index)", notes: ""))))
        }
        settle()
        for targetColumn in [0, 1, 2, 0] {
            var moved = fixture.schedule
            moved.setHorizontalPosition((Double(targetColumn) + 0.5) / 3)
            XCTAssertTrue(fixture.store.upsertSchedule(moved))
            settle()
            let width: CGFloat = (680 - 54 - 8) / 3
            doubleClick(screenPoint(x: 54 + (CGFloat(targetColumn) + 0.5) * width,
                yFromTop: 145, in: fixture.window), in: fixture.window)
            settle()
            XCTAssertEqual(fixture.probe.presentation?.scheduleID, moved.id)
            XCTAssertEqual(fixture.probe.presentation?.mode, .editor)
            escape(in: try XCTUnwrap(editorWindow(fixture)))
            settle()
        }
    }

    func testMouseClicksRouteTitleAndBackgroundExclusivelyAndKeepStatusButtonWorking() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        // Fixed 680-point viewport, 90 points/hour, restored to 08:00.
        // Coordinates were checked against the rendered native window.
        let title = screenPoint(x: 150, yFromTop: 113, in: fixture.window)
        let background = screenPoint(x: 620, yFromTop: 145, in: fixture.window)
        click(background, in: fixture.window)
        settle()
        XCTAssertNil(fixture.probe.presentation)
        XCTAssertNil(fixture.probe.editingItem)
        doubleClick(title, in: fixture.window)
        settle()
        XCTAssertEqual(fixture.probe.editedIDs, [fixture.item.id])
        XCTAssertNil(fixture.probe.presentation)
        XCTAssertNotNil(fixture.probe.editingItem)
        dismissSheet(fixture)
        doubleClick(background, in: fixture.window)
        settle()
        XCTAssertEqual(fixture.probe.presentation?.mode, .editor)
        XCTAssertEqual(fixture.probe.editedIDs, [fixture.item.id])
        escape(in: try XCTUnwrap(editorWindow(fixture)))
        settle()
        XCTAssertNil(fixture.probe.presentation)
        click(screenPoint(x: 67, yFromTop: 113, in: fixture.window), in: fixture.window)
        settle()
        XCTAssertTrue(fixture.store.item(withID: fixture.item.id)?.isCompleted == true)
        XCTAssertNil(fixture.probe.presentation)
    }

    func testEscapeWithFocusedInputDiscardsNewArrangementAndCanReopen() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        let draft = DaySchedule(startDay: day, startMinute: 720, durationMinutes: 30,
                                content: .independent(title: "", notes: ""))
        for forwardsToParent in [false, true] {
            fixture.probe.draft = draft
            settle()
            let popup = try XCTUnwrap(editorWindow(fixture))
            let field = try XCTUnwrap(fields(in: try XCTUnwrap(popup.contentView)).first)
            edit(field, text: "Unsaved arrangement", in: popup)
            escape(in: forwardsToParent ? fixture.window : popup)
            settle()
            XCTAssertNil(fixture.probe.draft)
            XCTAssertEqual(fixture.store.schedules, [fixture.schedule])
        }
        escape(in: fixture.window)
        settle()
        XCTAssertEqual(fixture.store.schedules, [fixture.schedule])
    }

    func testTaskEditorEscapeClosesNestedPickerBeforeDiscardingTaskDraft() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        fixture.probe.editingItem = fixture.item
        settle()
        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        // The date section now precedes the estimate row in this fixed-size editor.
        click(screenPoint(x: 440, yFromTop: 398, in: sheet), in: sheet)
        settle()
        let picker = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0 !== fixture.window && $0 !== sheet })
        escape(in: picker)
        settle()
        XCTAssertNotNil(fixture.probe.editingItem)
        XCTAssertTrue(sheet.isVisible)
        let field = try XCTUnwrap(fields(in: try XCTUnwrap(sheet.contentView)).first)
        edit(field, text: "Unsaved task name", in: sheet)
        escape(in: sheet)
        settle()
        XCTAssertNil(fixture.probe.editingItem)
        XCTAssertEqual(fixture.store.item(withID: fixture.item.id), fixture.item)
    }

    func testTimeTextAndIndependentTitleOpenOnlyArrangementEditor() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        doubleClick(screenPoint(x: 90, yFromTop: 129, in: fixture.window), in: fixture.window)
        settle()
        XCTAssertEqual(fixture.probe.presentation?.mode, .editor)
        XCTAssertTrue(fixture.probe.editedIDs.isEmpty)
        escape(in: try XCTUnwrap(editorWindow(fixture)))
        settle()
        var independent = fixture.schedule
        independent.content = .independent(title: "Independent", notes: "Original notes")
        XCTAssertTrue(fixture.store.upsertSchedule(independent))
        settle()
        doubleClick(screenPoint(x: 90, yFromTop: 113, in: fixture.window), in: fixture.window)
        settle()
        XCTAssertEqual(fixture.probe.presentation?.mode, .editor)
        XCTAssertTrue(fixture.probe.editedIDs.isEmpty)
        let popup = try XCTUnwrap(editorWindow(fixture))
        edit(try XCTUnwrap(fields(in: try XCTUnwrap(popup.contentView)).first), text: "Unsaved name", in: popup)
        escape(in: popup)
        settle()
        XCTAssertNil(fixture.probe.presentation)
        XCTAssertEqual(fixture.store.schedules, [independent])
    }

    func testContextMenuHasEditTaskAndOpensLatestTask() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        var renamed = fixture.item
        renamed.title = "Latest task name"
        XCTAssertTrue(fixture.store.upsert(renamed))
        settle()
        let observer = TimelineMenuObserver(probe: fixture.probe)
        NotificationCenter.default.addObserver(observer, selector: #selector(TimelineMenuObserver.didStartMenu(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(observer) }
        let point = fixture.window.convertPoint(fromScreen: screenPoint(x: 620, yFromTop: 145, in: fixture.window))
        dispatch(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        settle()
        XCTAssertTrue(fixture.probe.menuTitles.contains(L10n.string("编辑任务")))
        XCTAssertTrue(fixture.probe.menuTitles.contains(L10n.string("编辑安排")))
        XCTAssertTrue(fixture.probe.menuTitles.contains(L10n.string("移除安排")))
        XCTAssertEqual(fixture.probe.editingItem, renamed)
        XCTAssertNil(fixture.probe.presentation)
    }

    private struct Fixture {
        var store: TodoStore
        var item: TodoItem
        var schedule: DaySchedule
        var probe: TimelineWindowProbe
        var window: NSWindow
    }

    private func makeWindow() -> Fixture {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-Interaction-\(UUID())/todos.json"))
        let item = TodoItem(title: "Window interaction task", dueDate: day.date())
        XCTAssertTrue(store.upsert(item))
        let schedule = DaySchedule(startDay: day, startMinute: 540, durationMinutes: 60, content: .todo(item.id))
        XCTAssertTrue(store.upsertSchedule(schedule))
        let probe = TimelineWindowProbe()
        let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 680, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TimelineWindowHarness(day: day, probe: probe)
            .environmentObject(store))
        window.makeKeyAndOrderFront(nil)
        settle()
        return Fixture(store: store, item: item, schedule: schedule, probe: probe, window: window)
    }


    private func close(_ fixture: Fixture) {
        fixture.probe.presentation = nil
        fixture.probe.draft = nil
        fixture.probe.editingItem = nil
        settle()
        fixture.window.close()
    }

    private func dismissSheet(_ fixture: Fixture) {
        fixture.probe.editingItem = nil
        settle()
    }

    private func editorWindow(_ fixture: Fixture) -> NSWindow? {
        (NSApp.windows + (fixture.window.childWindows ?? [])).first {
            $0.isVisible && $0 !== fixture.window && $0 !== fixture.window.attachedSheet
                && hasEditorControls(in: $0.contentView ?? NSView())
        }
    }

    private func hasEditorControls(in view: NSView) -> Bool {
        // Linked tasks keep their title read-only; their editor can consist
        // entirely of native date pickers, without an editable text field.
        if view is NSDatePicker { return true }
        if let field = view as? NSTextField, field.isEditable { return true }
        return view.subviews.contains { hasEditorControls(in: $0) }
    }

    private func fields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).flatMap { $0.isEditable ? $0 : nil }
        return (own.map { [$0] } ?? []) + view.subviews.flatMap(fields(in:))
    }

    private func screenPoint(x: CGFloat, yFromTop: CGFloat, in window: NSWindow) -> CGPoint {
        let view = window.contentView!
        let point = CGPoint(x: x, y: view.isFlipped ? yFromTop : view.bounds.height - yFromTop)
        return window.convertPoint(toScreen: view.convert(point, to: nil))
    }

    private func edit(_ field: NSTextField, text: String, in window: NSWindow) {
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.selectAll(nil)
            editor.insertText(text, replacementRange: editor.selectedRange())
        } else {
            XCTFail("Expected a focused native text editor")
        }
    }

    private func click(_ screenPoint: CGPoint, in window: NSWindow, count: Int = 1) {
        let point = window.convertPoint(fromScreen: screenPoint)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0)!
            dispatch(event)
        }
    }

    private func doubleClick(_ point: CGPoint, in window: NSWindow) {
        click(point, in: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        click(point, in: window, count: 2)
    }

    private func escape(in window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        dispatch(event)
    }

    private func dispatch(_ event: NSEvent) {
        NSApp.postEvent(event, atStart: true)
        if let queued = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.1),
                                       inMode: .default, dequeue: true) {
            NSApp.sendEvent(queued)
        }
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(max(0.65, NSEvent.doubleClickInterval + 0.1))) }
}

@MainActor
@Observable
private final class TimelineWindowProbe {
    var presentation: SchedulePopoverRequest?
    var draft: DaySchedule?
    var editingItem: TodoItem?
    var editedIDs: [UUID] = []
    var menuTitles: [String] = []
}

@MainActor
private final class TimelineMenuObserver: NSObject {
    let probe: TimelineWindowProbe
    init(probe: TimelineWindowProbe) { self.probe = probe }

    @objc func didStartMenu(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        probe.menuTitles = menu.items.map(\.title)
        let index = menu.items.firstIndex { $0.title == L10n.string("编辑任务") }
        DispatchQueue.main.async {
            menu.cancelTrackingWithoutAnimation()
            if let index { menu.performActionForItem(at: index) }
        }
    }
}

private struct TimelineWindowHarness: View {
    @EnvironmentObject private var store: TodoStore
    let day: LocalDay
    @Bindable var probe: TimelineWindowProbe

    var body: some View {
        DayTimelineView(day: day, hourHeight: .constant(90), restoredScrollMinute: .constant(480), now: day.date(),
            presentation: $probe.presentation,
            create: { minute, duration, horizontal in
                probe.draft = DaySchedule(startDay: day, startMinute: minute, durationMinutes: duration,
                                          content: .independent(title: "", notes: ""),
                                          horizontalPosition: horizontal, horizontalPositionUpdatedAt: .now)
            }, dropTodo: { _, _, _ in }, editTodo: {
                probe.editedIDs.append($0.id)
                probe.editingItem = $0
            }, activityChanged: { _ in })
        .popover(item: $probe.draft) { schedule in
            ScheduleEditorView(schedule: schedule, isCreating: true, close: { probe.draft = nil }, editTodo: { _ in })
        }
        .sheet(item: $probe.editingItem) { item in
            TodoEditorView(item: item, isEditing: true) { store.upsert($0) }
        }
        .editorEscapeDismissal(enabled: probe.draft != nil || probe.presentation != nil) {
            probe.draft = nil
            probe.presentation = nil
        }
    }
}
