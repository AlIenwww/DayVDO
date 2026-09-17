import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TimelinePopoverPresentationTests: XCTestCase {
    func testIndependentDetailsAndEditorPopoversPresentFromARealWindow() {
        let day = LocalDay(year: 2026, month: 9, day: 4)
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-PopoverWindowTest-\(UUID()).json"))
        let block = DaySchedule(
            startDay: day,
            startMinute: 540,
            durationMinutes: 30,
            content: .independent(title: "Window test", notes: "")
        )
        XCTAssertTrue(store.upsertSchedule(block))

        let app = NSApplication.shared
        let commandName = Notification.Name("DayVDO-TimelinePopover-\(UUID())")
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 640, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: TimelinePopoverHarness(day: day, commandName: commandName)
                .environmentObject(store)
        )
        let existingWindows = Set(app.windows.map(\.windowNumber))
        window.makeKeyAndOrderFront(nil)
        defer {
            NotificationCenter.default.post(name: commandName, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            window.close()
        }

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        NotificationCenter.default.post(name: commandName, object: SchedulePopoverRequest.details(block.id))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(hasVisiblePopover(in: window, app: app, excluding: existingWindows))
        XCTAssertTrue(editableTextFields(in: popoverWindows(in: window, app: app, excluding: existingWindows)).isEmpty)

        NotificationCenter.default.post(name: commandName, object: SchedulePopoverRequest.editor(block.id))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(hasVisiblePopover(in: window, app: app, excluding: existingWindows))
        XCTAssertFalse(editableTextFields(in: popoverWindows(in: window, app: app, excluding: existingWindows)).isEmpty)
    }

    private func hasVisiblePopover(
        in window: NSWindow,
        app: NSApplication,
        excluding existingWindows: Set<Int>
    ) -> Bool {
        !popoverWindows(in: window, app: app, excluding: existingWindows).isEmpty
    }

    private func popoverWindows(
        in window: NSWindow,
        app: NSApplication,
        excluding existingWindows: Set<Int>
    ) -> [NSWindow] {
        let presentedWindows = app.windows.filter {
            $0.isVisible && $0 !== window && !existingWindows.contains($0.windowNumber)
        }
        let attachedWindows = (window.childWindows ?? []).filter(\.isVisible)
        return presentedWindows + attachedWindows.filter { child in
            !presentedWindows.contains(where: { $0 === child })
        }
    }

    private func editableTextFields(in windows: [NSWindow]) -> [NSTextField] {
        windows.compactMap(\.contentView).flatMap(editableTextFields(in:))
    }

    private func editableTextFields(in view: NSView) -> [NSTextField] {
        let field = (view as? NSTextField).flatMap { $0.isEditable ? $0 : nil }
        return (field.map { [$0] } ?? []) + view.subviews.flatMap(editableTextFields(in:))
    }
}

private struct TimelinePopoverHarness: View {
    let day: LocalDay
    let commandName: Notification.Name
    @State private var request: SchedulePopoverRequest?

    var body: some View {
        DayTimelineView(
            day: day,
            hourHeight: .constant(90),
            restoredScrollMinute: .constant(nil),
            now: day.date(),
            presentation: $request,
            create: { _, _ in },
            dropTodo: { _, _ in },
            editTodo: { _ in },
            activityChanged: { _ in }
        )
        .onReceive(NotificationCenter.default.publisher(for: commandName)) { notification in
            request = notification.object as? SchedulePopoverRequest
        }
    }
}
