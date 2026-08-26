import Foundation

enum CalendarMonthGrid {
    static func dates(containing month: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let firstGridDate = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: interval.start
        ) else { return [] }

        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstGridDate)
        }
    }
}
