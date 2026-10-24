import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TodayHeaderWindowTests: XCTestCase {
    func testZoomAndNativeScrollKeepListFixedBeforeSwiftUIProcessesScrollGeometry() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-PinnedList-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let day = LocalDay(.now)
        for index in 0..<20 { store.upsert(TodoItem(title: "Task \(index)", dueDate: day.date())) }
        let zoom = PlanningZoomState()
        let hosting = NSHostingView(rootView: PlanningZoomHarness(day: day, zoom: zoom).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        try await settle(hosting)
        let scrolls = findScrollViews(in: hosting).sorted { $0.bounds.width > $1.bounds.width }
        let timeline = try XCTUnwrap(scrolls.first)
        let panel = try XCTUnwrap(scrolls.last)
        XCTAssertEqual(scrolls.count, 2)
        panel.contentView.scroll(to: NSPoint(x: 0, y: 120))
        panel.reflectScrolledClipView(panel.contentView)
        try await settle(hosting)
        let listOffset = panel.contentView.bounds.minY
        let frame = panel.convert(panel.bounds, to: hosting)

        for height: CGFloat in [45, 180, 90] {
            zoom.hourHeight = height
            try await settle(hosting)
            for offset: CGFloat in [0, 400, 100] {
                timeline.contentView.scroll(to: NSPoint(x: 0, y: offset))
                timeline.reflectScrolledClipView(timeline.contentView)
                // Check immediately: a later SwiftUI update cannot hide a frame
                // that briefly moved with the document during zooming.
                let current = panel.convert(panel.bounds, to: hosting)
                XCTAssertEqual(current.minY, frame.minY, accuracy: 1)
                XCTAssertEqual(current.height, frame.height, accuracy: 1)
                XCTAssertEqual(panel.contentView.bounds.minY, listOffset, accuracy: 1)
                let hit = hosting.hitTest(NSPoint(x: current.midX, y: current.midY))
                XCTAssertTrue(hit?.enclosingScrollView === panel)
                try await settle(hosting)
            }
        }
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    func testSharedToolbarViewportKeepsBothColumnsInteractiveAcrossResizing() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-Header-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let day = LocalDay(.now)
        for number in 0..<16 {
            store.upsert(TodoItem(title: "Todo \(number)", dueDate: day.date()))
        }
        store.upsertSchedule(DaySchedule(startDay: day, startMinute: 547,
                                         durationMinutes: 45,
                                         content: .independent(title: "Plan", notes: "")))
        let hosting = NSHostingView(rootView: TodayView(
            editingItem: .constant(nil), selectedDay: .constant(day),
            hourHeight: .constant(90), timelineScrollMinute: .constant(nil))
            .environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }

        for width: CGFloat in [900, 620, 900] {
            window.setContentSize(NSSize(width: width, height: 600))
            for _ in 0..<8 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
            let scrolls = findScrollViews(in: hosting).sorted { $0.bounds.width > $1.bounds.width }
            XCTAssertEqual(scrolls.count, width >= 720 ? 2 : 1)
            let timeline = try XCTUnwrap(scrolls.first)
            let frame = timeline.convert(timeline.bounds, to: hosting)
            XCTAssertEqual(frame.minX, 0, accuracy: 1)
            XCTAssertEqual(frame.width, hosting.bounds.width, accuracy: 1,
                           "The default native toolbar needs one full-width viewport")
            if width >= 720 {
                let panel = try XCTUnwrap(scrolls.last)
                let panelFrame = panel.convert(panel.bounds, to: hosting)
                XCTAssertEqual(panelFrame.maxX, hosting.bounds.maxX, accuracy: 1)
                XCTAssertEqual(panelFrame.width, 280, accuracy: 1)
                XCTAssertEqual(panelFrame.minY, frame.minY, accuracy: 1,
                               "Both columns extend behind the one shared native header")
                XCTAssertTrue(panel.superview?.enclosingScrollView === timeline,
                              "The native header must sample both columns in the same scroll surface")
                XCTAssertEqual(panel.contentInsets.top, timeline.contentInsets.top, accuracy: 1,
                               "The initial list content must start below the shared header")
                let hit = hosting.hitTest(NSPoint(x: panelFrame.midX, y: panelFrame.midY))
                XCTAssertTrue(hit?.enclosingScrollView === panel,
                              "Right-column input must reach its own scroll view: \(String(describing: hit))")

                panel.contentView.scroll(to: NSPoint(x: 0, y: 200))
                panel.reflectScrolledClipView(panel.contentView)
                try await settle(hosting)
                let panelOffset = panel.contentView.bounds.minY
                let fixedFrame = panel.convert(panel.bounds, to: hosting)
                timeline.contentView.scroll(to: NSPoint(x: 0, y: timeline.contentView.bounds.minY + 90))
                timeline.reflectScrolledClipView(timeline.contentView)
                try await settle(hosting)
                XCTAssertEqual(panel.contentView.bounds.minY, panelOffset, accuracy: 1,
                               "Scrolling the timeline must not scroll the list")
                XCTAssertEqual(panel.convert(panel.bounds, to: hosting).minY, fixedFrame.minY, accuracy: 1,
                               "The list must stay fixed within the shared viewport")
            }
        }
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func findScrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { findScrollViews(in: $0) }
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<8 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

@MainActor
private final class PlanningZoomState: ObservableObject {
    @Published var hourHeight: CGFloat = 90
}

private struct PlanningZoomHarness: View {
    let day: LocalDay
    @ObservedObject var zoom: PlanningZoomState

    var body: some View {
        TodayView(editingItem: .constant(nil), selectedDay: .constant(day),
                  hourHeight: $zoom.hourHeight, timelineScrollMinute: .constant(nil))
    }
}
