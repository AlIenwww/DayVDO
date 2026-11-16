import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class TaskAssignmentPickerWindowTests: XCTestCase {
    func testExpandedPickerPaintsTheTagColors() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let tags = [
            TaskTag(name: "Pink", color: .init(red: 0.9, green: 0.1, blue: 0.45)),
            TaskTag(name: "Green", color: .init(red: 0.05, green: 0.7, blue: 0.15))
        ]
        let host = NSHostingView(rootView: TaskAssignmentPicker(title: "Project", selection: tags[0].id,
            options: tags.map { .init(id: $0.id, title: $0.name, tag: $0) },
            noneTitle: "None", symbol: "folder", createTitle: "New Project",
            select: { _ in }, create: {}, isPresented: .constant(true))
            .frame(width: 360, height: 360))
        let window = NSWindow(contentRect: .init(x: 200, y: 250, width: 360, height: 360),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }

        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(35))
        }
        let popup = try XCTUnwrap(window.childWindows?.first(where: \.isVisible)?.contentView)
        let bitmap = try XCTUnwrap(popup.bitmapImageRepForCachingDisplay(in: popup.bounds))
        popup.cacheDisplay(in: popup.bounds, to: bitmap)

        var foundPink = false
        var foundGreen = false
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<(bitmap.pixelsWide / 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.9 else { continue }
                foundPink = foundPink || (color.redComponent - color.greenComponent > 0.4
                    && color.blueComponent - color.greenComponent > 0.1)
                foundGreen = foundGreen || (color.greenComponent - color.redComponent > 0.25
                    && color.greenComponent - color.blueComponent > 0.25)
            }
        }
        XCTAssertTrue(foundPink)
        XCTAssertTrue(foundGreen)
    }
}
