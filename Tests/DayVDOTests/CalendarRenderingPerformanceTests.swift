import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

/// A repeatable main-thread rendering workload, not a display FPS measurement.
@MainActor
final class CalendarRenderingPerformanceTests: XCTestCase {
    func testWeekEntryAndNativeScrollingWorkload() async throws {
        guard ProcessInfo.processInfo.environment["DAYVDO_RUN_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Enable DAYVDO_RUN_RENDER_BENCHMARK for the controlled rendering workload")
        }
        for count in [100, 1000] { try await runWorkload(itemCount: count) }
    }

    private func runWorkload(itemCount: Int) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-Render-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monday = LocalDay(year: 2026, month: 10, day: 19)
        let items = (0..<itemCount).map { index in
            let day = monday.adding(days: index % 42 - 14)
            return TodoItem(title: "Task \(index)", startDate: day.date(),
                            dueDate: day.adding(days: index % 5).date())
        }
        let schedules = items.enumerated().compactMap { index, item -> DaySchedule? in
            guard index.isMultiple(of: 4), let day = item.startDay else { return nil }
            return DaySchedule(startDay: day, startMinute: 480 + index % 600,
                               durationMinutes: 45, content: .todo(item.id))
        }
        let data: [String: Any] = ["version": 4,
            "items": try items.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) },
            "schedules": try schedules.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }]
        let file = directory.appendingPathComponent("todos.json")
        try JSONSerialization.data(withJSONObject: data).write(to: file)
        let store = TodoStore(fileURL: file)
        let cache = CalendarWindowCache()
        let calendar = AppCalendar.make(locale: L10n.locale, startsOnMonday: true)
        let key = CalendarWindowSnapshot.Key(revision: store.dateContentRevision,
            firstDay: monday.adding(days: -21), lastDay: monday.adding(days: 27),
            timeZoneIdentifier: calendar.timeZone.identifier, firstWeekday: 2,
            visibility: .init(showCompleted: true))
        cache.prepare(.init(key: key, items: items, tags: []))
        let ready = await cache.waitForSnapshot(covering: key, until: .now + .seconds(10))
        XCTAssertTrue(ready)
        let state = CalendarRenderWorkloadState()
        let hosting = NSHostingView(rootView: CalendarRenderWorkload(monday: monday,
            state: state, cache: cache).environmentObject(store).environmentObject(CalendarTodoSelection()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        var entries: [Double] = []
        for _ in 0..<3 {
            state.showsWeek = false; await drain(hosting, passes: 3)
            let start = CACurrentMediaTime()
            state.showsWeek = true; await drain(hosting, passes: 8)
            entries.append((CACurrentMediaTime() - start) * 1000)
        }
        let viewport = try XCTUnwrap(views(hosting).compactMap { $0 as? CalendarWeekNativeViewport }.first)
        let initialX = viewport.scroll.contentView.bounds.minX
        var horizontal: [Double] = []
        for step in 1...70 {
            let start = CACurrentMediaTime()
            viewport.scroll.contentView.scroll(to: NSPoint(x: initialX + CGFloat(step) * viewport.scroll.columnWidth / 8, y: 0))
            viewport.scroll.reflectScrolledClipView(viewport.scroll.contentView)
            await drain(hosting, passes: 2)
            horizontal.append((CACurrentMediaTime() - start) * 1000)
        }
        viewport.scroll.settled?()
        await drain(hosting, passes: 20)
        let firstDay = try XCTUnwrap(viewport.day(at: CGPoint(x: viewport.leadingInset + 1, y: 0)))
        let visibleWeek = LocalDay(calendar.dateInterval(of: .weekOfYear, for: firstDay.date())!.start)
        var nearby = key
        nearby.firstDay = visibleWeek.adding(days: -21)
        nearby.lastDay = visibleWeek.adding(days: 27)
        cache.prepare(.init(key: nearby, items: items, tags: []))
        let scrolledReady = await cache.waitForSnapshot(covering: nearby, until: .now + .seconds(10))
        XCTAssertTrue(scrolledReady)
        await drain(hosting, passes: 8)
        func p95(_ values: [Double]) -> Double { values.sorted()[Int(ceil(Double(values.count) * 0.95)) - 1] }
        var report: [String: Any] = ["items": itemCount, "entry_ms": entries,
            "horizontal_p95_ms": p95(horizontal), "horizontal_max_ms": horizontal.max()!]
        // A preloaded, offscreen week is not a user scroll target. Pick the
        // largest visible pane separately for date cards and the time grid.
        func visiblePanes() -> [NSScrollView] { views(viewport.document).compactMap { $0 as? NSScrollView }
            .filter { $0.bounds.width > 200 && $0.convert($0.bounds, to: hosting).intersection(hosting.bounds).width > 1 }
            .sorted { $0.convert($0.bounds, to: hosting).intersection(hosting.bounds).width
                > $1.convert($1.bounds, to: hosting).intersection(hosting.bounds).width } }
        for (name, isTimeline) in [("dates", false), ("timeline", true)] {
            let pane = try XCTUnwrap(visiblePanes().first {
                (abs(($0.documentView?.bounds.height ?? 0) - 2184) < 1) == isTimeline
            })
            let scrollable = (pane.documentView?.bounds.height ?? 0) > pane.contentSize.height + 1
            report[name + "_scrollable"] = scrollable
            guard scrollable else { continue }
            var samples: [Double] = []
            var stable = true
            for step in 1...40 {
                let pane = try XCTUnwrap(visiblePanes().first {
                    (abs(($0.documentView?.bounds.height ?? 0) - 2184) < 1) == isTimeline
                })
                let start = CACurrentMediaTime()
                let target = 100 + CGFloat(step) * 6
                pane.contentView.scroll(to: NSPoint(x: 0, y: target))
                pane.reflectScrolledClipView(pane.contentView)
                await drain(hosting, passes: 2)
                samples.append((CACurrentMediaTime() - start) * 1000)
                let current = try XCTUnwrap(visiblePanes().first {
                    (abs(($0.documentView?.bounds.height ?? 0) - 2184) < 1) == isTimeline
                })
                XCTAssertEqual(current.contentView.bounds.minY, target, accuracy: 1)
                if abs(current.contentView.bounds.minY - target) > 1 {
                    stable = false
                    break
                }
            }
            report[name + "_position_stable"] = stable
            if stable {
                report[name + "_p95_ms"] = p95(samples)
                report[name + "_max_ms"] = samples.max()!
            }
        }
        FileHandle.standardError.write(Data(("CALENDAR_RENDER_WORKLOAD " + String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)! + "\n").utf8))
    }

    private func drain(_ view: NSView, passes: Int) async {
        for _ in 0..<passes {
            view.layoutSubtreeIfNeeded(); view.window?.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
}

@MainActor
private final class CalendarRenderWorkloadState: ObservableObject {
    @Published var showsWeek = false
}

private struct CalendarRenderWorkload: View {
    let monday: LocalDay
    @ObservedObject var state: CalendarRenderWorkloadState
    @ObservedObject var cache: CalendarWindowCache
    @StateObject private var presentations = CalendarWeekPresentationCache()
    @State private var selectedDate = LocalDay(year: 2026, month: 10, day: 19).date()
    @State private var position = CalendarWeekViewportPosition()

    var body: some View {
        if state.showsWeek {
            CalendarWeekView(calendar: AppCalendar.make(locale: L10n.locale, startsOnMonday: true),
                visibility: .init(showCompleted: true), selectedDate: $selectedDate,
                position: position, windowCache: cache,
                presentationCache: presentations, createTodo: { _, _ in }, changeTodo: { _ in },
                editTodo: { _ in }, showMore: { _ in })
        } else { Color.clear }
    }
}
