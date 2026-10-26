import AppKit
import Combine
import XCTest
@testable import DayVDO

@MainActor
final class AppClockTests: XCTestCase {
    func testNativeRefreshNotificationsAreSharedAndReconnectAfterCancellation() {
        var first = 0, second = 0, resumed = 0
        let one = AppClock.refreshes.sink { _ in first += 1 }
        let two = AppClock.refreshes.sink { _ in second += 1 }
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        one.cancel()
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        two.cancel()
        let three = AppClock.refreshes.sink { _ in resumed += 1 }
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(resumed, 1)
        three.cancel()
    }
}
