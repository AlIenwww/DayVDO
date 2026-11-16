import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class Settings090WindowTests: XCTestCase {
    func testSettingsResizeAndLocalizeWithoutHorizontalScrolling() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-Settings-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory); L10n.configure(language: .system) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let navigation = AppNavigation(store: store)
        let host = NSHostingView(rootView: SettingsView().environmentObject(store).environmentObject(navigation)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.sizingOptions = []
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        for language in [AppLanguage.simplifiedChinese, .english, .german] {
            store.settings.language = language
            for size in [NSSize(width: 820, height: 650), NSSize(width: 540, height: 468)] {
                window.setContentSize(size)
                for category in SettingsCategory.allCases {
                    navigation.settingsCategory = category
                    try await settle(host)
                    XCTAssertEqual(host.frame.width, size.width, accuracy: 1)
                    XCTAssertEqual(host.frame.height, size.height, accuracy: 1)
                    for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) {
                        if let document = scroll.documentView {
                            XCTAssertLessThanOrEqual(document.frame.width, scroll.contentView.bounds.width + 2,
                                "Horizontal overflow: \(language) \(category) \(size)")
                        }
                    }
                    if [.general, .animation, .planning, .help, .about].contains(category) {
                        try capture(host, name: "settings-\(language.rawValue)-\(category.rawValue)-\(Int(size.width))")
                    }
                }
            }
        }
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    func testGuideFitsMinimumWindowAndRestoresPracticeState() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-GuideWindow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory); L10n.configure(language: .system) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        store.settings.language = .simplifiedChinese
        let navigation = AppNavigation(store: store)
        let guide = navigation.guide
        let host = NSHostingView(rootView: AppRootView(store: store, navigation: navigation, guide: guide))
        host.sizingOptions = []
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        // The split view can impose a larger native minimum than requested.
        window.setContentSize(NSSize(width: 760, height: 468))
        try await settle(host)
        let mainWindowSize = host.bounds.size
        XCTAssertEqual(mainWindowSize.width, 760, accuracy: 1)
        guide.open()
        try await settle(host)
        try capture(host, name: "guide-welcome-minimum")
        guide.advance(); guide.advance()
        let practice = try XCTUnwrap(guide.practice)
        var item = practice.newItem(dueDate: guide.progress.day.date())
        item.title = "阅读 20 分钟"; item.estimatedMinutes = 20
        practice.upsert(item)
        guide.advance()
        try await settle(host)
        window.setContentSize(mainWindowSize)
        try await settle(host)
        try capture(host, name: "guide-schedule-minimum")
        XCTAssertEqual(host.bounds.width, mainWindowSize.width, accuracy: 1)
        XCTAssertEqual(host.bounds.height, mainWindowSize.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(descendants(host).compactMap { $0 as? NSScrollView }.count, 2,
                                    "Practice keeps the task list visible alongside the timeline")
        XCTAssertTrue(guide.close())
        XCTAssertEqual(navigation.currentDestination, .today)
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = SettingsTestWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 650),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(NSSize(width: 820, height: 650))
        window.makeKeyAndOrderFront(nil)
        return window
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func settle(_ host: NSView) async throws {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    private func capture(_ host: NSView, name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["DAYVDO_CAPTURE_DIR"] else { return }
        let url = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(name + ".png"))
    }
}

// A locked/offscreen desktop can report a zero-height visible screen. Keep the
// requested content size so these tests actually exercise the intended viewport.
@MainActor
private final class SettingsTestWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
