import XCTest
@testable import DayVDO

final class CalendarWindowSnapshotTests: XCTestCase {
    private let windowStart = LocalDay(year: 2026, month: 9, day: 1)
    private let windowEnd = LocalDay(year: 2026, month: 9, day: 30)

    func testSnapshotClipsRangesToWindowAndIncludesEveryAssignedDay() {
        let item = TodoItem(
            title: "跨月任务",
            startDate: LocalDay(year: 2026, month: 8, day: 30).date(),
            dueDate: LocalDay(year: 2026, month: 9, day: 3).date()
        )
        let snapshot = makeSnapshot(items: [item])

        XCTAssertEqual(snapshot.items(on: windowStart).map(\.id), [item.id])
        XCTAssertEqual(snapshot.items(on: windowStart.adding(days: 2)).map(\.id), [item.id])
        XCTAssertTrue(snapshot.items(on: windowStart.adding(days: 3)).isEmpty)
        XCTAssertEqual(snapshot.itemsByDay.count, 3)
    }

    func testCompletedVisibilityAndPresentationMetadataAreResolvedOnce() {
        let tag = TaskTag(name: "设计", color: TagColor(red: 0.8, green: 0.2, blue: 0.3))
        let item = TodoItem(
            title: "完成项",
            dueDate: windowStart.date(),
            priority: .high,
            isCompleted: true,
            projectID: UUID(),
            tagID: tag.id
        )

        XCTAssertTrue(makeSnapshot(items: [item], tags: [tag], showCompleted: false)
            .items(on: windowStart).isEmpty)
        let visible = makeSnapshot(items: [item], tags: [tag], showCompleted: true)
            .items(on: windowStart)
        XCTAssertEqual(visible.first?.status, .completed)
        XCTAssertEqual(visible.first?.tagColor, tag.color)
        XCTAssertEqual(visible.first?.hasProject, true)
    }

    func testSnapshotUsesStableTodoOrdering() {
        let low = TodoItem(title: "低", dueDate: windowStart.date(), priority: .low)
        let high = TodoItem(title: "高", dueDate: windowStart.date(), priority: .high)
        let snapshot = makeSnapshot(items: [low, high])

        XCTAssertEqual(snapshot.items(on: windowStart).map(\.id), [high.id, low.id])
    }

    func testThousandItemWindowBuildKeepsOnlyIntersectingItems() {
        let items = (0..<1_000).map { index in
            TodoItem(
                title: "任务 \(index)",
                dueDate: windowStart.adding(days: index % 45).date(),
                priority: TodoItem.Priority(rawValue: index % 4) ?? .none
            )
        }
        let snapshot = makeSnapshot(items: items)

        XCTAssertEqual(snapshot.itemsByDay.values.reduce(0) { $0 + $1.count }, 670)
        XCTAssertTrue(snapshot.itemsByDay.keys.allSatisfy { windowStart...windowEnd ~= $0 })
    }

    @MainActor
    func testCachePublishesOnlyTheNewestRequest() async {
        let cache = CalendarWindowCache()
        let oldItems = (0..<1_000).map { index in
            TodoItem(title: "旧任务 \(index)", dueDate: windowStart.date())
        }
        let newest = TodoItem(title: "最新任务", dueDate: windowStart.date())
        cache.prepare(request(items: oldItems, revision: 1))
        cache.prepare(request(items: [newest], revision: 2))

        for _ in 0..<100 where cache.snapshot?.key.revision != 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(cache.snapshot?.key.revision, 2)
        XCTAssertEqual(cache.snapshot?.items(on: windowStart).map(\.id), [newest.id])
    }

    private func makeSnapshot(
        items: [TodoItem],
        tags: [TaskTag] = [],
        showCompleted: Bool = true,
        revision: UInt64 = 1
    ) -> CalendarWindowSnapshot {
        CalendarWindowSnapshot.build(
            key: request(
                items: items,
                tags: tags,
                showCompleted: showCompleted,
                revision: revision
            ).key,
            items: items,
            tags: tags
        )
    }

    private func request(
        items: [TodoItem],
        tags: [TaskTag] = [],
        showCompleted: Bool = true,
        revision: UInt64
    ) -> CalendarWindowRequest {
        CalendarWindowRequest(
            key: CalendarWindowSnapshot.Key(
                revision: revision,
                firstDay: windowStart,
                lastDay: windowEnd,
                timeZoneIdentifier: "GMT",
                firstWeekday: 2,
                showCompleted: showCompleted
            ),
            items: items,
            tags: tags
        )
    }
}
