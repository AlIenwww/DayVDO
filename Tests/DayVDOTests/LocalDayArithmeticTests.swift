import XCTest
@testable import DayVDO

final class LocalDayArithmeticTests: XCTestCase {
    func testDateArithmeticMatchesFoundationAcrossLeapYearsAndDSTDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for year in [1900, 2000, 2024, 2026, 2100] {
            for month in [1, 2, 3, 10, 11, 12] {
                let day = LocalDay(year: year, month: month, day: 28)
                for offset in [-366, -31, -1, 0, 1, 31, 366] {
                    let expected = LocalDay(calendar.date(byAdding: .day, value: offset,
                        to: day.date(timeZone: calendar.timeZone))!, timeZone: calendar.timeZone)
                    XCTAssertEqual(day.adding(days: offset), expected)
                    XCTAssertEqual(day.distance(to: expected), offset)
                    XCTAssertEqual(expected.distance(to: day), -offset)
                }
            }
        }
    }

    func testScheduleClippingMatchesReferenceAtDayBoundaries() {
        let day = LocalDay(year: 2024, month: 2, day: 29)
        for start in [0, 1, 60, 720, 1380, 1439] {
            for duration in [1, 30, 60, 720, 1440] {
                let schedule = DaySchedule(startDay: day, startMinute: start,
                    durationMinutes: duration, content: .independent(title: "Test", notes: ""))
                for offset in -2...3 {
                    let lower = max(0, start - offset * 1440)
                    let upper = min(1440, start + duration - offset * 1440)
                    XCTAssertEqual(schedule.interval(on: day.adding(days: offset)), lower < upper ? lower..<upper : nil)
                }
            }
        }
    }
}
