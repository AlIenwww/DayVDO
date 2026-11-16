import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class Settings091PreviewTests: XCTestCase {
    func testIllustrationsRenderInBothAppearances() async throws {
        _ = NSApplication.shared
        defer { L10n.configure(language: .system) }
        L10n.configure(language: .simplifiedChinese)
        for scheme in [ColorScheme.light, .dark] {
            let gallery = VStack(spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(AppAnimationEffect.allCases) { effect in
                        VStack(alignment: .leading, spacing: 5) {
                            SettingsIllustration(scene: .animation(effect), progress: 0.7)
                            Text(L10n.string(effect.title)).font(.caption)
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(GlossaryTerm.allCases) { term in
                        VStack {
                            SettingsIllustration(scene: .concept(term))
                            Text(L10n.string(term.title)).font(.caption)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 900)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: gallery)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1180),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
            }
            try capture(host, name: "illustrations-\(scheme)")
            XCTAssertEqual(host.bounds.width, 900, accuracy: 1)
            window.contentView = nil
            window.close()
        }
    }

    func testDisabledEffectsLeaveSettingsAndUserDataUnchanged() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-Preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory); L10n.configure(language: .system) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        while store.isInitialLoading { try await Task.sleep(for: .milliseconds(20)) }
        store.settings.disabledAnimations = Set(AppAnimationEffect.allCases)
        let settings = store.settings
        let host = NSHostingView(rootView: AnimationSettingsPreview()
            .environmentObject(store)
            .frame(width: 440).padding(20))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 850),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        try capture(host, name: "animations-disabled")
        XCTAssertEqual(store.settings, settings)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.schedules.isEmpty)
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func capture(_ host: NSView, name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["DAYVDO_CAPTURE_DIR"] else { return }
        let url = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: url.appendingPathComponent(name + ".png"))
    }
}
