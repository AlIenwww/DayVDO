import Foundation

/// A wall-clock plan, deliberately independent of time zones and elapsed DST hours.
struct DaySchedule: Identifiable, Codable, Equatable, Sendable {
    enum Content: Codable, Equatable, Sendable {
        case todo(UUID)
        case independent(title: String, notes: String)
    }

    var id = UUID()
    var startDay: LocalDay
    var startMinute: Int
    var durationMinutes: Int
    var content: Content

    var todoID: UUID? {
        if case .todo(let id) = content { return id }
        return nil
    }
    var isValid: Bool {
        guard (0..<1440).contains(startMinute), (1...1440).contains(durationMinutes) else { return false }
        if case .independent(let title, _) = content {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    var endMinute: Int { startMinute + durationMinutes }

    func interval(on day: LocalDay) -> Range<Int>? {
        let offset = startDay.distance(to: day) * 1440
        let lower = max(0, startMinute - offset)
        let upper = min(1440, endMinute - offset)
        return lower < upper ? lower..<upper : nil
    }
}

extension LocalDay {
    func adding(days: Int) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return LocalDay(calendar.date(byAdding: .day, value: days, to: date(timeZone: calendar.timeZone))!, timeZone: calendar.timeZone)
    }

    func distance(to other: LocalDay) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.day], from: date(timeZone: calendar.timeZone), to: other.date(timeZone: calendar.timeZone)).day!
    }
}

enum DayPlanningPolicy {
    struct Placement: Identifiable, Equatable {
        var id: UUID
        var interval: Range<Int>
        var column: Int
        var columnCount: Int
    }

    static func snapped(_ minute: Double) -> Int {
        Int((minute / 5).rounded()) * 5
    }

    /// Clamp to legal grid points, not arbitrary minute limits at either edge.
    static func snapped(_ minute: Double, within limits: ClosedRange<Int>) -> Int? {
        let first = Int(ceil(Double(limits.lowerBound) / 5)) * 5
        let last = Int(floor(Double(limits.upperBound) / 5)) * 5
        guard first <= last else { return nil }
        return min(last, max(first, snapped(minute)))
    }

    static func defaultDuration(estimated: Int?, scheduled: Int) -> Int {
        guard let estimated, estimated > scheduled else { return 30 }
        return min(1440, estimated - scheduled)
    }

    static func isInProgress(_ placement: Placement, at minute: Int, onCurrentDay: Bool) -> Bool {
        onCurrentDay && placement.interval.contains(minute)
    }

    /// Connected overlap groups have stable, equal-width columns. Touching edges do not overlap.
    static func placements(_ schedules: [DaySchedule], on day: LocalDay) -> [Placement] {
        let sorted = schedules.compactMap { schedule -> (UUID, Range<Int>)? in
            schedule.interval(on: day).map { (schedule.id, $0) }
        }.sorted {
            if $0.1.lowerBound != $1.1.lowerBound { return $0.1.lowerBound < $1.1.lowerBound }
            if $0.1.upperBound != $1.1.upperBound { return $0.1.upperBound > $1.1.upperBound }
            return $0.0.uuidString < $1.0.uuidString
        }
        var result: [Placement] = []
        var group: [Placement] = []
        var columnEnds: [Int] = []
        var groupEnd = -1
        func flush() {
            result += group.map { var p = $0; p.columnCount = columnEnds.count; return p }
            group = []
            columnEnds = []
        }
        for (id, interval) in sorted {
            if interval.lowerBound >= groupEnd { flush() }
            let column = columnEnds.firstIndex(where: { $0 <= interval.lowerBound }) ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(interval.upperBound) }
            else { columnEnds[column] = interval.upperBound }
            groupEnd = max(groupEnd, interval.upperBound)
            group.append(Placement(id: id, interval: interval, column: column, columnCount: 1))
        }
        flush()
        return result
    }

    static func followedDay(selected: LocalDay, previousToday: LocalDay, today: LocalDay) -> LocalDay {
        selected == previousToday ? today : selected
    }
}

/// Escape remains latched through key repeats and interrupted gesture callbacks.
/// Only a physical mouse release permits another drag to begin.
struct TimelineDragCancellation {
    private(set) var isSuppressed = false

    mutating func cancel(isDragging: Bool) {
        isSuppressed = isSuppressed || isDragging
    }

    @discardableResult
    mutating func observeMouseButton(isPressed: Bool) -> Bool {
        guard isSuppressed, !isPressed else { return false }
        isSuppressed = false
        return true
    }
}
