import SwiftUI
import AppKit

struct DayVDOCommandActions {
    let newTodo: () -> Void
    let newProject: () -> Void
    let focusSearch: () -> Void
    let navigate: (SidebarDestination) -> Void
}

private struct DayVDOCommandActionsKey: FocusedValueKey {
    typealias Value = DayVDOCommandActions
}

extension FocusedValues {
    var dayVDOCommandActions: DayVDOCommandActions? {
        get { self[DayVDOCommandActionsKey.self] }
        set { self[DayVDOCommandActionsKey.self] = newValue }
    }
}

private struct DayVDOCommands: Commands {
    @FocusedValue(\.dayVDOCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.string("新建待办")) { actions?.newTodo() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)

            Button(L10n.string("新建大项目…")) { actions?.newProject() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button(L10n.string("搜索待办")) { actions?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(L10n.string("今日待办")) { actions?.navigate(.today) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(actions == nil)
            Button(L10n.string("总待办")) { actions?.navigate(.all) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(actions == nil)
            Button(L10n.string("日历")) { actions?.navigate(.calendar) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(actions == nil)
            Button(L10n.string("设置")) { actions?.navigate(.settings) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: TodoStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.hasPendingPersistence else { return .terminateNow }
        Task {
            let didSave = await store.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: didSave)
        }
        return .terminateLater
    }
}

@main
struct DayVDOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: TodoStore

    init() {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let isolatedURL = AppDataLocation.isolatedTestingURL(
               bundleIdentifier: Bundle.main.bundleIdentifier,
               enabled: Bundle.main.object(forInfoDictionaryKey: "DayVDOIsolatedTesting") as? Bool == true,
               applicationSupport: support
           ) {
            _store = StateObject(wrappedValue: TodoStore(fileURL: isolatedURL))
            return
        }
        #if DEBUG
        // A test-only bundle may opt into an explicit data file. This remains
        // isolated even when a UI automation tool relaunches it without its environment.
        if let path = Bundle.main.object(forInfoDictionaryKey: "DayVDOTestingDataPath") as? String {
            _store = StateObject(wrappedValue: TodoStore(fileURL: URL(fileURLWithPath: path)))
            return
        }
        #endif
        _store = StateObject(wrappedValue: TodoStore())
    }

    var body: some Scene {
        Window("DayVDO", id: "main") {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(preferredColorScheme)
                .frame(minWidth: 760, minHeight: 468)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            DayVDOCommands()
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
