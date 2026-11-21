import AppKit
import Observation
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TimelineInteractionWindowTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 5)

    func testBlankTimelineClickDoesNotOpenCreationDraft() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        fixture.store.settings.defaultScheduleMinutes = 37
        settle()
        click(screenPoint(x: 300, yFromTop: 260, in: fixture.window), in: fixture.window)
        settle()
        XCTAssertNil(fixture.probe.draft)
        XCTAssertNil(fixture.probe.presentation)
        XCTAssertEqual(fixture.store.schedules, [fixture.schedule])
    }

    func testBlankTimelineClickClearsSelectionBeforeDelete() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        let card = screenPoint(x: 620, yFromTop: 145, in: fixture.window)
        for x: CGFloat in [300, 20] {
            click(card, in: fixture.window)
            settle()
            click(screenPoint(x: x, yFromTop: 260, in: fixture.window), in: fixture.window)
            settle()
            pressDelete(in: fixture.window)
            settle()
            XCTAssertEqual(fixture.store.schedules, [fixture.schedule])
        }
        click(card, in: fixture.window)
        settle()
        pressDelete(in: fixture.window)
        settle()
        XCTAssertTrue(fixture.store.schedules.isEmpty)
    }

    func testConsecutiveArrangementsKeepTheirAbsoluteTimeHitRegions() throws {
        let additional = [(600, 30), (630, 25), (655, 90)].map { minute, duration in
            DaySchedule(startDay: day, startMinute: minute, durationMinutes: duration,
                content: .independent(title: "Plan \(minute)", notes: ""))
        }
        let fixture = makeWindow(additionalSchedules: additional)
        defer { close(fixture) }
        let schedules = [fixture.schedule] + additional
        let view = try XCTUnwrap(fixture.window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        for schedule in schedules {
            let middle = CGFloat(schedule.startMinute - 480) * 1.5 + 12
                + CGFloat(schedule.durationMinutes) * 0.75
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(620 * scaleX), y: Int(middle * scaleY)))
            assertCardPaint(color, schedule: schedule)
        }
        if let path = ProcessInfo.processInfo.environment["DAYVDO_TIMELINE_SNAPSHOT"] {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        for schedule in schedules {
            let middle = CGFloat(schedule.startMinute - 480) * 1.5 + 12
                + CGFloat(schedule.durationMinutes) * 0.75
            doubleClick(screenPoint(x: 620, yFromTop: middle, in: fixture.window), in: fixture.window)
            settle()
            XCTAssertEqual(fixture.probe.presentation?.scheduleID, schedule.id,
                "Card hit region must match its time, without stacking previous card heights")
            if let editor = editorWindow(fixture) { escape(in: editor); settle() }
        }
        XCTAssertEqual(Set(fixture.store.schedules.map(\.id)), Set(schedules.map(\.id)))
    }

    func testWeekArrangementsPaintAtTheirAbsoluteTimes() throws {
        let additional = [(600, 30), (630, 25), (655, 90)].map { minute, duration in
            DaySchedule(startDay: day, startMinute: minute, durationMinutes: duration,
                content: .independent(title: "Plan \(minute)", notes: ""))
        }
        let fixture = makeWindow(additionalSchedules: additional)
        defer { close(fixture) }
        let host = NSHostingView(rootView: CalendarWeekTimeline(week: day,
            visibility: .init(showCompleted: true), hourHeight: .constant(90),
            scrollMinute: .constant(480), presentationCache: CalendarWeekPresentationCache(),
            editTodo: { _ in }).environmentObject(fixture.store))
        fixture.window.contentView = host
        settle()
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        for schedule in [fixture.schedule] + additional {
            let middle = CGFloat(schedule.startMinute - 480) * 1.5 + 12
                + CGFloat(schedule.durationMinutes) * 0.75
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(130 * scaleX), y: Int(middle * scaleY)))
            assertCardPaint(color, schedule: schedule)
        }
    }

    func testWeekTimelineBlankClickDoesNotShowFocusBorder() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        let host = NSHostingView(rootView: CalendarWeekView(
            calendar: AppCalendar.make(locale: L10n.locale, startsOnMonday: true),
            visibility: .init(showCompleted: true), selectedDate: .constant(day.date()),
            position: CalendarWeekViewportPosition(scrollMinute: 480), windowCache: CalendarWindowCache(),
            presentationCache: CalendarWeekPresentationCache(), createTodo: { _, _ in }, changeTodo: { _ in },
            editTodo: { _ in }, showMore: { _ in })
            .environmentObject(fixture.store).environmentObject(CalendarTodoSelection()))
        fixture.window.contentView = host
        fixture.window.makeKeyAndOrderFront(nil)
        settle()

        func viewport(in view: NSView) -> CalendarWeekNativeViewport? {
            (view as? CalendarWeekNativeViewport) ?? view.subviews.lazy.compactMap { viewport(in: $0) }.first
        }
        XCTAssertEqual(try XCTUnwrap(viewport(in: host)).scroll.focusRingType, .none)
        XCTAssertTrue(fixture.window.makeFirstResponder(nil))
        let responder = fixture.window.firstResponder
        for x: CGFloat in [300, 34] {
            click(screenPoint(x: x, yFromTop: host.bounds.height - 34, in: fixture.window), in: fixture.window)
            settle()
            XCTAssertTrue(fixture.window.firstResponder === responder)
        }
    }

    func testWeekArrangementCanMoveAcrossDaysAndCancelAnotherMove() throws {
        let fixture = makeWindow()
        defer { close(fixture) }
        let cache = CalendarWeekPresentationCache()
        fixture.window.contentView = NSHostingView(rootView: CalendarWeekTimeline(week: day,
            visibility: .init(showCompleted: true), hourHeight: .constant(90),
            scrollMinute: .constant(480), presentationCache: cache,
            editTodo: { _ in }).environmentObject(fixture.store))
        settle()

        let source = screenPoint(x: 130, yFromTop: 145, in: fixture.window)
        let target = screenPoint(x: 220, yFromTop: 175, in: fixture.window)
        mouse(.leftMouseDown, at: source, in: fixture.window)
        mouse(.leftMouseDragged, at: screenPoint(x: 137, yFromTop: 151, in: fixture.window),
              in: fixture.window)
        mouse(.leftMouseDragged, at: target, in: fixture.window)
        settle()
        XCTAssertEqual(cache.dragPreview?.startDay, day.adding(days: 1))
        XCTAssertEqual(fixture.store.schedule(withID: fixture.schedule.id), fixture.schedule)
        mouse(.leftMouseUp, at: target, in: fixture.window)
        settle()
        let moved = try XCTUnwrap(fixture.store.schedule(withID: fixture.schedule.id))
        XCTAssertEqual(moved.startDay, day.adding(days: 1))
        XCTAssertEqual(moved.startMinute, 560)
        XCTAssertNil(cache.dragPreview)

        mouse(.leftMouseDown, at: target, in: fixture.window)
        mouse(.leftMouseDragged, at: source, in: fixture.window)
        settle()
        XCTAssertNotNil(cache.dragPreview)
        escape(in: fixture.window)
        mouse(.leftMouseUp, at: source, in: fixture.window)
        settle()
        XCTAssertNil(cache.dragPreview)
        XCTAssertEqual(fixture.store.schedule(withID: moved.id), moved)

        let bottomHandle = screenPoint(x: 220, yFromTop: 218, in: fixture.window)
        let extended = screenPoint(x: 220, yFromTop: 248, in: fixture.window)
        mouse(.leftMouseDown, at: bottomHandle, in: fixture.window)
        mouse(.leftMouseDragged, at: extended, in: fixture.window)
        settle()
        XCTAssertEqual(cache.dragPreview?.durationMinutes, 80)
        mouse(.leftMouseUp, at: extended, in: fixture.window)
        settle()
        XCTAssertEqual(fixture.store.schedule(withID: moved.id)?.durationMinutes, 80)

        let blank = screenPoint(x: 310, yFromTop: 270, in: fixture.window)
        let blankEnd = screenPoint(x: 310, yFromTop: 315, in: fixture.window)
        for _ in 0..<2 {
            click(blank, in: fixture.window)
            settle()
            XCTAssertNil(editorWindow(fixture), "Clicking empty time must not open a creation editor")
        }
        mouse(.leftMouseDown, at: blank, in: fixture.window)
        mouse(.leftMouseDragged, at: blankEnd, in: fixture.window)
        mouse(.leftMouseUp, at: blankEnd, in: fixture.window)
        settle()
        XCTAssertNotNil(editorWindow(fixture))
        XCTAssertEqual(fixture.store.schedules.count, 1, "Creating a draft must wait for confirmation")
    }

    private func assertCardPaint(_ color: NSColor, schedule: DaySchedule,
                                 file: StaticString = #filePath, line: UInt = #line) {
        if schedule.todoID == nil {
            // Independent cards use secondaryLabelColor (itself translucent)
            // at 14% opacity. These sample points avoid text, borders and grid lines.
            XCTAssertEqual(color.alphaComponent, NSColor.secondaryLabelColor.alphaComponent * 0.14,
                accuracy: 0.01, "Card must paint at minute \(schedule.startMinute)", file: file, line: line)
        } else {
            XCTAssertGreaterThan(color.alphaComponent, 0.1,
                "Linked card must paint at minute \(schedule.startMinute)", file: file, line: line)
        }
    }

    private func pressDelete(in window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: 51)!
        dispatch(event)
    }

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
        // The compact title-only header is 31 points shorter than the former title/subtitle header.
        click(screenPoint(x: 440, yFromTop: 367, in: sheet), in: sheet)
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

    private func makeWindow(additionalSchedules: [DaySchedule] = []) -> Fixture {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-Interaction-\(UUID())/todos.json"))
        let item = TodoItem(title: "Window interaction task", dueDate: day.date())
        XCTAssertTrue(store.upsert(item))
        let schedule = DaySchedule(startDay: day, startMinute: 540, durationMinutes: 60, content: .todo(item.id))
        XCTAssertTrue(store.upsertSchedule(schedule))
        for value in additionalSchedules { XCTAssertTrue(store.upsertSchedule(value)) }
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
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            mouse(type, at: screenPoint, in: window, count: count)
        }
    }

    private func mouse(_ type: NSEvent.EventType, at screenPoint: CGPoint, in window: NSWindow, count: Int = 1) {
        let event = NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screenPoint), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!
        dispatch(event)
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
            ScheduleEditorView(schedule: schedule, close: { probe.draft = nil }, editTodo: { _ in })
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
