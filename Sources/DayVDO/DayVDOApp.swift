import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct DayVDOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TodoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(preferredColorScheme)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("新建待办")) {
                    NotificationCenter.default.post(name: .newTodoRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(preferredColorScheme)
                .frame(width: 520, height: 480)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Notification.Name {
    static let newTodoRequested = Notification.Name("DayVDO.newTodoRequested")
}
