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

    func testImportanceAndUrgencyLabels() {
        XCTAssertEqual(TodoItem.Priority.allCases.map(\.title), ["无", "可做", "需做", "必做"])
        XCTAssertEqual(
            TodoItem.Urgency.allCases.map(\.title),
            ["无", "改天也没关系", "最好当天完成", "当天必须完成"]
        )
    }

    func testLegacyItemWithoutUrgencyDefaultsToNone() throws {
        let item = TodoItem(
            title: "旧待办",
            dueDate: .now,
            priority: .high,
            urgency: .mustToday
        )
        let encoded = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "urgency")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TodoItem.self, from: legacyData)

        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.urgency, .none)
        XCTAssertNil(decoded.projectID)
        XCTAssertNil(decoded.projectSortOrder)
        XCTAssertNil(decoded.tagID)
    }

    func testLegacyProjectWithoutTagDecodesAsUntagged() throws {
        let project = TodoProject(title: "旧项目", tagID: UUID())
        let encoded = try JSONEncoder().encode(project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "tagID")

        let decoded = try JSONDecoder().decode(
            TodoProject.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.tagID)
    }
}
