import Foundation

enum CalendarDisplayMode: String { case month, week }

enum CalendarDateDragMode { case create, move, start, end }

enum CalendarDatePolicy {
    static func range(start: LocalDay, end: LocalDay, anchor: LocalDay,
                      target: LocalDay, mode: CalendarDateDragMode) -> ClosedRange<LocalDay> {
        switch mode {
        case .create: min(anchor, target)...max(anchor, target)
        case .move: start.adding(days: anchor.distance(to: target))...end.adding(days: anchor.distance(to: target))
        case .start: min(target, end)...end
        case .end: start...max(start, target)
        }
    }

    struct Segment: Identifiable, Equatable, Sendable {
        var item: CalendarWindowSnapshot.Item
        var firstColumn: Int
        var lastColumn: Int
        var lane: Int
        var startsHere: Bool
        var endsHere: Bool
        var id: UUID { item.id }
    }

    /// Existing tasks keep their normal lane during a drag. Only new drafts and
    /// previews hidden by overflow need a reserved visible lane.
    static func previewSegments(_ items: [CalendarWindowSnapshot.Item], draft: CalendarWindowSnapshot.Item?,
                                previewID: UUID?, week: LocalDay, maxLanes: Int = .max) -> [Segment] {
        let values = items + (draft.map { [$0] } ?? [])
        let regular = segments(values, week: week)
        guard let previewID,
              draft?.id == previewID || regular.contains(where: { $0.id == previewID && $0.lane >= maxLanes })
        else { return regular }
        let ordered = values.filter { $0.id == previewID } + values.filter { $0.id != previewID }
        return segments(ordered, week: week)
    }

    /// Input order is stable across a snapshot. Each interval occupies its first free lane.
    static func segments(_ items: [CalendarWindowSnapshot.Item], week: LocalDay) -> [Segment] {
        var occupied: [Set<Int>] = []
        let weekEnd = week.adding(days: 6)
        return items.compactMap { item in
            guard item.startDay <= weekEnd, item.dueDay >= week else { return nil }
            let first = max(0, week.distance(to: item.startDay))
            let last = min(6, week.distance(to: item.dueDay))
            let columns = Set(first...last)
            let lane = occupied.firstIndex { $0.isDisjoint(with: columns) } ?? occupied.count
            if lane == occupied.count { occupied.append(columns) }
            else { occupied[lane].formUnion(columns) }
            return Segment(item: item, firstColumn: first, lastColumn: last, lane: lane,
                           startsHere: item.startDay >= week, endsHere: item.dueDay <= weekEnd)
        }
    }
}

struct CalendarDateLayout: Equatable, Sendable {
    let segments: [CalendarDatePolicy.Segment]
    let lanes: [[CalendarDatePolicy.Segment]]

    init(segments: [CalendarDatePolicy.Segment]) {
        self.segments = segments
        var lanes = Array(repeating: [CalendarDatePolicy.Segment](),
                          count: max(1, (segments.map(\.lane).max() ?? 0) + 1))
        for segment in segments { lanes[segment.lane].append(segment) }
        self.lanes = lanes
    }
}

enum WeekSchedulePolicy {
    enum Mode { case move, start, end }

    static func adjusted(_ schedule: DaySchedule, mode: Mode, dayDelta: Int,
                         minuteDelta: Double) -> DaySchedule {
        var value = schedule
        switch mode {
        case .move:
            value.startDay = schedule.startDay.adding(days: dayDelta)
            if abs(minuteDelta) > 0.001 {
                value.startMinute = DayPlanningPolicy.snapped(Double(schedule.startMinute) + minuteDelta,
                                                             within: 0...1439) ?? schedule.startMinute
            }
        case .start:
            let absolute = dayDelta * 1440 + DayPlanningPolicy.snapped(Double(schedule.startMinute) + minuteDelta)
            guard let newStart = DayPlanningPolicy.snapped(Double(absolute),
                within: (schedule.endMinute - 1440)...(schedule.endMinute - 1)) else { return schedule }
            let dayOffset = Int(floor(Double(newStart) / 1440))
            value.startDay = schedule.startDay.adding(days: dayOffset)
            value.startMinute = newStart - dayOffset * 1440
            value.durationMinutes = schedule.endMinute - newStart
        case .end:
            let absolute = dayDelta * 1440 + DayPlanningPolicy.snapped(Double(schedule.endMinute) + minuteDelta)
            guard let newEnd = DayPlanningPolicy.snapped(Double(absolute),
                within: (schedule.startMinute + 1)...(schedule.startMinute + 1440)) else { return schedule }
            value.durationMinutes = newEnd - schedule.startMinute
        }
        return value
    }
}
