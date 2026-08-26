import XCTest
@testable import DayVDO

final class CalendarMonthGridTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testGridAlwaysContainsSixCompleteWeeks() throws {
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let dates = CalendarMonthGrid.dates(containing: month, calendar: calendar)

        XCTAssertEqual(dates.count, 42)
        for index in 1..<dates.count {
            XCTAssertEqual(calendar.dateComponents([.day], from: dates[index - 1], to: dates[index]).day, 1)
        }
    }

    func testAugust2026StartsInSaturdayColumnWhenWeekStartsMonday() throws {
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let dates = CalendarMonthGrid.dates(containing: month, calendar: calendar)
        let augustFirstIndex = try XCTUnwrap(dates.firstIndex(where: {
            calendar.component(.year, from: $0) == 2026 &&
            calendar.component(.month, from: $0) == 8 &&
            calendar.component(.day, from: $0) == 1
        }))

        XCTAssertEqual(augustFirstIndex, 5)
    }
}
