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

    @MainActor
    func testPendingEditKeepsVisibleTasksUntilTheReplacementIsReady() async throws {
        let cache = CalendarWindowCache()
        let unchanged = TodoItem(title: "Unchanged", dueDate: windowStart.date())
        var edited = TodoItem(title: "Before", dueDate: windowStart.adding(days: 1).date())
        let initial = request(items: [unchanged, edited], revision: 1)
        cache.prepare(initial)
        let ready = await cache.waitForSnapshot(covering: initial.key, until: .now + .seconds(2))
        XCTAssertTrue(ready)

        edited.title = "After"
        edited.startDay = windowStart.adding(days: 2)
        edited.dueDay = edited.startDay
        let update = request(items: [unchanged, edited], revision: 2)
        cache.prepare(update)
        let pending = try XCTUnwrap(cache.snapshotForDisplay(matching: update.key))
        XCTAssertEqual(Set(pending.rangedItems.map(\.id)), [unchanged.id, edited.id])
        XCTAssertTrue(pending.dateLayoutsByWeek.isEmpty, "Pending rows must resolve current task dates and styles")
        XCTAssertFalse(cache.hasSnapshot(covering: update.key), "Visible fallback does not mean fresh data is ready")
        XCTAssertFalse(try XCTUnwrap(cache.snapshot).dateLayoutsByWeek.isEmpty)

        let updated = await cache.waitForSnapshot(covering: update.key, until: .now + .seconds(2))
        XCTAssertTrue(updated)
        let displayed = try XCTUnwrap(cache.snapshotForDisplay(matching: update.key))
        XCTAssertEqual(displayed.items(on: windowStart).map(\.id), [unchanged.id])
        XCTAssertTrue(displayed.items(on: windowStart.adding(days: 1)).isEmpty)
        XCTAssertEqual(displayed.items(on: windowStart.adding(days: 2)).first?.title, "After")
        XCTAssertFalse(displayed.dateLayoutsByWeek.isEmpty)
    }

    @MainActor
    func testPendingFilterRecomputesLayoutsButCalendarGeometryMustMatch() async throws {
        let cache = CalendarWindowCache()
        let item = TodoItem(title: "Done", dueDate: windowStart.date(), isCompleted: true)
        let initial = request(items: [item], revision: 1)
        cache.prepare(initial)
        let ready = await cache.waitForSnapshot(covering: initial.key, until: .now + .seconds(2))
        XCTAssertTrue(ready)

        var filteredKey = initial.key
        filteredKey.visibility.showCompleted = false
        let pending = try XCTUnwrap(cache.snapshotForDisplay(matching: filteredKey))
        XCTAssertTrue(pending.dateLayoutsByWeek.isEmpty, "The previous filter's layout must never bypass the current filter")
        XCTAssertFalse(cache.hasSnapshot(covering: filteredKey))
        filteredKey.firstWeekday = 1
        XCTAssertNil(cache.snapshotForDisplay(matching: filteredKey))
        filteredKey = initial.key
        filteredKey.timeZoneIdentifier = "America/Los_Angeles"
        XCTAssertNil(cache.snapshotForDisplay(matching: filteredKey))
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
                visibility: .init(showCompleted: showCompleted)
            ),
            items: items,
            tags: tags
        )
    }
}
