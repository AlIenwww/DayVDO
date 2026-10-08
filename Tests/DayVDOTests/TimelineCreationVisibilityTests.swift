import XCTest
@testable import DayVDO

@MainActor
final class TimelineCreationVisibilityTests: XCTestCase {
    private let monday = LocalDay(year: 2026, month: 10, day: 5)

    func testCompletedAndOtherDayArrangementsDoNotAttractHiddenWeekCreationEdge() {
        let completed = TodoItem(title: "Completed", isCompleted: true)
        let hidden = DaySchedule(startDay: monday, startMinute: 541, durationMinutes: 60,
                                 content: .todo(completed.id))
        let tomorrow = DaySchedule(startDay: monday.adding(days: 1), startMinute: 602, durationMinutes: 60,
                                   content: .independent(title: "Tomorrow", notes: ""))
        let cache = CalendarWeekPresentationCache()
        let schedules = [hidden, tomorrow]
        let hiddenWeek = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: false)),
            schedules: schedules, preview: nil, todo: { $0 == completed.id ? completed : nil })
        let hiddenBoundaries = TimelineCreationPolicy.boundaries(
            in: (hiddenWeek.placementsByDay[monday] ?? []).map(\.interval))
        XCTAssertEqual(TimelineCreationPolicy.startMinute(
            at: 603, boundaries: hiddenBoundaries, pointsPerMinute: 1.5), 605)

        let shownWeek = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: true)),
            schedules: schedules, preview: nil, todo: { $0 == completed.id ? completed : nil })
        let shownBoundaries = TimelineCreationPolicy.boundaries(
            in: (shownWeek.placementsByDay[monday] ?? []).map(\.interval))
        XCTAssertEqual(TimelineCreationPolicy.startMinute(
            at: 603, boundaries: shownBoundaries, pointsPerMinute: 1.5), 601,
            "Only the arrangement in the originating day can attract the pointer")
    }

    func testChangingProjectFilterChangesMagnetToTheNearestVisibleArrangement() {
        let projectA = UUID(), projectB = UUID()
        let matching = TodoItem(title: "Matching", projectID: projectA)
        let hidden = TodoItem(title: "Hidden", projectID: projectB)
        let schedules = [
            DaySchedule(startDay: monday, startMinute: 541, durationMinutes: 60, content: .todo(matching.id)),
            DaySchedule(startDay: monday, startMinute: 542, durationMinutes: 60, content: .todo(hidden.id))
        ]
        let cache = CalendarWeekPresentationCache()
        var filter = TodoFilterState()
        filter.projectIDs = [projectA]
        let filtered = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(filter: filter, showCompleted: true)),
            schedules: schedules, preview: nil, todo: { id in [matching, hidden].first { $0.id == id } })
        let filteredBoundaries = TimelineCreationPolicy.boundaries(
            in: (filtered.placementsByDay[monday] ?? []).map(\.interval))
        XCTAssertEqual(TimelineCreationPolicy.startMinute(
            at: 603, boundaries: filteredBoundaries, pointsPerMinute: 1.5), 601)

        let cleared = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: true)),
            schedules: schedules, preview: nil, todo: { id in [matching, hidden].first { $0.id == id } })
        let clearedBoundaries = TimelineCreationPolicy.boundaries(
            in: (cleared.placementsByDay[monday] ?? []).map(\.interval))
        XCTAssertEqual(TimelineCreationPolicy.startMinute(
            at: 603, boundaries: clearedBoundaries, pointsPerMinute: 1.5), 602)
    }

    func testCrossMidnightMagnetsUseTheDisplayedDayEdges() {
        let carried = DaySchedule(startDay: monday.adding(days: -1), startMinute: 1387, durationMinutes: 60,
                                  content: .independent(title: "Carried", notes: ""))
        let continuing = DaySchedule(startDay: monday, startMinute: 1413, durationMinutes: 60,
                                     content: .independent(title: "Continuing", notes: ""))
        let tomorrow = DaySchedule(startDay: monday.adding(days: 1), startMinute: 20, durationMinutes: 30,
                                   content: .independent(title: "Tomorrow", notes: ""))
        let cache = CalendarWeekPresentationCache()
        let week = cache.value(
            for: .init(week: monday, revision: 1, visibility: .init(showCompleted: true)),
            schedules: [carried, continuing, tomorrow], preview: nil, todo: { _ in nil })
        let boundaries = TimelineCreationPolicy.boundaries(
            in: (week.placementsByDay[monday] ?? []).map(\.interval))

        XCTAssertEqual(boundaries, [0, 7, 1413, 1440])
        XCTAssertEqual(TimelineCreationPolicy.startMinute(
            at: 6, boundaries: boundaries, pointsPerMinute: 1.5), 7)
        XCTAssertEqual(TimelineCreationPolicy.range(
            from: 1411, anchoredAt: 1413, to: 1440,
            boundaries: boundaries, pointsPerMinute: 1.5), 1413..<1440)
    }
}
