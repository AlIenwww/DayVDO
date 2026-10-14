import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TimelineInitialPositionWindowTests: XCTestCase {
    private let day = LocalDay(year: 2026, month: 10, day: 11)

    func testFirstLayoutShowsEarliestArrangementInsteadOfMidnightOrCurrentTime() async throws {
        try await check(schedules: [schedule(minute: 900), schedule(minute: 547)], expectedMinute: 547)
    }

    func testEmptyTodayStartsAtCurrentTimeAndOtherDatesStartAtMidnight() async throws {
        try await check(schedules: [], expectedMinute: 17 * 60)
        try await check(schedules: [], now: day.adding(days: 1).date(), expectedMinute: 0)
        // Near midnight, clamp the viewport while keeping the red line visible.
        try await check(schedules: [], now: day.date().addingTimeInterval(11.75 * 3600),
                        expectedMinute: (90 * 24 + 24 - 560) / 1.5)
    }

    func testOvernightArrangementStillStartsAtMidnight() async throws {
        let overnight = DaySchedule(startDay: day.adding(days: -1), startMinute: 1380,
                                    durationMinutes: 120, content: .independent(title: "Overnight", notes: ""))
        try await check(schedules: [schedule(minute: 547), overnight], expectedMinute: 0)
    }

    func testSavedPagePositionWinsAndEditingDoesNotRelocateTheViewport() async throws {
        try await check(schedules: [schedule(minute: 547)], restoredMinute: 720, expectedMinute: 720,
                        addEarlierSchedule: true)
    }

    private func schedule(minute: Int) -> DaySchedule {
        DaySchedule(startDay: day, startMinute: minute, durationMinutes: 45,
                    content: .independent(title: "Plan", notes: ""))
    }

    private func check(schedules: [DaySchedule], restoredMinute: CGFloat? = nil, now: Date? = nil,
                       expectedMinute: CGFloat, addEarlierSchedule: Bool = false) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-InitialPosition-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        for schedule in schedules { XCTAssertTrue(store.upsertSchedule(schedule)) }
        let hosting = NSHostingView(rootView: DayTimelineView(
            day: day, hourHeight: .constant(90), restoredScrollMinute: .constant(restoredMinute),
            now: now ?? day.date().addingTimeInterval(5 * 3600), presentation: .constant(nil),
            create: { _, _, _ in }, dropTodo: { _, _, _ in }, editTodo: { _ in }, activityChanged: { _ in })
            .environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        try await settle(hosting)
        let scroll = try XCTUnwrap(findScrollView(in: hosting))
        XCTAssertEqual(scroll.contentView.bounds.minY, expectedMinute * 1.5, accuracy: 2)
        if addEarlierSchedule {
            XCTAssertTrue(store.upsertSchedule(schedule(minute: 300)))
            try await settle(hosting)
            XCTAssertEqual(scroll.contentView.bounds.minY, expectedMinute * 1.5, accuracy: 2)
        }
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<8 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}
