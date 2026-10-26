import AppKit
import Darwin
import os
import SwiftUI
import XCTest
@testable import DayVDO

/// An opt-in native-window workload. Intervals include the action and four
/// layout/display turns; they are not hardware input-to-photon latency.
@MainActor
final class ExperienceWorkloadTests: XCTestCase {
    private let log = OSLog(subsystem: "DayVDO.Experience", category: .pointsOfInterest)

    func testNativePageAndInteractionWorkloads() async throws {
        guard ProcessInfo.processInfo.environment["DAYVDO_EXPERIENCE_WORKLOAD"] == "1" else {
            throw XCTSkip("Enable DAYVDO_EXPERIENCE_WORKLOAD for native Release comparisons")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let rounds = Int(ProcessInfo.processInfo.environment["DAYVDO_EXPERIENCE_ROUNDS"] ?? "5") ?? 5
        for count in [100, 1000] {
            for round in 0..<rounds { try await run(count: count, round: round) }
        }
    }

    private func run(count: Int, round: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-Experience-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "DayVDO-Experience-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let day = LocalDay(year: 2026, month: 10, day: 19)
        let project = TodoProject(title: "Project", createdAt: .distantFuture, usesManualTaskOrder: true)
        let children = count / 5
        let items = (0..<count).map { index -> TodoItem in
            let start = day.adding(days: index % 14)
            return TodoItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                title: "Task \(index)", startDate: start.date(), dueDate: start.adding(days: index % 3).date(),
                projectID: index < children ? project.id : nil)
        }
        let schedules = items.enumerated().map { index, item in
            DaySchedule(startDay: item.startDay!, startMinute: 480 + (index % 16) * 30,
                durationMinutes: 45, content: .todo(item.id))
        }
        let file = directory.appendingPathComponent("todos.json")
        try JSONEncoder().encode(TodoSnapshot(items: items, projects: [project], tags: [],
            settings: AppSettings(), schedules: schedules)).write(to: file)
        let store = TodoStore(fileURL: file)
        let state = ExperienceState(day: day, defaults: defaults)
        let host = NSHostingView(rootView: ExperienceHarness(state: state).environmentObject(store)
            .environmentObject(CalendarTodoSelection()).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: CGRect(x: 60, y: 60, width: 1080, height: 720),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        state.presentation.feedback.window = window
        defer { state.cache.cancel(); state.presentation.cancelPendingPresentation(); window.contentView = nil; window.close() }
        await settle(host)
        func enter(_ page: SidebarDestination) {
            state.presentation.selection = page
            state.presentation.presentSelection {
                let key = CalendarWindowSnapshot.Key(revision: store.dateContentRevision,
                    firstDay: day.adding(days: -21), lastDay: day.adding(days: 27),
                    timeZoneIdentifier: TimeZone.current.identifier, firstWeekday: 2,
                    visibility: .init(showCompleted: true))
                state.cache.prepare(.init(key: key, items: store.items, tags: store.tags), priority: .userInitiated)
                return .init(cache: state.cache, key: key)
            }
        }
        var samples: [String: [Double]] = [:]
        var cpu: [String: [Double]] = [:]
        var resources: [String: [[String: UInt64]]] = [:]
        func record(_ name: String, _ action: () -> Void, waitFor page: SidebarDestination? = nil) async throws {
            let start = ContinuousClock.now
            let cpuStart = cpuMilliseconds()
            let resourceStart = resourceUsage()
            os_signpost(.begin, log: log, name: "Operation", "%{public}s", name)
            action()
            if let page {
                let deadline = ContinuousClock.now + .seconds(5)
                while state.presentation.displayedDestination != page && .now < deadline {
                    window.update(); await Task.yield()
                    try await Task.sleep(for: .milliseconds(1))
                }
                XCTAssertEqual(state.presentation.displayedDestination, page)
            }
            await settle(host)
            os_signpost(.end, log: log, name: "Operation", "%{public}s", name)
            samples[name, default: []].append(milliseconds(start.duration(to: .now)))
            cpu[name, default: []].append(cpuMilliseconds() - cpuStart)
            resources[name, default: []].append(resourceDelta(from: resourceStart))
        }
        try await record("today_entry", { enter(.today) }, waitFor: .today)
        let idleStart = resourceUsage()
        let idleCPU = cpuMilliseconds()
        try await Task.sleep(for: .seconds(2))
        resources["today_idle_2s"] = [resourceDelta(from: idleStart)]
        cpu["today_idle_2s"] = [cpuMilliseconds() - idleCPU]
        let todayScroll = try XCTUnwrap(scrollViews(host).first { ($0.documentView?.bounds.height ?? 0) > 2000 })
        for step in 0..<20 {
            try await record("today_scroll", {
                todayScroll.contentView.scroll(to: CGPoint(x: 0, y: 550 + step * 9))
                todayScroll.reflectScrolledClipView(todayScroll.contentView)
            })
        }
        for step in 0..<12 { try await record("today_zoom_update", { state.hourHeight = 90 + CGFloat(step * 3) }) }
        try await record("calendar_cold_entry", { enter(.calendar) }, waitFor: .calendar)
        for step in 0..<20 {
            var preview = schedules[0]; preview.startMinute += step * 5
            try await record("week_drag_preview", { state.weekPresentation.dragPreview = preview })
        }
        state.weekPresentation.dragPreview = nil
        try await record("today_return", { enter(.today) }, waitFor: .today)
        try await record("calendar_cached_entry", { enter(.calendar) }, waitFor: .calendar)
        try await record("all_entry", { enter(.all) }, waitFor: .all)
        try await record("project_expand", {
            let point = host.convert(CGPoint(x: 40, y: host.isFlipped ? 35 : host.bounds.height - 35), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
                NSApp.sendEvent(event)
            }
        })
        XCTAssertTrue(state.expansion.isExpanded(project.id), "The workload must actually expand the project")
        try await Task.sleep(for: .milliseconds(200))
        await settle(host)
        for step in 0..<10 {
            let scroll = try XCTUnwrap(scrollViews(host).first)
            try await record("project_scroll", {
                scroll.contentView.scroll(to: CGPoint(x: 0, y: step * 20))
                scroll.reflectScrolledClipView(scroll.contentView)
            })
        }
        for query in ["T", "Ta", "Task", "Task 1", ""] {
            try await record("search_update", { state.query = query })
        }
        for index in 1...5 {
            try await record("project_reorder_commit", { _ = store.moveProjectItem(items[index].id, before: items[0].id, in: project.id) })
        }
        let saved = await store.flushPersistence(); XCTAssertTrue(saved)
        let report: [String: Any] = ["items": count, "children": children, "round": round,
            "samples_ms": samples, "cpu_ms": cpu, "resources": resources, "process_peak_rss_bytes": peakRSS(),
            "screen_max_fps": window.screen?.maximumFramesPerSecond ?? 0]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        FileHandle.standardError.write(Data("EXPERIENCE_WORKLOAD ".utf8) + data + Data("\n".utf8))
    }
    private func settle(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded(); host.window?.displayIfNeeded(); host.window?.update()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
    private func milliseconds(_ value: Duration) -> Double { Double(value.components.seconds) * 1000 + Double(value.components.attoseconds) / 1e15 }
    private func cpuMilliseconds() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
    }
    private func resourceUsage() -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? usage : nil
    }
    private func resourceDelta(from start: rusage_info_v4?) -> [String: UInt64] {
        guard let start, let end = resourceUsage() else { return [:] }
        return ["interrupt_wakeups": end.ri_interrupt_wkups - start.ri_interrupt_wkups,
            "package_idle_wakeups": end.ri_pkg_idle_wkups - start.ri_pkg_idle_wkups,
            "disk_read_bytes": end.ri_diskio_bytesread - start.ri_diskio_bytesread,
            "disk_write_bytes": end.ri_diskio_byteswritten - start.ri_diskio_byteswritten,
            "footprint_bytes": end.ri_phys_footprint]
    }
    private func peakRSS() -> Int64 { var usage = rusage(); getrusage(RUSAGE_SELF, &usage); return Int64(usage.ru_maxrss) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func scrollViews(_ view: NSView) -> [NSScrollView] { descendants(view).compactMap { $0 as? NSScrollView } }
}

@MainActor
private final class ExperienceState: ObservableObject {
    let day: LocalDay
    let presentation = SidebarPagePresentation()
    let cache = CalendarWindowCache()
    let weekPresentation = CalendarWeekPresentationCache()
    let weekPosition = CalendarWeekViewportPosition(scrollMinute: 480)
    let expansion: ProjectExpansionState
    let allCache = AllTodosView.PresentationCache()
    @Published var selectedDay: LocalDay
    @Published var selectedDate: Date
    @Published var hourHeight: CGFloat = 90
    @Published var scrollMinute: CGFloat? = 480
    @Published var query = ""
    @Published var filter = TodoFilterState()
    @Published var allScroll = ScrollPosition()
    init(day: LocalDay, defaults: UserDefaults) {
        self.day = day; selectedDay = day; selectedDate = day.date()
        expansion = ProjectExpansionState(defaults: defaults)
        presentation.selection = .settings
        presentation.presentSelection { nil }
    }
}

private struct ExperienceHarness: View {
    @ObservedObject var state: ExperienceState
    @EnvironmentObject var store: TodoStore
    var body: some View {
        Group {
            switch state.presentation.displayedDestination {
            case .today:
                TodayView(editingItem: .constant(nil), selectedDay: $state.selectedDay,
                    hourHeight: $state.hourHeight, timelineScrollMinute: $state.scrollMinute)
            case .calendar:
                CalendarWeekView(calendar: AppCalendar.make(locale: L10n.locale, startsOnMonday: true),
                    visibility: .init(showCompleted: true), selectedDate: $state.selectedDate,
                    position: state.weekPosition, windowCache: state.cache, presentationCache: state.weekPresentation,
                    createTodo: { _, _ in }, changeTodo: { store.upsert($0) }, editTodo: { _ in }, showMore: { _ in })
            case .all:
                AllTodosView(editingItem: .constant(nil), editingProject: .constant(nil), searchFocusRequest: 0,
                    query: $state.query, filter: $state.filter, scrollPosition: $state.allScroll,
                    expansionState: state.expansion, presentationCache: state.allCache)
            case .settings: Color.clear
            }
        }
    }
}
