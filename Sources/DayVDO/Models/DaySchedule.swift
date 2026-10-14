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
    var horizontalPosition: Double? = nil
    var horizontalPositionUpdatedAt: Date? = nil

    mutating func setHorizontalPosition(_ position: Double, at date: Date = .now) {
        horizontalPosition = position
        horizontalPositionUpdatedAt = date
    }

    var todoID: UUID? {
        if case .todo(let id) = content { return id }
        return nil
    }
    var isValid: Bool {
        guard (0..<1440).contains(startMinute), (1...1440).contains(durationMinutes) else { return false }
        if let horizontalPosition, !horizontalPosition.isFinite || !(0...1).contains(horizontalPosition) { return false }
        if case .independent(let title, _) = content {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    var endMinute: Int { startMinute + durationMinutes }

    /// The end is exclusive: an arrangement ending at midnight occupies only
    /// its starting day. A partially overlapping arrangement stays indivisible.
    func isContained(in days: ClosedRange<LocalDay>) -> Bool {
        let lastDay = startDay.adding(days: (endMinute - 1) / 1440)
        return days.contains(startDay) && days.contains(lastDay)
    }

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

    static func initialScrollMinute(schedules: [DaySchedule], on day: LocalDay, now: Date = .now) -> Int {
        if let earliest = schedules.compactMap({ $0.interval(on: day)?.lowerBound }).min() {
            return earliest
        }
        guard day == LocalDay(now) else { return 0 }
        let time = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }

    static func isInProgress(_ placement: Placement, at minute: Int, onCurrentDay: Bool) -> Bool {
        onCurrentDay && placement.interval.contains(minute)
    }

    static func horizontalPosition(x: Double, minX: Double, width: Double) -> Double {
        guard x.isFinite, minX.isFinite, width.isFinite, width > 0 else { return 0.5 }
        return min(1, max(0, (x - minX) / width))
    }

    /// Connected overlap groups use only as many columns as their simultaneous overlap needs.
    /// Column permutations honor pointer positions without putting conflicts in the same column.
    static func placements(_ schedules: [DaySchedule], on day: LocalDay,
                           prioritizing activeID: UUID? = nil) -> [Placement] {
        let byID = Dictionary(schedules.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
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
            let count = columnEnds.count
            var available = Array(0..<count)
            var columns: [Int: Int] = [:]
            let preferred = group.filter { byID[$0.id]?.horizontalPosition != nil }.sorted {
                if ($0.id == activeID) != ($1.id == activeID) { return $0.id == activeID }
                let left = byID[$0.id]?.horizontalPositionUpdatedAt ?? .distantPast
                let right = byID[$1.id]?.horizontalPositionUpdatedAt ?? .distantPast
                return left != right ? left > right : $0.id.uuidString < $1.id.uuidString
            }
            func reserve(_ source: Int, near target: Int) {
                guard columns[source] == nil,
                      let destination = available.min(by: {
                          let left = abs($0 - target), right = abs($1 - target)
                          return left != right ? left < right : $0 < $1
                      }) else { return }
                columns[source] = destination
                available.removeAll { $0 == destination }
            }
            for placement in preferred {
                guard let position = byID[placement.id]?.horizontalPosition, position.isFinite else { continue }
                let target = min(count - 1, Int(min(1, max(0, position)) * Double(count)))
                reserve(placement.column, near: target)
            }
            for source in 0..<count { reserve(source, near: source) }
            result += group.map {
                var placement = $0
                placement.columnCount = count
                placement.column = columns[placement.column] ?? placement.column
                return placement
            }
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
