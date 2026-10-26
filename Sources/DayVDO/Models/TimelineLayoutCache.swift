import Foundation

/// Geometry depends on arrangements, day and active column priority, never on
/// scrolling, selection, clock ticks, theme or zoom scale.
@MainActor
final class TimelineLayoutCache: ObservableObject {
    struct Value {
        var schedulesByID: [UUID: DaySchedule]
        var placements: [DayPlanningPolicy.Placement]
    }
    private var day: LocalDay?
    private var schedules: [DaySchedule] = []
    private var activeID: UUID?
    private var cached: Value?
    private(set) var buildCount = 0

    func value(day: LocalDay, schedules: [DaySchedule], prioritizing activeID: UUID?) -> Value {
        if self.day == day, self.schedules == schedules, self.activeID == activeID, let cached { return cached }
        let value = Value(schedulesByID: Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) }),
            placements: DayPlanningPolicy.placements(schedules, on: day, prioritizing: activeID))
        self.day = day; self.schedules = schedules; self.activeID = activeID; cached = value
        buildCount += 1
        return value
    }
}
