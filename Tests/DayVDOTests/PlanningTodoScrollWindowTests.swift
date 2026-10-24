import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class PlanningTodoScrollWindowTests: XCTestCase {
    func testListEdgesAndMomentumDoNotScrollTimeline() async throws {
        try await checkContainment(itemCount: 24)
    }

    func testEmptyListDoesNotForwardWheelEvents() async throws {
        try await checkContainment(itemCount: 0)
    }

    private func checkContainment(itemCount: Int) async throws {
        _ = NSApplication.shared
        let day = LocalDay(.now)
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("Scroll-\(UUID()).json"))
        for index in 0..<itemCount { store.upsert(TodoItem(title: "Task \(index)", dueDate: day.date())) }
        let host = NSHostingView(rootView: PlanningScrollHarness(day: day).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 520),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        let all = scrollViews(in: host)
        let timeline = try XCTUnwrap(all.first { $0.bounds.width > 500 })
        let list = try XCTUnwrap(all.first { $0.bounds.width < 300 })
        XCTAssertTrue(list.superview?.enclosingScrollView === timeline,
                      "Both columns must share the timeline backdrop")
        XCTAssertNotEqual(list.verticalScrollElasticity, .none)
        timeline.contentView.scroll(to: CGPoint(x: 0, y: 500))
        timeline.reflectScrolledClipView(timeline.contentView)
        try await settle(host)
        let timelineY = timeline.contentView.bounds.minY
        for (atBottom, delta) in [(false, 35), (true, -35)] {
            // Lazy rows refine the document height after becoming visible.
            for _ in 0..<5 {
                let limit = atBottom ? max(-list.contentInsets.top, (list.documentView?.bounds.maxY ?? 0)
                    - list.contentSize.height + list.contentInsets.bottom) : -list.contentInsets.top
                list.contentView.scroll(to: CGPoint(x: 0, y: limit))
                list.reflectScrolledClipView(list.contentView)
                try await settle(host)
            }
            let limit = list.contentView.bounds.minY
            var greatestStretch: CGFloat = 0
            for (phase, momentum, amount) in [(1, 0, 0), (2, 0, delta), (2, 0, delta), (2, 0, delta),
                                               (4, 0, 0), (0, 1, delta / 2), (0, 2, delta / 3), (0, 4, 0)] {
                let event = wheel(delta: Int32(amount), phase: Int64(phase), momentum: Int64(momentum), in: list)
                window.sendEvent(event)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(25))
                let stretch = atBottom ? list.contentView.bounds.minY - limit : limit - list.contentView.bounds.minY
                greatestStretch = max(greatestStretch, stretch)
                XCTAssertEqual(timeline.contentView.bounds.minY, timelineY, accuracy: 0.5,
                               "List edge \(atBottom), phase \(phase), momentum \(momentum) must stay in the list")
            }
            XCTAssertGreaterThan(greatestStretch, 1, "AppKit must visibly stretch at the edge")
            try await Task.sleep(for: .milliseconds(800))
            try await settle(host)
            XCTAssertEqual(list.contentView.bounds.minY, limit, accuracy: 1, "AppKit must spring back after release")
        }
        if itemCount > 0 {
            list.contentView.scroll(to: CGPoint(x: 0, y: 100))
            list.reflectScrolledClipView(list.contentView)
            for (phase, amount) in [(1, 0), (2, -40), (2, -40), (4, 0)] {
                window.sendEvent(wheel(delta: Int32(amount), phase: Int64(phase), in: list))
                try await Task.sleep(for: .milliseconds(25))
            }
            try await settle(host)
            XCTAssertGreaterThan(list.contentView.bounds.minY, 100, "Ordinary list scrolling remains native")
        }
        for (phase, amount) in [(1, 0), (2, -50), (2, -50), (4, 0)] {
            window.sendEvent(wheel(delta: Int32(amount), phase: Int64(phase), in: timeline))
            try await Task.sleep(for: .milliseconds(25))
        }
        try await settle(host)
        XCTAssertGreaterThan(timeline.contentView.bounds.minY, timelineY, "Scrolling over the timeline still moves it")
    }

    private func wheel(delta: Int32, phase: Int64, momentum: Int64 = 0, in view: NSView) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: delta, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        let window = view.window!
        let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let screenPoint = window.convertPoint(toScreen: point)
        event.location = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ProcessInfo.processInfo.processIdentifier))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        let bound = PlanningWheelEvent()
        bound.base = NSEvent(cgEvent: event)!
        bound.eventWindow = view.window
        bound.eventWindowNumber = view.window!.windowNumber
        bound.windowPoint = point
        return bound
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            host.window?.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(15))
        }
    }
}

private struct PlanningScrollHarness: View {
    @State var day: LocalDay
    @State private var editing: TodoItem?
    @State private var hourHeight: CGFloat = 90
    @State private var scrollMinute: CGFloat?
    var body: some View {
        TodayView(editingItem: $editing, selectedDay: $day, hourHeight: $hourHeight,
                  timelineScrollMinute: $scrollMinute)
    }
}

private final class PlanningWheelEvent: NSEvent {
    var base: NSEvent!
    weak var eventWindow: NSWindow?
    var eventWindowNumber = 0
    var windowPoint = NSPoint.zero
    override var window: NSWindow? { eventWindow }
    override var windowNumber: Int { eventWindowNumber }
    override var locationInWindow: NSPoint { windowPoint }
    override var type: NSEvent.EventType { .scrollWheel }
    override var timestamp: TimeInterval { base.timestamp }
    override var modifierFlags: NSEvent.ModifierFlags { base.modifierFlags }
    override var scrollingDeltaX: CGFloat { base.scrollingDeltaX }
    override var scrollingDeltaY: CGFloat { base.scrollingDeltaY }
    override var deltaX: CGFloat { base.deltaX }
    override var deltaY: CGFloat { base.deltaY }
    override var phase: NSEvent.Phase { base.phase }
    override var momentumPhase: NSEvent.Phase { base.momentumPhase }
    override var hasPreciseScrollingDeltas: Bool { base.hasPreciseScrollingDeltas }
    override var cgEvent: CGEvent? { base.cgEvent }
}
