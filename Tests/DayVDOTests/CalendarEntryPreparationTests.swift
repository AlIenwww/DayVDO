import XCTest
@testable import DayVDO

final class CalendarEntryPreparationTests: XCTestCase {
    func testInitialWeekAnchorPlacesWeekZeroAtTheViewportTop() {
        let anchor = CalendarScrollPolicy.initialWeekAnchor(range: -104...104, visibleCount: 6)
        XCTAssertEqual(anchor * CGFloat(209 - 6), 104, accuracy: 0.0001)
    }

    func testTimelineAnchorClampsAtTheEndAndHandlesAnOversizedViewport() {
        XCTAssertEqual(CalendarScrollPolicy.initialAnchor(offset: 720, contentHeight: 2184, viewportHeight: 600),
                       720 / 1584, accuracy: 0.0001)
        XCTAssertEqual(CalendarScrollPolicy.initialAnchor(offset: 3000, contentHeight: 2184, viewportHeight: 600), 1)
        XCTAssertEqual(CalendarScrollPolicy.initialAnchor(offset: 720, contentHeight: 2184, viewportHeight: 3000), 0)
    }

    @MainActor func testVisibleSnapshotIsRetainedWhileTheWindowExpands() async {
        let cache = CalendarWindowCache()
        let visible = request(days: 42, revision: 1)
        cache.prepare(visible, priority: .userInitiated)
        let ready = await cache.waitForSnapshot(covering: visible.key, until: .now + .seconds(2))
        XCTAssertTrue(ready)
        let original = cache.snapshot
        let expanded = request(days: 210, revision: 1)
        cache.prepare(expanded)
        XCTAssertEqual(cache.snapshot, original)
        XCTAssertTrue(cache.hasSnapshot(covering: visible.key))
        let expandedReady = await cache.waitForSnapshot(covering: expanded.key, until: .now + .seconds(2))
        XCTAssertTrue(expandedReady)
        XCTAssertTrue(cache.hasSnapshot(covering: visible.key))
    }

    @MainActor func testExpiredAndCancelledWaitsFinishWithoutPublishingStaleData() async {
        let cache = CalendarWindowCache()
        let key = request(days: 42, revision: 1).key
        let expired = await cache.waitForSnapshot(covering: key, until: .now - .milliseconds(1))
        XCTAssertFalse(expired)
        let wait = Task { await cache.waitForSnapshot(covering: key, until: .now + .seconds(30)) }
        await Task.yield()
        wait.cancel()
        let cancelled = await wait.value
        XCTAssertFalse(cancelled)
        XCTAssertNil(cache.snapshot)
    }

    @MainActor func testAnOlderRevisionCannotSatisfyEntryReadiness() async {
        let cache = CalendarWindowCache()
        let old = request(days: 42, revision: 1)
        cache.prepare(old)
        _ = await cache.waitForSnapshot(covering: old.key, until: .now + .seconds(2))
        var newest = old.key
        newest.revision = 2
        XCTAssertFalse(cache.hasSnapshot(covering: newest))
        newest = old.key
        newest.visibility.showCompleted.toggle()
        XCTAssertFalse(cache.hasSnapshot(covering: newest))
        newest = old.key
        newest.firstWeekday = 1
        XCTAssertFalse(cache.hasSnapshot(covering: newest))
    }

    func testCachedDateLayoutKeepsCrossWeekEdgesAndStableLaneOrdering() {
        let request = request(days: 42, revision: 1)
        let snapshot = CalendarWindowSnapshot.build(key: request.key, items: request.items, tags: [])
        let week = request.key.firstDay
        let layout = snapshot.dateLayoutsByWeek[week]
        XCTAssertEqual(layout?.segments.map(\.id), snapshot.items(inWeek: week).map(\.id))
        XCTAssertEqual(layout?.lanes.flatMap { $0 }.count, layout?.segments.count)
        XCTAssertEqual(layout?.segments.first?.startsHere, true)
        XCTAssertEqual(layout?.segments.first?.endsHere, false)
    }

    private func request(days: Int, revision: UInt64) -> CalendarWindowRequest {
        let first = LocalDay(year: 2026, month: 9, day: 21)
        return .init(key: .init(revision: revision, firstDay: first, lastDay: first.adding(days: days - 1),
                               timeZoneIdentifier: "Asia/Shanghai", firstWeekday: 2, visibility: .init(showCompleted: true)),
                     items: [TodoItem(title: "跨周任务", startDate: first.date(), dueDate: first.adding(days: 9).date())], tags: [])
    }
}
