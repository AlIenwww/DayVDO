import Foundation

enum AppCalendar {
    static func make(locale: Locale, startsOnMonday: Bool, timeZone: TimeZone? = nil) -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        if let timeZone {
            calendar.timeZone = timeZone
        }
        calendar.firstWeekday = startsOnMonday ? 2 : 1
        return calendar
    }
}
