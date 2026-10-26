import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

final class CalendarWeekScrollPolicyTests: XCTestCase {
    func testSlowDragStopsAtADayEvenWithReleaseSpike() {
        XCTAssertEqual(target(start: 364, end: 365.2, duration: 0.8, velocity: 6), 365)
        XCTAssertEqual(target(start: 364, end: 362.8, duration: 0.8, velocity: -6), 363)
    }
    func testShortFlickGoesToAdjacentWeekInReleaseDirection() {
        XCTAssertEqual(target(start: 364, end: 365.1, duration: 0.12, velocity: 9), 371)
        XCTAssertEqual(target(start: 364, end: 363.2, duration: 0.12, velocity: -9), 357)
        XCTAssertEqual(target(start: 365, end: 365.8, duration: 0.12, velocity: -9), 357)
    }
    func testLongFlickUsesDeceleratedPositionAndSnapsToWeek() {
        XCTAssertEqual(target(start: 364, end: 369, duration: 0.12, velocity: 20, current: 385.6), 385)
        XCTAssertEqual(target(start: 364, end: 359, duration: 0.12, velocity: -20, current: 343.4), 343)
    }
    func testCoarseWheelAndStationaryGestureDoNotJumpAWeek() {
        XCTAssertEqual(target(start: 364, end: 365.1, duration: 0.12, velocity: 9, precise: false), 365)
        XCTAssertEqual(target(start: 364, end: 364.005, duration: 0.12, velocity: 0), 364)
    }
    private func target(start: CGFloat, end: CGFloat, duration: TimeInterval, velocity: CGFloat,
                        precise: Bool = true, current: CGFloat? = nil) -> Int {
        CalendarWeekScrollPolicy.targetDay(release: .init(startRow: start, currentRow: end,
            duration: duration, releaseVelocityInWeeksPerSecond: velocity, usesPreciseDeltas: precise),
            currentDay: current ?? end)
    }
}

@MainActor
final class CalendarWeekScrollWindowTests: XCTestCase {
    func testDateTaskCanKeepDraggingAcrossWeeksAndCancelWithoutSaving() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-WeekDrag-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let probe = WeekViewProbe()
        let task = TodoItem(title: "Cross-week task", dueDate: probe.original.adding(days: 6).date())
        store.upsert(task)
        let cache = CalendarWindowCache()
        let host = NSHostingView(rootView: WeekViewHarness(probe: probe, cache: cache, changeTodo: { store.upsert($0) })
            .environmentObject(store).environmentObject(CalendarTodoSelection()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 754, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { cache.cancel(); window.contentView = nil; window.close() }
        try await settle(host)
        let viewport = try XCTUnwrap(findRouter(host)?.superview as? CalendarWeekNativeViewport)
        let input = try XCTUnwrap(inputs(host).first { input in
            input.regions.contains { if case let .item(id, _, _) = $0.target { return id == task.id }; return false }
                && input.convert(input.bounds, to: viewport).intersects(viewport.bounds)
        })
        let source = try XCTUnwrap(input.regions.first { if case let .item(id, _, _) = $0.target { return id == task.id }; return false }?.frame)
        let edge = CGPoint(x: viewport.bounds.maxX - 10,
            y: input.convert(CGPoint(x: source.midX, y: source.midY), to: viewport).y)
        input.pointerDown(at: CGPoint(x: source.midX, y: source.midY), clickCount: 1)
        input.pointerDragged(to: input.convert(edge, from: viewport))
        // A stationary pointer must advance without another mouse-drag event.
        try await settle(host)
        let targetDay = try XCTUnwrap(viewport.day(at: edge))
        XCTAssertGreaterThan(targetDay, probe.original.adding(days: 6))
        XCTAssertEqual(input.interaction?.drag?.range, targetDay...targetDay)
        XCTAssertEqual(store.item(withID: task.id), task, "Hovering must only preview the move")
        input.pointerUp(at: input.convert(edge, from: viewport))
        XCTAssertEqual(store.item(withID: task.id)?.startDay, targetDay)
        XCTAssertNil(viewport.dragOwner)
        XCTAssertNil(input.interaction?.drag)
        try await settle(host)

        let current = try XCTUnwrap(inputs(host).first { $0.regions.contains {
            if case let .item(id, _, _) = $0.target { return id == task.id }; return false
        } && $0.convert($0.bounds, to: viewport).intersects(viewport.bounds) })
        let frame = try XCTUnwrap(current.regions.first { if case let .item(id, _, _) = $0.target { return id == task.id }; return false }?.frame)
        current.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY), clickCount: 1)
        current.pointerDragged(to: current.convert(edge, from: viewport))
        current.cancelPress()
        try await settle(host)
        current.pointerUp(at: current.convert(edge, from: viewport))
        XCTAssertEqual(store.item(withID: task.id)?.startDay, targetDay)
        XCTAssertNil(viewport.dragOwner)
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    func testHeldMouseButtonRejectsWheelWithoutChangingGestureOrPosition() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let router = CalendarWeekHorizontalScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        router.columnWidth = 100
        router.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 2100, height: 500))
        window.contentView = router
        defer { router.stop(); window.contentView = nil; window.close() }
        let initial = router.contentView.bounds.origin
        let event = wheel(dx: -20, dy: 0, phase: 1, in: window)
        // The wheel events and mouse-button state belong to the same synthetic
        // gesture. Real hardware activity must not alter its test input.
        XCTAssertFalse(router.route(event, pressedMouseButtons: 1))
        XCTAssertEqual(router.contentView.bounds.origin, initial)
        XCTAssertTrue(router.route(event, pressedMouseButtons: 0))
        XCTAssertGreaterThan(router.contentView.bounds.minX, initial.x)
    }

    func testSlowNativeGestureMovesOneDayAndVerticalScrollStaysInItsPane() async throws {
        _ = NSApplication.shared
        let probe = WeekPagerProbe()
        let host = NSHostingView(rootView: WeekPagerHarness(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 700, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        let pager = try XCTUnwrap(scrollViews(host).first { ($0.documentView?.bounds.width ?? 0) > 1400 })
        let router = try XCTUnwrap(findRouter(host))
        XCTAssertTrue(router === pager)
        let initialX = pager.contentView.bounds.minX
        XCTAssertEqual(initialX, 52 * 700, accuracy: 1)
        for sign: CGFloat in [-1, 1] {
            let pane = try XCTUnwrap(scrollViews(host).first {
                $0 !== pager && $0.convert($0.bounds, to: host).contains(CGPoint(x: 350, y: 250))
            })
            for step in 0...20 {
                let event = wheel(dx: step == 0 || step == 20 ? 0 : sign * 5.3, dy: 0,
                                  phase: step == 0 ? 1 : (step == 20 ? 4 : 2), in: window)
                if step == 20 { XCTAssertEqual(event.phase, .ended) }
                let handled = router.route(event, pressedMouseButtons: 0)
                if step > 0 { XCTAssertTrue(handled, "Window \(event.windowNumber) vs \(window.windowNumber), phase \(event.phase)") }
                if !handled { pane.scrollWheel(with: event) }
                try await Task.sleep(for: .milliseconds(30))
            }
            try await settle(host)
            XCTAssertEqual(pager.contentView.bounds.minX, initialX + (sign < 0 ? 100 : 0), accuracy: 1)
            XCTAssertEqual(probe.firstDay, probe.original.adding(days: sign < 0 ? 1 : 0))
        }
        let pane = try XCTUnwrap(scrollViews(host).first {
            $0 !== pager && $0.convert($0.bounds, to: host).contains(CGPoint(x: 350, y: 250))
        })
        for step in 0...10 {
            let event = wheel(dx: 0, dy: step == 0 || step == 10 ? 0 : -25,
                              phase: step == 0 ? 1 : (step == 10 ? 4 : 2), in: window)
            XCTAssertFalse(router.route(event, pressedMouseButtons: 0))
            pane.scrollWheel(with: event)
            try await Task.sleep(for: .milliseconds(12))
        }
        try await settle(host)
        XCTAssertGreaterThan(pane.contentView.bounds.minY, 100)
        XCTAssertEqual(pager.contentView.bounds.minX, initialX, accuracy: 1)
        probe.firstDay = probe.original.adding(days: 701)
        try await settle(host)
        XCTAssertEqual(pager.contentView.bounds.minX, initialX + 100, accuracy: 1,
                       "Rebasing retains the day within the week")
        window.setContentSize(NSSize(width: 840, height: 500))
        try await settle(host)
        XCTAssertEqual(pager.contentView.bounds.minX, 52 * 840 + 120, accuracy: 1)
    }

    func testRealWeekKeepsAxisFixedAndSynchronizesAdjacentTimelines() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-WeekColumns-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let probe = WeekViewProbe()
        let day = probe.original.adding(days: 1)
        let task = TodoItem(title: "Tuesday marker", dueDate: day.date())
        store.upsert(task)
        for number in 0..<38 {
            store.upsert(TodoItem(title: "Same week task \(number)", dueDate: day.date()))
        }
        store.upsertSchedule(DaySchedule(startDay: day, startMinute: 540, durationMinutes: 45,
            content: .todo(task.id)))
        let cache = CalendarWindowCache()
        let host = NSHostingView(rootView: WeekViewHarness(probe: probe, cache: cache)
            .environmentObject(store).environmentObject(CalendarTodoSelection()))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 754, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { cache.cancel(); window.contentView = nil; window.close() }
        try await settle(host)
        let pager = try XCTUnwrap(scrollViews(host).first { ($0.documentView?.bounds.width ?? 0) > 1400 })
        let router = try XCTUnwrap(findRouter(host))
        let axis = try XCTUnwrap(scrollViews(host).first { abs($0.bounds.width - 54) < 1 })
        let axisFrame = axis.convert(axis.bounds, to: host)
        XCTAssertEqual(pager.bounds.width, 754, accuracy: 1)
        XCTAssertEqual(pager.convert(pager.bounds, to: host).minX, 0, accuracy: 1)
        XCTAssertEqual(pager.contentInsets.left, 54, accuracy: 1)
        let taskInput = try XCTUnwrap(inputs(host).first { input in
            input.regions.contains { if case let .item(id, _, _) = $0.target { return id == task.id }; return false }
        })
        let taskRegion = try XCTUnwrap(taskInput.regions.first { if case let .item(id, _, _) = $0.target { return id == task.id }; return false })
        let taskX = taskInput.convert(CGPoint(x: taskRegion.frame.midX, y: taskRegion.frame.midY), to: host).x
        XCTAssertEqual(taskX, 204, accuracy: 1)
        XCTAssertTrue(router === pager)
        pager.contentView.scroll(to: CGPoint(x: 52 * 700 - 54 + 95, y: 0))
        pager.reflectScrolledClipView(pager.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: pager)
        try await settle(host)
        XCTAssertEqual(LocalDay(probe.selectedDate), probe.original, "Horizontal scrolling must not change the selected date")
        XCTAssertEqual(pager.contentView.bounds.minX, 52 * 700 - 54 + 100, accuracy: 1)
        XCTAssertEqual(axis.convert(axis.bounds, to: host), axisFrame)
        XCTAssertEqual(taskInput.convert(CGPoint(x: taskRegion.frame.midX, y: taskRegion.frame.midY), to: host).x,
            taskX - 100, accuracy: 1, "Task bars move by exactly the same day column as the header")
        let timelines = scrollViews(host).filter { $0 !== pager && $0 !== axis
            && ($0.documentView?.bounds.height ?? 0) > 2000 }
        XCTAssertGreaterThanOrEqual(timelines.count, 2)
        let dateViewport = CGRect(x: 54, y: 0, width: 700, height: host.bounds.height)
        let pane = try XCTUnwrap(timelines.first {
            $0.convert($0.bounds, to: host).intersection(dateViewport).width > 1
        })
        pane.contentView.scroll(to: CGPoint(x: 0, y: 810))
        pane.reflectScrolledClipView(pane.contentView)
        try await settle(host)
        XCTAssertEqual(probe.minute ?? 0, 540, accuracy: 1)
        XCTAssertEqual(axis.contentView.bounds.minY, 810, accuracy: 1)
        for timeline in scrollViews(host).filter({ $0 !== axis && $0 !== pager && ($0.documentView?.bounds.height ?? 0) > 2000 && $0.convert($0.bounds, to: host).intersection(dateViewport).width > 1 }) { XCTAssertEqual(timeline.contentView.bounds.minY, 810, accuracy: 1) }
        XCTAssertEqual(axis.convert(axis.bounds, to: host), axisFrame)
        let todoPanes = scrollViews(host).filter { $0 !== pager && $0 !== axis
            && ($0.documentView?.bounds.height ?? 0) < 2000 }
        let todoPane = try XCTUnwrap(todoPanes.first {
            $0.convert($0.bounds, to: host).intersection(dateViewport).width > 1
        })
        todoPane.contentView.scroll(to: CGPoint(x: 0, y: 100))
        todoPane.reflectScrolledClipView(todoPane.contentView)
        try await settle(host)
        XCTAssertEqual(todoPane.contentView.bounds.minY, 100, accuracy: 1,
                       "Synchronizing panes must not feed the fixed header inset back into the scroll offset")
        for pane in scrollViews(host).filter({ $0 !== axis && $0 !== pager && ($0.documentView?.bounds.height ?? 0) < 2000 && $0.convert($0.bounds, to: host).intersection(dateViewport).width > 1 }) {
            XCTAssertEqual(pane.contentView.bounds.minY, todoPane.contentView.bounds.minY, accuracy: 1,
                "Empty and populated adjacent weeks share a vertical task viewport")
        }
        probe.navigationDate = day.adding(days: 7).date()
        probe.navigationID = UUID()
        try await settle(host)
        XCTAssertEqual(LocalDay(probe.selectedDate), probe.original, "Week browsing also leaves the selected date unchanged")
        XCTAssertEqual(pager.contentView.bounds.minX, 53 * 700 - 54 + 100, accuracy: 1,
                       "The next-week button preserves a day-aligned visible range")
        XCTAssertEqual(axis.convert(axis.bounds, to: host), axisFrame)
        XCTAssertEqual(axis.contentView.bounds.minY, 810, accuracy: 1)
        probe.navigationDate = probe.original.date()
        probe.navigationID = UUID()
        try await settle(host)
        XCTAssertEqual(pager.contentView.bounds.minX, 52 * 700 - 54, accuracy: 1,
            "Returning to an unchanged selection must still reset the visible range")
        XCTAssertEqual(LocalDay(probe.selectedDate), probe.original)
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    func testFastFlicksUseWeekBoundariesAfterSimulatedMomentum() async throws {
        _ = NSApplication.shared
        let probe = WeekPagerProbe()
        let host = NSHostingView(rootView: WeekPagerHarness(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 700, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        let pager = try XCTUnwrap(scrollViews(host).first { ($0.documentView?.bounds.width ?? 0) > 1400 })
        let router = try XCTUnwrap(findRouter(host))
        for step in 0...12 {
            _ = router.route(wheel(dx: step == 0 || step == 12 ? 0 : -8, dy: 0,
                phase: step == 0 ? 1 : (step == 12 ? 4 : 2), in: window), pressedMouseButtons: 0)
            try await Task.sleep(for: .milliseconds(8))
        }
        try await settle(host)
        XCTAssertEqual(probe.firstDay, probe.original.adding(days: 7))
        XCTAssertEqual(pager.contentView.bounds.minX, 53 * 700, accuracy: 1)
        for step in 0...12 {
            _ = router.route(wheel(dx: step == 0 || step == 12 ? 0 : -50, dy: 0,
                phase: step == 0 ? 1 : (step == 12 ? 4 : 2), in: window), pressedMouseButtons: 0)
            try await Task.sleep(for: .milliseconds(8))
        }
        let releasedX = pager.contentView.bounds.minX
        // OS-generated inertia is not reproduced by a CGEvent wrapper. Move
        // the actual clip view through its momentum destination while feeding
        // phases, verifying that settling waits for the final momentum event.
        for step in 0...30 {
            let event = wheel(dx: step == 30 ? 0 : -30, dy: 0, phase: 0,
                momentum: step == 0 ? 1 : (step == 30 ? 3 : 2), in: window)
            if step == 30 { XCTAssertEqual(event.momentumPhase, .ended) }
            XCTAssertTrue(router.route(event, pressedMouseButtons: 0))
            if step < 30 {
                pager.contentView.scroll(to: CGPoint(x: releasedX + CGFloat(step + 1) * 30, y: 0))
                pager.reflectScrolledClipView(pager.contentView)
                XCTAssertEqual(probe.firstDay, probe.original.adding(days: 7))
            }
            try await Task.sleep(for: .milliseconds(15))
        }
        try await settle(host)
        XCTAssertGreaterThan(pager.contentView.bounds.minX, 54 * 700)
        XCTAssertEqual(pager.contentView.bounds.minX / 700,
            (pager.contentView.bounds.minX / 700).rounded(), accuracy: 0.01)
        XCTAssertEqual(probe.original.distance(to: probe.firstDay) % 7, 0)
    }

    func testScrollOnlyRefreshReusesHostedWeeksAndContentChangesStillUpdateThem() {
        _ = NSApplication.shared
        let day = LocalDay(year: 2026, month: 10, day: 19)
        var builds = 0
        var input = CalendarWeekDateViewport(week: day, firstDay: day,
            contentVersion: 1, settledAtDay: { _ in }) { _ in
                builds += 1
                return Color.clear
            }
        let coordinator = input.makeCoordinator()
        let view = CalendarWeekNativeViewport(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        coordinator.attach(view)
        coordinator.update(input, environment: EnvironmentValues())
        view.layoutSubtreeIfNeeded()
        defer { coordinator.stop(); window.contentView = nil; window.close() }
        let initial = builds
        XCTAssertGreaterThan(initial, 0)
        for _ in 0..<20 { coordinator.update(input, environment: EnvironmentValues()) }
        XCTAssertEqual(builds, initial, "A scroll binding update must not replace all week roots")
        input.contentVersion = 2
        coordinator.update(input, environment: EnvironmentValues())
        XCTAssertGreaterThan(builds, initial)
        let changed = builds
        var disabled = EnvironmentValues()
        disabled.isEnabled = false
        coordinator.update(input, environment: disabled)
        XCTAssertGreaterThan(builds, changed, "Native hosts must still receive changed environment values")
    }

    func testParentRefreshCannotUndoPendingProgrammaticWeekNavigation() async throws {
        _ = NSApplication.shared
        let day = LocalDay(year: 2026, month: 10, day: 12)
        let destination = day.adding(days: 14)
        var reported: LocalDay?
        var input = CalendarWeekDateViewport(week: day, firstDay: day,
            settledAtDay: { reported = $0 }) { _ in Color.clear }
        let coordinator = input.makeCoordinator()
        let view = CalendarWeekNativeViewport(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        coordinator.attach(view)
        coordinator.update(input, environment: EnvironmentValues())
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()
        defer { coordinator.stop(); window.contentView = nil; window.close() }
        input.navigationID = UUID(); input.navigationDay = destination
        coordinator.update(input, environment: EnvironmentValues())
        XCTAssertEqual(view.scroll.contentView.bounds.minX, 54 * 700, accuracy: 1)
        // A toolbar/geometry refresh arrives before the deferred range binding
        // publication. Its unchanged firstDay is stale input, not a new command.
        coordinator.update(input, environment: EnvironmentValues())
        coordinator.update(input, environment: EnvironmentValues())
        XCTAssertEqual(view.scroll.contentView.bounds.minX, 54 * 700, accuracy: 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reported, destination)
        XCTAssertEqual(view.scroll.contentView.bounds.minX, 54 * 700, accuracy: 1)
    }

    func testReleaseStartsSnapImmediatelyAndConsumesResidualMomentum() async throws {
        let (host, window, pager) = try await fixture()
        defer { window.contentView = nil; window.close() }
        let time = ProcessInfo.processInfo.systemUptime
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 1, at: time, in: window))
        _ = pager.route(wheel(dx: -88, dy: 0, phase: 2, at: time + 0.1, in: window))
        let released = pager.contentView.bounds.minX
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 4, at: time + 0.12, in: window))
        XCTAssertEqual(pager.motion, .snapping, "No debounce follows a short flick")
        _ = pager.route(wheel(dx: -100, dy: 0, phase: 0, momentum: 1, at: time + 0.13, in: window))
        XCTAssertEqual(pager.contentView.bounds.minX, released, accuracy: 0.01)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertGreaterThan(pager.contentView.bounds.minX, released, "The next display frame advances the snap")
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 4, at: time + 0.14, in: window))
        XCTAssertEqual(pager.motion, .snapping, "A duplicate release cannot restart the gesture")
        try await settle(host)
        XCTAssertEqual(pager.contentView.bounds.minX, 53 * 700, accuracy: 1)

        let slow = time + 1
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 1, at: slow, in: window))
        _ = pager.route(wheel(dx: -88, dy: 0, phase: 2, at: slow + 0.5, in: window))
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 4, at: slow + 0.8, in: window))
        XCTAssertEqual(pager.motion, .snapping, "Slow release also starts immediately")
        try await settle(host)
        XCTAssertEqual(pager.contentView.bounds.minX, 53 * 700 + 100, accuracy: 1)
    }

    func testLongFlickWaitsOnlyForMomentumAndNewContactInterruptsSnap() async throws {
        let (host, window, pager) = try await fixture()
        defer { window.contentView = nil; window.close() }
        let time = ProcessInfo.processInfo.systemUptime
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 1, at: time, in: window))
        for index in 1...6 {
            _ = pager.route(wheel(dx: -50, dy: 0, phase: 2, at: time + Double(index) * 0.01, in: window))
        }
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 4, at: time + 0.08, in: window))
        XCTAssertEqual(pager.motion, .waitingForMomentum)
        _ = pager.route(wheel(dx: -20, dy: 0, phase: 0, momentum: 1, at: time + 0.09, in: window))
        XCTAssertEqual(pager.motion, .momentum)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(pager.motion, .momentum, "The missing-momentum fallback cannot pull back active inertia")
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 0, momentum: 3, at: time + 0.2, in: window))
        XCTAssertEqual(pager.motion, .snapping)
        try await Task.sleep(for: .milliseconds(25))
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 1, at: time + 0.3, in: window))
        let interrupted = pager.contentView.bounds.minX
        XCTAssertEqual(pager.motion, .idle)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(pager.contentView.bounds.minX, interrupted, accuracy: 0.01)

        // A long flick for which the OS supplies no inertia starts its snap in 32 ms.
        _ = pager.route(wheel(dx: -300, dy: 0, phase: 2, at: time + 0.35, in: window))
        _ = pager.route(wheel(dx: 0, dy: 0, phase: 4, at: time + 0.4, in: window))
        XCTAssertEqual(pager.motion, .waitingForMomentum)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(pager.motion, .snapping)
        pager.resetGesture()
        let reset = pager.contentView.bounds.minX
        try await settle(host)
        XCTAssertEqual(pager.contentView.bounds.minX, reset, accuracy: 0.01)
    }

    func testCoveredWeeksStayMountedUnderNativeMaterialWithBoundedHosting() async throws {
        let (host, window, pager) = try await fixture(inset: 54)
        defer { window.contentView = nil; window.close() }
        let viewport = try XCTUnwrap(pager.superview as? CalendarWeekNativeViewport)
        XCTAssertEqual(viewport.backdrop.material, .headerView)
        XCTAssertEqual(viewport.backdrop.blendingMode, .withinWindow)
        XCTAssertTrue(viewport.backdrop.superview === pager.superview)
        for column in [1, 6, 7, 20, -1, -15] {
            let x: CGFloat = 33538 + CGFloat(column) * (646.0 / 7.0)
            pager.contentView.scroll(to: CGPoint(x: x, y: 0))
            pager.reflectScrolledClipView(pager.contentView)
            host.layoutSubtreeIfNeeded()
            let mounted = viewport.document.subviews
            XCTAssertLessThanOrEqual(mounted.count, 5, "Scrolling cannot accumulate hidden weeks")
            let covered = CGRect(x: pager.contentView.bounds.minX, y: 0, width: 54, height: 500)
            XCTAssertTrue(mounted.contains { $0.frame.intersects(covered) }, "The content behind the entire axis remains drawn")
        }
        try await settle(host)
    }

    private func fixture(inset: CGFloat = 0) async throws -> (NSView, NSWindow, CalendarWeekHorizontalScrollView) {
        _ = NSApplication.shared
        let probe = WeekPagerProbe()
        let host = NSHostingView(rootView: WeekPagerHarness(probe: probe, inset: inset))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 700, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await settle(host)
        return (host, window, try XCTUnwrap(findRouter(host)))
    }

    private func inputs(_ view: NSView) -> [CalendarDateInput.InputView] {
        ((view as? CalendarDateInput.InputView).map { [$0] } ?? []) + view.subviews.flatMap(inputs)
    }

    private func wheel(dx: CGFloat, dy: CGFloat, phase: Int64, momentum: Int64 = 0,
                       point: CGPoint = CGPoint(x: 350, y: 250), at timestamp: TimeInterval? = nil, in window: NSWindow) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)!
        event.timestamp = UInt64((timestamp ?? ProcessInfo.processInfo.systemUptime) * 1_000_000_000)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        let screenPoint = window.convertPoint(toScreen: point)
        event.location = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ProcessInfo.processInfo.processIdentifier))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        let bound = WindowWheelEvent()
        bound.base = NSEvent(cgEvent: event)!
        bound.eventWindow = window
        bound.eventWindowNumber = window.windowNumber
        bound.windowPoint = point
        return bound
    }

    private func findRouter(_ view: NSView) -> CalendarWeekHorizontalScrollView? {
        (view as? CalendarWeekHorizontalScrollView) ?? view.subviews.lazy.compactMap(findRouter).first
    }
    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }
    private func settle(_ view: NSView) async throws {
        for _ in 0..<40 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class WeekPagerProbe: ObservableObject {
    let original = LocalDay(year: 2026, month: 10, day: 12)
    @Published var firstDay = LocalDay(year: 2026, month: 10, day: 12)
}
private struct WeekPagerHarness: View {
    @ObservedObject var probe: WeekPagerProbe
    var inset: CGFloat = 0
    var body: some View {
        CalendarWeekDateViewport(week: probe.original, firstDay: probe.firstDay, leadingInset: inset, settledAtDay: { probe.firstDay = $0 }) { day in
            ScrollView(.vertical) {
                Text(verbatim: String(describing: day)).frame(maxWidth: .infinity).frame(height: 2000)
            }
        }
    }
}

// CGEvent-backed NSEvents created in a test have no window association.
// Preserve their native deltas/phases, supplying only the missing routing metadata.
private final class WindowWheelEvent: NSEvent {
    var base: NSEvent!
    weak var eventWindow: NSWindow?
    var eventWindowNumber = 0
    var windowPoint = CGPoint.zero
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

@MainActor
private final class WeekViewProbe: ObservableObject {
    let original = LocalDay(year: 2026, month: 10, day: 12)
    @Published var selectedDate = LocalDay(year: 2026, month: 10, day: 12).date()
    let position = CalendarWeekViewportPosition(scrollMinute: 480)
    var height: CGFloat {
        get { position.hourHeight }
        set { position.hourHeight = newValue }
    }
    var minute: CGFloat? {
        get { position.scrollMinute }
        set { position.scrollMinute = newValue }
    }
    @Published var visibleDay: LocalDay?
    @Published var navigationID: UUID?
    @Published var navigationDate: Date?
}
private struct WeekViewHarness: View {
    @ObservedObject var probe: WeekViewProbe
    let cache: CalendarWindowCache
    var changeTodo: (TodoItem) -> Void = { _ in }
    private let presentation = CalendarWeekPresentationCache()
    var body: some View {
        CalendarWeekView(calendar: AppCalendar.make(locale: L10n.locale, startsOnMonday: true),
            visibility: .init(showCompleted: true), selectedDate: $probe.selectedDate,
            position: probe.position,
            windowCache: cache, presentationCache: presentation,
            navigationID: probe.navigationID, navigationDate: probe.navigationDate,
            visibleRangeChanged: { if probe.visibleDay != $0 { probe.visibleDay = $0 } }, createTodo: { _, _ in },
            changeTodo: changeTodo, editTodo: { _ in }, showMore: { _ in })
    }
}
