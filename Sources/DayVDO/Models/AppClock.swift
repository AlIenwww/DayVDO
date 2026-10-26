import AppKit
import Combine
import Foundation

/// Visible pages share one periodic source. The last subscriber disconnects it.
/// Pages retain their own refresh decisions while sharing timer and notification sources.
@MainActor
enum AppClock {
    static let ticks = Timer.publish(every: 30, on: .main, in: .common)
        .autoconnect()
        .share()

    static let refreshes = Publishers.MergeMany(
        [ticks.eraseToAnyPublisher()] + [
            Notification.Name.NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            NSApplication.didBecomeActiveNotification
        ].map { name in
            NotificationCenter.default.publisher(for: name)
                .map { _ in Date.now }.eraseToAnyPublisher()
        }
    ).share()
}
