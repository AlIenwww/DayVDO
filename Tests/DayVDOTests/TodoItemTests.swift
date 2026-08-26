import XCTest
@testable import DayVDO

final class TodoItemTests: XCTestCase {
    func testItemMatchesOnlyItsDueDay() {
        let calendar = Calendar(identifier: .gregorian)
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 18))!
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 8))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        let item = TodoItem(title: "测试", dueDate: due)

        XCTAssertTrue(item.isDue(on: sameDay, calendar: calendar))
        XCTAssertFalse(item.isDue(on: nextDay, calendar: calendar))
    }

    func testNormalizedTitleTrimsWhitespace() {
        XCTAssertEqual(TodoItem(title: "  写周报 \n").normalizedTitle, "写周报")
    }
}
