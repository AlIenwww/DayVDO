import Foundation

@MainActor
final class CalendarWeekPresentationCache: ObservableObject {
    @Published var dragPreview: DaySchedule?
    struct Key: Equatable {
        var week: LocalDay
        var revision: UInt64
        var visibility: TodoFilterContext
    }
    struct Snapshot: Equatable {
        var schedulesByID: [UUID: DaySchedule]
        var placementsByDay: [LocalDay: [DayPlanningPolicy.Placement]]
    }
    private struct PreviewKey: Equatable {
        var schedule: DaySchedule?
        var activeID: UUID?
    }
    private struct Entry {
        var key: Key
        var days: [LocalDay]
        var schedulesByDay: [LocalDay: [DaySchedule]]
        var base: Snapshot
        var previewKey: PreviewKey?
        var preview: Snapshot?
    }
    private var entries: [LocalDay: Entry] = [:]
    private(set) var layoutBuildCount = 0

    /// Kept for callers with a standalone snapshot (including regression tests).
    func value(for key: Key, schedules: [DaySchedule], preview: DaySchedule?,
               prioritizing activeID: UUID? = nil, todo: (UUID) -> TodoItem?) -> Snapshot {
        value(for: key, schedulesOnDay: { day in schedules.filter { $0.interval(on: day) != nil } },
              preview: preview, prioritizing: activeID, todo: todo)
    }

    func value(for key: Key, schedulesOnDay: (LocalDay) -> [DaySchedule], preview: DaySchedule?,
               prioritizing activeID: UUID? = nil, todo: (UUID) -> TodoItem?) -> Snapshot {
        var entry: Entry
        if let cached = entries[key.week], cached.key == key {
            entry = cached
        } else {
            let days = (0..<7).map { key.week.adding(days: $0) }
            var includes: [UUID: Bool] = [:]
            var byID: [UUID: DaySchedule] = [:]
            var byDay: [LocalDay: [DaySchedule]] = [:]
            var placements: [LocalDay: [DayPlanningPolicy.Placement]] = [:]
            for day in days {
                let visible = schedulesOnDay(day).filter { schedule in
                    if let result = includes[schedule.id] { return result }
                    let result = schedule.todoID.map { id in todo(id).map(key.visibility.includes) ?? false } ?? true
                    includes[schedule.id] = result
                    return result
                }
                for schedule in visible { byID[schedule.id] = schedule }
                byDay[day] = visible
                placements[day] = DayPlanningPolicy.placements(visible, on: day)
                layoutBuildCount += 1
            }
            entry = Entry(key: key, days: days, schedulesByDay: byDay,
                base: Snapshot(schedulesByID: byID, placementsByDay: placements))
            entries = entries.filter { $0.value.key.revision == key.revision && $0.value.key.visibility == key.visibility }
            entries[key.week] = entry
            if entries.count > 7, let farthest = entries.keys.max(by: {
                abs(key.week.distance(to: $0)) < abs(key.week.distance(to: $1))
            }) { entries.removeValue(forKey: farthest) }
        }
        guard preview != nil || activeID != nil else { return entry.base }
        let previewKey = PreviewKey(schedule: preview, activeID: activeID)
        if entry.previewKey == previewKey, let cached = entry.preview { return cached }
        var result = entry.base
        let original = preview.flatMap { entry.base.schedulesByID[$0.id] }
        let includedPreview = preview.flatMap { schedule -> DaySchedule? in
            guard entry.days.contains(where: { schedule.interval(on: $0) != nil }) else { return nil }
            if let id = schedule.todoID, todo(id).map(key.visibility.includes) != true { return nil }
            return schedule
        }
        if let preview { result.schedulesByID.removeValue(forKey: preview.id) }
        if let includedPreview { result.schedulesByID[includedPreview.id] = includedPreview }
        for day in entry.days {
            let originalAffected = original?.interval(on: day) != nil
            let previewAffected = includedPreview?.interval(on: day) != nil
            let priorityAffected = activeID.flatMap { entry.base.schedulesByID[$0] }?.interval(on: day) != nil
            guard originalAffected || previewAffected || priorityAffected else { continue }
            var values = entry.schedulesByDay[day] ?? []
            if let preview { values.removeAll { $0.id == preview.id } }
            if previewAffected, let includedPreview { values.append(includedPreview) }
            result.placementsByDay[day] = DayPlanningPolicy.placements(values, on: day, prioritizing: activeID)
            layoutBuildCount += 1
        }
        entry.previewKey = previewKey; entry.preview = result
        entries[key.week] = entry
        return result
    }
}
