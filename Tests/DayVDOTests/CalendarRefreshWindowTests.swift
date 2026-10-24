import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class CalendarRefreshWindowTests: XCTestCase {
    func testMonthEditsKeepUnrelatedTaskBarsVisible() async throws {
        try await checkRefresh(mode: .month)
    }

    func testWeekEditsKeepUnrelatedTaskBarsVisible() async throws {
        try await checkRefresh(mode: .week)
    }

    func testMonthDropIntoOccupiedDayKeepsTheFinalLane() async throws {
        try await checkRefresh(mode: .month, dropOffset: 4)
    }

    func testWeekDropIntoOccupiedDayKeepsTheFinalLane() async throws {
        try await checkRefresh(mode: .week, dropOffset: 4)
    }

    func testMonthDropIntoAnotherOccupiedWeekKeepsTheFinalLane() async throws {
        try await checkRefresh(mode: .month, dropOffset: 11)
    }

    func testPendingDropUsesCurrentWeekMembershipAndOrder() async throws {
        _ = NSApplication.shared
        let monday = LocalDay(year: 2026, month: 10, day: 5)
        for targetWeek in [monday, monday.adding(days: 7)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-PendingDrop-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
            let target = targetWeek.adding(days: 4)
            let existing = TodoItem(title: "Existing", dueDate: target.date())
            var moving = TodoItem(title: "Moving", dueDate: monday.adding(days: 1).date())
            XCTAssertTrue(store.upsert(existing))
            XCTAssertTrue(store.upsert(moving))
            let key = CalendarWindowSnapshot.Key(revision: store.contentRevision,
                firstDay: monday, lastDay: monday.adding(days: 13),
                timeZoneIdentifier: TimeZone.current.identifier, firstWeekday: 2,
                visibility: .init(showCompleted: true))
            let beforeDrop = CalendarWindowSnapshot.build(key: key, items: store.items, tags: [])
            let probe = CalendarRefreshProbe()
            let hosting = NSHostingView(rootView: CalendarDateWeekRow(
                interaction: CalendarDateInteraction(), week: targetWeek, selected: target, month: target.month,
                items: beforeDrop.items(inWeek: targetWeek), select: { _ in }, showMore: { _ in }, edit: { _ in })
                .environmentObject(store).environmentObject(CalendarTodoSelection())
                .coordinateSpace(name: "calendarDateViewport")
                .onPreferenceChange(CalendarDateHitRegions.self) { probe.record($0) })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 140),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.contentView = nil; window.close() }
            try await settle(hosting)
            moving.startDay = target; moving.dueDay = target
            XCTAssertTrue(store.upsert(moving))
            // Freeze the pre-drop snapshot to exercise the entire pending phase.
            try await settle(hosting)
            XCTAssertGreaterThan(try XCTUnwrap(probe.frames[moving.id]).minY,
                                 try XCTUnwrap(probe.frames[existing.id]).minY)
            let saved = await store.flushPersistence()
            XCTAssertTrue(saved)
        }
    }

    private func checkRefresh(mode: CalendarDisplayMode, dropOffset: Int? = nil) async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: "calendarDisplayMode")
        defaults.set(mode.rawValue, forKey: "calendarDisplayMode")
        defer {
            if let previousMode { defaults.set(previousMode, forKey: "calendarDisplayMode") }
            else { defaults.removeObject(forKey: "calendarDisplayMode") }
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-CalendarRefresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        store.settings.startWeekOnMonday = true
        let monday = LocalDay(year: 2026, month: 10, day: 5)
        let unchanged = TodoItem(title: "Always visible", dueDate: monday.adding(days: dropOffset ?? 0).date())
        var edited = TodoItem(title: "Edit this task", dueDate: monday.adding(days: 1).date())
        XCTAssertTrue(store.upsert(unchanged))
        XCTAssertTrue(store.upsert(edited))
        let monthCache = CalendarWindowCache()
        let weekCache = CalendarWindowCache()
        let visibility = TodoFilterContext(showCompleted: true)
        let calendar = AppCalendar.make(locale: L10n.locale, startsOnMonday: true)
        let initialKey = CalendarWindowSnapshot.Key(revision: store.contentRevision,
            firstDay: monday.adding(days: -84), lastDay: monday.adding(days: 125),
            timeZoneIdentifier: calendar.timeZone.identifier, firstWeekday: 2, visibility: visibility)
        for cache in [monthCache, weekCache] {
            cache.prepare(.init(key: initialKey, items: store.items, tags: store.tags))
            let ready = await cache.waitForSnapshot(covering: initialKey, until: .now + .seconds(2))
            XCTAssertTrue(ready)
        }
        let session = CalendarTimelineSession()
        session.topWeek = monday
        let probe = CalendarRefreshProbe()
        let hosting = NSHostingView(rootView: CalendarView(
            editingItem: .constant(nil), filter: .constant(.init()), visibility: visibility,
            columnVisibility: .constant(.all), selectedDate: .constant(monday.date()),
            currentMonth: .constant(monday.date()), weekPosition: CalendarWeekViewportPosition(scrollMinute: 480),
            isInspectorPresented: .constant(false),
            windowCache: monthCache, weekCache: weekCache,
            weekPresentationCache: CalendarWeekPresentationCache(), timelineSession: session)
            .environmentObject(store)
            .onPreferenceChange(CalendarDateHitRegions.self) { values in
                probe.record(values)
            })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
            monthCache.cancel()
            weekCache.cancel()
        }
        // Lay out the real calendar without bringing a test window to the front.
        try await settle(hosting)
        XCTAssertTrue(probe.current.contains(unchanged.id))
        XCTAssertTrue(probe.current.contains(edited.id))
        probe.samples.removeAll()

        if let dropOffset {
            try await checkDrop(from: monday, offset: dropOffset, edited: edited,
                occupied: unchanged, hosting: hosting, store: store, probe: probe)
        } else {
            for offset in [2, 3, 1] {
                edited.startDay = monday.adding(days: offset)
                edited.dueDay = edited.startDay
                XCTAssertTrue(store.upsert(edited))
                try await settle(hosting)
                XCTAssertTrue(probe.current.contains(edited.id))
            }
            let added = TodoItem(title: "New task", dueDate: monday.adding(days: 4).date())
            XCTAssertTrue(store.upsert(added))
            try await settle(hosting)
            XCTAssertTrue(probe.current.contains(added.id))
            XCTAssertTrue(store.delete(edited))
            try await settle(hosting)
            XCTAssertFalse(probe.current.contains(edited.id))
        }
        XCTAssertFalse(probe.samples.isEmpty)
        XCTAssertTrue(probe.samples.allSatisfy { $0.contains(unchanged.id) },
            "Editing one task must not remove an unrelated bar during any layout pass")
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func checkDrop(from monday: LocalDay, offset: Int, edited: TodoItem, occupied: TodoItem,
                           hosting: NSView, store: TodoStore, probe: CalendarRefreshProbe) async throws {
        let input = try XCTUnwrap(findInput(in: hosting, matching: edited.id))
        let source = try XCTUnwrap(input.regions.first {
            if case let .item(id, _, _) = $0.target { return id == edited.id }
            return false
        }?.frame)
        let targetWeek = monday.adding(days: offset / 7 * 7)
        // Each native week has its own hit regions; its viewport owns date
        // conversion across week boundaries. Month still uses shared row frames.
        let weekFrame: CGRect
        if input.calendarWeekViewport != nil {
            weekFrame = CGRect(x: 0, y: 0, width: input.bounds.width, height: input.bounds.height)
        } else {
            weekFrame = try XCTUnwrap(input.interaction?.frames[targetWeek])
        }
        let target = CGPoint(x: weekFrame.minX + (CGFloat(offset % 7) + 0.5) * weekFrame.width / 7,
                             y: weekFrame.minY + source.midY - (input.interaction?.frames[monday]?.minY ?? 0))
        input.pointerDown(at: CGPoint(x: source.midX, y: source.midY), clickCount: 1)
        input.pointerDragged(to: target)
        try await settle(hosting)
        let preview = try XCTUnwrap(probe.frames[edited.id])
        let existing = try XCTUnwrap(probe.frames[occupied.id])
        XCTAssertGreaterThan(preview.minY, existing.minY, "The preview uses the same lane as the saved task")
        probe.frameSamples.removeAll()

        input.pointerUp(at: target)
        try await settle(hosting)
        XCTAssertEqual(store.item(withID: edited.id)?.startDay, monday.adding(days: offset))
        XCTAssertEqual(store.item(withID: edited.id)?.dueDay, monday.adding(days: offset))
        XCTAssertEqual(try XCTUnwrap(probe.frames[edited.id]).minY, preview.minY, accuracy: 0.5)
        for sample in probe.frameSamples {
            let frame = try XCTUnwrap(sample[edited.id], "The dropped task stays visible while its snapshot refreshes")
            XCTAssertEqual(frame.minY, preview.minY, accuracy: 0.5, "Dropping must not pass through a temporary top lane")
        }
    }

    private func findInput(in view: NSView, matching id: UUID) -> CalendarDateInput.InputView? {
        if let input = view as? CalendarDateInput.InputView,
           input.regions.contains(where: { if case let .item(itemID, _, _) = $0.target { return itemID == id }; return false }) {
            return input
        }
        return view.subviews.lazy.compactMap { self.findInput(in: $0, matching: id) }.first
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

@MainActor
private final class CalendarRefreshProbe {
    var current: Set<UUID> = []
    var samples: [Set<UUID>] = []
    var frames: [UUID: CGRect] = [:]
    var frameSamples: [[UUID: CGRect]] = []

    func record(_ values: [LocalDay: [CalendarDateHitRegion]]) {
        frames = Dictionary(values.values.flatMap { $0 }.compactMap { region -> (UUID, CGRect)? in
            if case let .item(id, _, _) = region.target { return (id, region.frame) }
            return nil
        }, uniquingKeysWith: { first, _ in first })
        current = Set(frames.keys)
        samples.append(current)
        frameSamples.append(frames)
    }
}
