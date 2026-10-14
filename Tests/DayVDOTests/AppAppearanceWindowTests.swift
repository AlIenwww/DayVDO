import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class AppAppearanceWindowTests: XCTestCase {
    func testDarkAndLightReturnToSystemAcrossExistingAndNewWindows() async throws {
        let app = NSApplication.shared
        let previous = app.appearance
        defer { app.appearance = previous }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDO-Appearance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("todos.json"))
        let delegate = AppDelegate()
        store.settings.appearance = .dark
        delegate.store = store
        XCTAssertEqual(app.appearance?.name, .darkAqua,
                       "Binding must apply the already loaded appearance immediately")

        let mainProbe = AppearanceProbe()
        let settingsProbe = AppearanceProbe()
        let main = makeWindow(ContentView().environmentObject(store), probe: mainProbe)
        let settings = makeWindow(SettingsView().environmentObject(store), probe: settingsProbe)
        defer {
            for window in [main, settings] { window.contentView = nil; window.close() }
            delegate.store = nil
        }
        for mode in [AppearanceMode.dark, .automatic, .light, .automatic, .dark, .light, .dark, .automatic] {
            store.settings.appearance = mode
            try await settle([main, settings])
            let expected: NSAppearance.Name
            switch mode {
            case .dark: expected = .darkAqua
            case .light: expected = .aqua
            case .automatic:
                XCTAssertNil(app.appearance, "Automatic must release the application override")
                expected = try XCTUnwrap(app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
            }
            for (window, probe) in [(main, mainProbe), (settings, settingsProbe)] {
                XCTAssertNil(window.appearance, "Windows must inherit the application appearance")
                XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
                XCTAssertEqual(window.contentView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
                XCTAssertEqual(probe.scheme, expected == .darkAqua ? .dark : .light,
                               "SwiftUI content must agree with the native window after \(mode)")
            }
        }
        let newProbe = AppearanceProbe()
        let newWindow = makeWindow(Text("New window"), probe: newProbe)
        defer { newWindow.contentView = nil; newWindow.close() }
        try await settle([newWindow])
        XCTAssertEqual(newProbe.scheme, mainProbe.scheme,
                       "Windows opened after returning to automatic must inherit the same scheme")
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
    }

    private func makeWindow<Content: View>(_ content: Content, probe: AppearanceProbe) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content.overlay { SchemeObserver(probe: probe) })
        return window
    }

    private func settle(_ windows: [NSWindow]) async throws {
        for _ in 0..<12 {
            for window in windows { window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class AppearanceProbe {
    var scheme: ColorScheme?
}

private struct SchemeObserver: View {
    @Environment(\.colorScheme) private var scheme
    let probe: AppearanceProbe

    var body: some View {
        Color.clear.allowsHitTesting(false)
            .onChange(of: scheme, initial: true) { _, value in probe.scheme = value }
    }
}
