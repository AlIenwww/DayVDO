import Foundation

/// A calendar date without a time or time-zone component.
///
/// DayVDO tasks are due on a day, not at an instant. Persisting the components
/// prevents a task from moving to the previous or next day when the user
/// changes time zones.
struct LocalDay: Hashable, Comparable, Sendable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    func date(timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Noon is valid even on daylight-saving transition days.
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        ) ?? .distantPast
    }

    // Date-only arithmetic must not follow the system time zone or DST.
    private static let arithmeticCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var arithmeticDate: Date {
        Self.arithmeticCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            ?? .distantPast
    }

    func adding(days: Int) -> LocalDay {
        guard days != 0 else { return self }
        let calendar = Self.arithmeticCalendar
        let date = calendar.date(byAdding: .day, value: days, to: arithmeticDate)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    func distance(to other: LocalDay) -> Int {
        guard self != other else { return 0 }
        return Self.arithmeticCalendar.dateComponents([.day], from: arithmeticDate, to: other.arithmeticDate).day!
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid local day: \(value)")
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )
        let validated = date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        guard validated?.year == year, validated?.month == month, validated?.day == day else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid local day: \(value)")
            )
        }
        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(
            String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), year, month, day)
        )
    }
}
