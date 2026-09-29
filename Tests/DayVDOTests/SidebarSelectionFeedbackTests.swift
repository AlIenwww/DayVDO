import AppKit
import XCTest
@testable import DayVDO

@MainActor
final class SidebarSelectionFeedbackTests: XCTestCase {
    func testOnlyTheOwningWindowReleasesTheDetailPage() async {
        let window = NSWindow()
        let otherWindow = NSWindow()
        let feedback = SidebarSelectionFeedback()
        feedback.window = window
        var released = false
        let wait = Task {
            await feedback.waitForWindowUpdate()
            released = true
        }
        await Task.yield()
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: otherWindow)
        await Task.yield()
        XCTAssertFalse(released)

        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        await wait.value
        XCTAssertTrue(released)
    }

    func testRapidNavigationCanCancelAnUnfinishedWindowWait() async {
        let feedback = SidebarSelectionFeedback()
        let window = NSWindow()
        feedback.window = window
        let wait = Task { await feedback.waitForWindowUpdate() }
        await Task.yield()
        wait.cancel()
        await wait.value

        let nextWait = Task { await feedback.waitForWindowUpdate() }
        await Task.yield()
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        await nextWait.value
    }

    func testAnUpdateBeforeThePresentationTaskStartsIsRemembered() async {
        let feedback = SidebarSelectionFeedback()
        let window = NSWindow()
        feedback.window = window
        let update = feedback.nextWindowUpdate()
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        try? await Task.sleep(for: .milliseconds(1))
        // No second notification should be needed after the task begins.
        await update.wait()
    }

    func testRapidSelectionPresentsOnlyTheLastDestination() async {
        let presentation = SidebarPagePresentation()
        let window = NSWindow()
        presentation.feedback.window = window
        presentation.selection = .calendar
        presentation.presentSelection { nil }
        presentation.selection = .all
        presentation.presentSelection { nil }
        XCTAssertEqual(presentation.displayedDestination, .today)

        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        for _ in 0..<100 where presentation.displayedDestination != .all {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(presentation.displayedDestination, .all)
    }

    func testReturningToTheDisplayedPageCancelsPendingNavigation() async {
        let presentation = SidebarPagePresentation()
        let window = NSWindow()
        presentation.feedback.window = window
        presentation.selection = .calendar
        presentation.presentSelection { nil }
        presentation.selection = .today
        presentation.presentSelection { nil }
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        try? await Task.sleep(for: .milliseconds(1))
        XCTAssertEqual(presentation.displayedDestination, .today)
    }

    func testCalendarKeepsThePreviousPageUntilDataIsReady() async {
        let presentation = SidebarPagePresentation()
        let window = NSWindow()
        presentation.feedback.window = window
        let cache = CalendarWindowCache()
        let request = calendarRequest()
        presentation.selection = .calendar
        presentation.presentSelection { .init(cache: cache, key: request.key) }
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        await Task.yield()
        XCTAssertEqual(presentation.selection, .calendar)
        XCTAssertEqual(presentation.displayedDestination, .today)
        cache.prepare(request, priority: .userInitiated)
        for _ in 0..<100 where presentation.displayedDestination != .calendar {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(presentation.displayedDestination, .calendar)
        XCTAssertFalse(presentation.calendarPreparationTimedOut)
    }

    func testMissingCalendarDataFallsBackAndIsMarkedAsDegraded() async {
        let presentation = SidebarPagePresentation()
        let window = NSWindow()
        presentation.feedback.window = window
        let cache = CalendarWindowCache()
        let key = calendarRequest().key
        presentation.selection = .calendar
        presentation.presentSelection { .init(cache: cache, key: key) }
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        for _ in 0..<150 where presentation.displayedDestination != .calendar {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(presentation.displayedDestination, .calendar)
        XCTAssertTrue(presentation.calendarPreparationTimedOut)
        XCTAssertNil(cache.snapshot)
    }

    func testAReadyOldCalendarRequestCannotReplaceANewerSelection() async {
        let presentation = SidebarPagePresentation()
        let window = NSWindow()
        presentation.feedback.window = window
        let cache = CalendarWindowCache()
        let request = calendarRequest()
        presentation.selection = .calendar
        presentation.presentSelection { .init(cache: cache, key: request.key) }
        await Task.yield()
        presentation.selection = .settings
        presentation.presentSelection { nil }
        cache.prepare(request)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        _ = await cache.waitForSnapshot(covering: request.key, until: .now + .seconds(2))
        for _ in 0..<100 where presentation.displayedDestination != .settings {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(presentation.displayedDestination, .settings)
    }

    private func calendarRequest() -> CalendarWindowRequest {
        let day = LocalDay(year: 2026, month: 9, day: 28)
        return .init(key: .init(revision: 1, firstDay: day, lastDay: day.adding(days: 41),
            timeZoneIdentifier: "Asia/Shanghai", firstWeekday: 2, showCompleted: true),
            items: [TodoItem(title: "待办", dueDate: day.date())], tags: [])
    }
}
