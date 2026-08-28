import XCTest
@testable import DayVDO

final class TodoStoreTests: XCTestCase {
    @MainActor
    func testDayIndexTracksInsertMoveAndDelete() {
        let calendar = Calendar.current
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 9))!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDOTests-\(UUID().uuidString).json")
        let store = TodoStore(fileURL: fileURL)
        var item = TodoItem(title: "索引测试", dueDate: firstDay)

        store.upsert(item)
        XCTAssertEqual(store.items(on: firstDay).map(\.id), [item.id])

        item.dueDate = secondDay
        store.upsert(item)
        XCTAssertTrue(store.items(on: firstDay).isEmpty)
        XCTAssertEqual(store.items(on: secondDay).map(\.id), [item.id])

        store.delete(item)
        XCTAssertTrue(store.items(on: secondDay).isEmpty)
    }
}
