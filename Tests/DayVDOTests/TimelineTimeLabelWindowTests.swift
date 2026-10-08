import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TimelineTimeLabelWindowTests: XCTestCase {
    func testRenderedLabelsStaySeparatedAroundTheHourAtAllZooms() throws {
        for hourHeight: CGFloat in [45, 90, 180] {
            for minute in [20 * 60 + 59, 21 * 60, 21 * 60 + 1, 21 * 60 + 9, 21 * 60 + 30] {
                try check(minute: minute, hourHeight: hourHeight,
                          screenshot: minute == 21 * 60 + 9 ? "21-09-\(Int(hourHeight))" : nil)
            }
        }
    }

    func testRenderedLabelsStaySeparatedAtBothMidnightBoundaries() throws {
        for hourHeight: CGFloat in [45, 90, 180] {
            for minute in [0, 1439] {
                try check(minute: minute, hourHeight: hourHeight,
                          screenshot: hourHeight == 90 ? "boundary-\(minute)" : nil)
            }
        }
    }

    private func check(minute: Int, hourHeight: CGFloat, screenshot: String?) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let day = LocalDay(year: 2026, month: 10, day: 5)
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-TimeLabels-\(UUID())/todos.json"))
        let item = TodoItem(title: "Global_Content", dueDate: day.date())
        XCTAssertTrue(store.upsert(item))
        XCTAssertTrue(store.upsertSchedule(DaySchedule(startDay: day, startMinute: 1255,
            durationMinutes: 180, content: .todo(item.id))))
        let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 680, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView:
            DayTimelineView(day: day, hourHeight: .constant(hourHeight),
                restoredScrollMinute: .constant(CGFloat(max(0, minute - 90))),
                now: Calendar.current.date(byAdding: .minute, value: minute,
                                           to: Calendar.current.startOfDay(for: day.date()))!,
                presentation: .constant(nil), create: { _, _, _ in }, dropTodo: { _, _, _ in },
                editTodo: { _ in }, activityChanged: { _ in })
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .background(Color(nsColor: .windowBackgroundColor)))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if let screenshot {
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent("dayvdo-time-label-\(screenshot).png"))
        }
        // Inspect the painted text in the gutter, excluding the red marker
        // and arrangements to its right. This also catches rendering overlap.
        let scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
        var currentRows = Set<Int>()
        var tickRows = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<Int(46 * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.6 && color.redComponent > color.greenComponent * 1.6
                    && color.redComponent > color.blueComponent * 1.6 {
                    currentRows.insert(y)
                } else if color.redComponent > 0.4 && color.redComponent < 0.9
                    && abs(color.redComponent - color.greenComponent) < 0.05
                    && abs(color.redComponent - color.blueComponent) < 0.05 {
                    tickRows.insert(y)
                }
            }
        }
        XCTAssertFalse(currentRows.isEmpty, "Current time text remains visible")
        XCTAssertFalse(tickRows.isEmpty, "Fixed time ticks remain visible")
        let pixelGap = currentRows.flatMap { red in tickRows.map { abs(red - $0) } }.min() ?? 0
        XCTAssertGreaterThanOrEqual(CGFloat(pixelGap) / scale, 3,
            "Rendered text overlaps at minute \(minute), zoom \(hourHeight)")
    }
}
