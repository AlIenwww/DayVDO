import Foundation

enum TodoDateFilter: Hashable, Sendable {
    case any
    case undated
    case today
    case tomorrow
    case thisWeek
    case nextWeek
    case thisMonth
    case custom(ClosedRange<LocalDay>)

    static let presets: [Self] = [.any, .undated, .today, .tomorrow, .thisWeek, .nextWeek, .thisMonth]

    var title: String {
        switch self {
        case .any: "全部日期"
        case .undated: "无日期"
        case .today: "今天"
        case .tomorrow: "明天"
        case .thisWeek: "本周"
        case .nextWeek: "下周"
        case .thisMonth: "本月"
        case .custom: "自定义范围"
        }
    }

    var usesRelativeDate: Bool {
        switch self {
        case .today, .tomorrow, .thisWeek, .nextWeek, .thisMonth: true
        default: false
        }
    }

    var usesWeekStart: Bool { self == .thisWeek || self == .nextWeek }

    var customRange: ClosedRange<LocalDay>? {
        if case .custom(let range) = self { return range }
        return nil
    }

    func range(today: LocalDay, startsOnMonday: Bool) -> ClosedRange<LocalDay>? {
        switch self {
        case .any, .undated: return nil
        case .today: return today...today
        case .tomorrow:
            let day = today.adding(days: 1)
            return day...day
        case .thisWeek, .nextWeek:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let weekday = calendar.component(.weekday, from: today.date(timeZone: calendar.timeZone))
            let offset = (weekday - (startsOnMonday ? 2 : 1) + 7) % 7
            let first = today.adding(days: -offset + (self == .nextWeek ? 7 : 0))
            return first...first.adding(days: 6)
        case .thisMonth:
            let first = LocalDay(year: today.year, month: today.month, day: 1)
            let next = today.month == 12
                ? LocalDay(year: today.year + 1, month: 1, day: 1)
                : LocalDay(year: today.year, month: today.month + 1, day: 1)
            return first...next.adding(days: -1)
        case .custom(let range): return range
        }
    }

    func includes(_ item: TodoItem, today: LocalDay, startsOnMonday: Bool) -> Bool {
        if self == .any { return true }
        if self == .undated { return item.startDay == nil && item.dueDay == nil }
        guard let start = item.startDay, let end = item.dueDay, start <= end,
              let selected = range(today: today, startsOnMonday: startsOnMonday) else { return false }
        return start <= selected.upperBound && end >= selected.lowerBound
    }
}
