import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

final class CalendarDateInputTests: XCTestCase {
    private let monday = LocalDay(year: 2026, month: 8, day: 31)

    @MainActor
    func testGeometryChangesUpdateTheResponderWithoutInvalidatingDateRows() {
        let (interaction, view) = grid()
        var rowInvalidations = 0
        let observation = interaction.objectWillChange.sink { rowInvalidations += 1 }
        let regions = [CalendarDateHitRegion(frame: CGRect(x: 105, y: 31, width: 90, height: 15),
            target: .item(UUID(), startsHere: true, endsHere: true))]
        interaction.hitRegions = regions
        XCTAssertEqual(view.regions, regions)
        XCTAssertEqual(rowInvalidations, 0)
        let replacement = CalendarDateInteraction()
        view.interaction = replacement
        interaction.hitRegions = []
        XCTAssertEqual(view.regions, replacement.hitRegions)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    private func grid() -> (CalendarDateInteraction, CalendarDateInput.InputView) {
        let interaction = CalendarDateInteraction()
        interaction.viewport = CGSize(width: 700, height: 300)
        interaction.frames = Dictionary(uniqueKeysWithValues: (0..<3).map {
            (monday.adding(days: $0 * 7), CGRect(x: 0, y: $0 * 100, width: 700, height: 100))
        })
        let view = CalendarDateInput.InputView(frame: CGRect(origin: .zero, size: interaction.viewport))
        view.interaction = interaction
        return (interaction, view)
    }

    @MainActor
    func testCapturedItemSurvivesSourceRegionRemovalAndCommitsOnce() {
        let (interaction, view) = grid()
        let item = TodoItem(title: "Source", dueDate: monday.adding(days: 1).date())
        view.resolveItem = { $0 == item.id ? item : nil }
        view.regions = [.init(frame: CGRect(x: 105, y: 31, width: 90, height: 15),
                              target: .item(item.id, startsHere: true, endsHere: true))]
        var changes: [TodoItem] = []
        view.change = { changes.append($0) }
        view.pointerDown(at: CGPoint(x: 150, y: 38), clickCount: 1)
        view.pointerDragged(to: CGPoint(x: 150, y: 140))
        view.regions = [] // SwiftUI removes the source bar while the pointer is down.
        view.pointerDragged(to: CGPoint(x: 150, y: 240))
        XCTAssertEqual(interaction.drag?.range, monday.adding(days: 15)...monday.adding(days: 15))
        XCTAssertTrue(changes.isEmpty)
        view.pointerUp(at: CGPoint(x: 150, y: 240))
        view.pointerUp(at: CGPoint(x: 150, y: 240))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.startDay, monday.adding(days: 15))
        XCTAssertNil(interaction.drag)
    }

    @MainActor
    func testContinuationGrabPreservesSpanAndOffset() {
        let (_, view) = grid()
        let item = TodoItem(title: "Range", startDate: monday.adding(days: 4).date(), dueDate: monday.adding(days: 8).date())
        view.resolveItem = { _ in item }
        let region = CalendarDateHitRegion(frame: CGRect(x: 5, y: 131, width: 190, height: 15),
                                          target: .item(item.id, startsHere: false, endsHere: true))
        XCTAssertEqual(region.mode(at: CGPoint(x: 6, y: 138)), .move)
        XCTAssertEqual(region.mode(at: CGPoint(x: 194, y: 138)), .end)
        view.regions = [region]
        var result: TodoItem?
        view.change = { result = $0 }
        view.pointerDown(at: CGPoint(x: 6, y: 138), clickCount: 1)
        view.pointerDragged(to: CGPoint(x: 106, y: 238))
        view.pointerUp(at: CGPoint(x: 106, y: 238))
        XCTAssertEqual(result?.startDay, monday.adding(days: 12))
        XCTAssertEqual(result?.dueDay, monday.adding(days: 16))
    }

    @MainActor
    func testEscapeAndWindowLossLatchUntilReleaseAndOutsideReleaseDoesNotCreate() {
        let (interaction, view) = grid()
        var count = 0
        view.create = { _, _ in count += 1 }
        view.pointerDown(at: CGPoint(x: 450, y: 80), clickCount: 1)
        view.pointerDragged(to: CGPoint(x: 150, y: 180))
        view.cancelPress() // Both Esc and window deactivation use this path.
        XCTAssertTrue(interaction.suppressed)
        view.pointerDragged(to: CGPoint(x: 150, y: 280))
        view.pointerDown(at: CGPoint(x: 150, y: 80), clickCount: 1)
        view.pointerUp(at: CGPoint(x: 150, y: 280))
        XCTAssertEqual(count, 0)
        XCTAssertFalse(interaction.suppressed)
        view.pointerDown(at: CGPoint(x: 450, y: 80), clickCount: 1)
        view.pointerDragged(to: CGPoint(x: 150, y: 180))
        view.pointerUp(at: CGPoint(x: 150, y: 310))
        XCTAssertEqual(count, 0)
        view.pointerDown(at: CGPoint(x: 450, y: 80), clickCount: 1)
        view.pointerDragged(to: CGPoint(x: 150, y: 180))
        view.pointerUp(at: CGPoint(x: 150, y: 180))
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testClickDoubleClickAndNoDateChangeDoNotCommit() {
        let (_, view) = grid()
        let selection = CalendarTodoSelection()
        view.selection = selection
        let item = TodoItem(title: "Task", dueDate: monday.date())
        view.resolveItem = { _ in item }
        view.regions = [.init(frame: CGRect(x: 5, y: 31, width: 90, height: 15),
                              target: .item(item.id, startsHere: true, endsHere: true))]
        var selected = 0, edited = 0
        view.select = { _ in selected += 1 }
        view.edit = { _ in edited += 1 }
        view.change = { _ in XCTFail("Same-day movement must not write") }
        view.create = { _, _ in XCTFail("Click must not create") }
        view.pointerDown(at: CGPoint(x: 50, y: 38), clickCount: 1)
        XCTAssertEqual(selection.selectedID, item.id) // Selection precedes mouse-up.
        XCTAssertEqual(edited, 0)
        view.pointerUp(at: CGPoint(x: 50, y: 38))
        XCTAssertEqual(selection.selectedID, item.id)
        XCTAssertEqual(selection.day, monday)
        XCTAssertEqual(edited, 0)
        view.pointerDown(at: CGPoint(x: 50, y: 38), clickCount: 2)
        view.pointerUp(at: CGPoint(x: 50, y: 38))
        view.pointerDown(at: CGPoint(x: 50, y: 38), clickCount: 1)
        view.pointerDragged(to: CGPoint(x: 65, y: 38))
        view.pointerUp(at: CGPoint(x: 65, y: 38))
        XCTAssertEqual(selected, 3); XCTAssertEqual(edited, 1)
        view.pointerDown(at: CGPoint(x: 350, y: 180), clickCount: 1)
        view.pointerUp(at: CGPoint(x: 350, y: 180))
        XCTAssertNil(selection.selectedID)
        XCTAssertEqual(selection.day, monday.adding(days: 10))
    }

    func testPreviewReservesVisibleLaneAndDoesNotChangeRealCount() {
        let items = (0..<8).map { index in
            CalendarWindowSnapshot.Item(id: UUID(), startDay: monday, dueDay: monday.adding(days: 10),
                title: "Item \(index)", status: .notStarted, hasProject: false, tagColor: nil)
        }
        let draft = CalendarWindowSnapshot.Item(id: UUID(), startDay: monday.adding(days: 4), dueDay: monday.adding(days: 8),
            title: "Draft", status: .notStarted, hasProject: false, tagColor: nil)
        for week in [monday, monday.adding(days: 7)] {
            let segments = CalendarDatePolicy.previewSegments(items, draft: draft, previewID: draft.id, week: week)
            XCTAssertEqual(segments.first?.id, draft.id)
            XCTAssertEqual(segments.first?.lane, 0)
            XCTAssertEqual(segments.filter { $0.id != draft.id }.count, 8)
            XCTAssertEqual(segments.filter { $0.lane < 2 }.count, 2)
            XCTAssertEqual(segments.filter { $0.lane >= 2 && $0.id != draft.id }.count, 7)
        }
        let regular = CalendarDatePolicy.previewSegments(items, draft: nil, previewID: nil, week: monday)
        XCTAssertEqual(regular, CalendarDatePolicy.segments(items, week: monday))
    }

    func testSplitFractionRespectsBothMinimumsWithoutChangingPreference() {
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: 0.6, availableHeight: 500), 300)
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: 0.1, availableHeight: 500), 120)
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: 0.95, availableHeight: 500), 400)
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: .nan, availableHeight: 500), 300)
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: 0.8, availableHeight: 220), 120)
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: 0.8, availableHeight: 1000), 800)
        XCTAssertEqual(CalendarWeekSplitPolicy.topHeight(fraction: 0.8, availableHeight: 110), 60)
    }

    @MainActor
    func testDividerOverlayLetsBothScrollPanesReceiveInput() {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 501))
        let split = CalendarWeekDivider.SplitView(frame: host.bounds)
        host.addSubview(split)
        split.addSubview(NSView()); split.addSubview(NSView())
        split.preferredFraction = 0.6
        split.applyFraction()

        for y: CGFloat in [80, 220, 380, 480] {
            let point = split.convert(NSPoint(x: 350, y: y), to: host)
            XCTAssertNil(split.hitTest(point))
        }
        let divider = split.convert(NSPoint(x: 350, y: 300), to: host)
        XCTAssertTrue(split.hitTest(divider) === split)
    }

    @MainActor
    func testNativeSplitWindowResizeKeepsRatioAndNeverPersistsTemporaryClamp() {
        let split = CalendarWeekDivider.SplitView(frame: CGRect(x: 0, y: 0, width: 700, height: 501))
        split.addSubview(NSView()); split.addSubview(NSView())
        split.preferredFraction = 0.8
        var writes = 0
        split.onUserResize = { _ in writes += 1 }
        split.applyFraction()
        XCTAssertEqual(split.subviews[0].frame.height, 400, accuracy: 0.01)
        split.setFrameSize(CGSize(width: 500, height: 221))
        XCTAssertEqual(split.subviews[0].frame.height, 120, accuracy: 0.01)
        XCTAssertEqual(split.subviews[1].frame.height, 100, accuracy: 0.01)
        split.setFrameSize(CGSize(width: 700, height: 1001))
        XCTAssertEqual(split.subviews[0].frame.height, 800, accuracy: 0.01)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(split.preferredFraction, 0.8)
    }
}
