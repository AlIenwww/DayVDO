import SwiftUI
import AppKit
import Combine

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
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var store: TodoStore

    private func navigate(_ destination: SidebarDestination) {
        if destination != .settings, let actions {
            actions.navigate(destination)
        } else {
            navigation.navigate(to: destination)
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Commands {
        PracticeUndoCommands(guide: navigation.guide, formalUndoManager: navigation.undoManager,
                             settings: store.settings)
        CommandGroup(replacing: .appSettings) {
            Button(L10n.string("设置…")) { navigate(.settings) }
                .keyboardShortcut(store.settings.shortcut(for: .settings).keyboardShortcut)
        }
        CommandGroup(replacing: .newItem) {
            Button(L10n.string("新建待办")) { actions?.newTodo() }
                .keyboardShortcut(store.settings.shortcut(for: .newTodo).keyboardShortcut)
                .disabled(actions == nil)

            Button(L10n.string("新建大项目…")) { actions?.newProject() }
                .keyboardShortcut(store.settings.shortcut(for: .newProject).keyboardShortcut)
                .disabled(actions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button(L10n.string("搜索待办")) { actions?.focusSearch() }
                .keyboardShortcut(store.settings.shortcut(for: .search).keyboardShortcut)
                .disabled(actions == nil)
        }
        CommandGroup(after: .help) {
            Button(L10n.string("使用教程")) {
                navigation.settingsCategory = .help
                navigate(.settings)
            }
        }
        CommandGroup(after: .sidebar) {
            Button(L10n.string("今日待办")) { navigate(.today) }
                .keyboardShortcut(store.settings.shortcut(for: .today).keyboardShortcut)
            Button(L10n.string("日历")) { navigate(.calendar) }
                .keyboardShortcut(store.settings.shortcut(for: .calendar).keyboardShortcut)
            Button(L10n.string("总待办")) { navigate(.all) }
                .keyboardShortcut(store.settings.shortcut(for: .all).keyboardShortcut)
            Button(L10n.string("设置")) { navigate(.settings) }
                .keyboardShortcut(store.settings.shortcut(for: .settingsAlternate).keyboardShortcut)
        }
    }
}

/// Do not let the formal window's undo history receive an undo while practicing.
/// Native text fields retain their own text undo; all other practice actions use the isolated manager.
private struct PracticeUndoCommands: Commands {
    @StateObject private var undoChanges = UndoMenuChanges()
    @ObservedObject var guide: OnboardingSession
    let formalUndoManager: UndoManager
    let settings: AppSettings
    private var manager: UndoManager? {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { return text.undoManager }
        return guide.isPresented ? guide.undoManager : formalUndoManager
    }
    var body: some Commands {
        let _ = undoChanges.revision
        CommandGroup(replacing: .undoRedo) {
            Button(L10n.string("撤销")) { manager?.undo() }
                .keyboardShortcut(settings.shortcut(for: .undo).keyboardShortcut)
                .disabled(manager?.canUndo != true)
            Button(L10n.string("重做")) { manager?.redo() }
                .keyboardShortcut(settings.shortcut(for: .redo).keyboardShortcut)
                .disabled(manager?.canRedo != true)
        }
    }
}

@MainActor
private final class UndoMenuChanges: ObservableObject {
    @Published var revision = 0
    private var subscription: AnyCancellable?
    init() {
        subscription = Publishers.MergeMany([
            Notification.Name.NSUndoManagerDidCloseUndoGroup, Notification.Name.NSUndoManagerDidUndoChange,
            Notification.Name.NSUndoManagerDidRedoChange, NSWindow.didBecomeKeyNotification
        ].map { NotificationCenter.default.publisher(for: $0) })
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.revision += 1 }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: TodoStore? {
        didSet {
            appearanceSubscription = store?.$settings
                .map(\.appearance)
                .removeDuplicates()
                .sink { AppAppearance.apply($0) }
        }
    }
    private var appearanceSubscription: AnyCancellable?
    private var legacyModalObservation: AnyCancellable?
    weak var guide: OnboardingSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if #unavailable(macOS 15.4) {
            // Earlier systems expose the same policy on the native window.
            legacyModalObservation = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification).sink {
                guard let window = $0.object as? NSWindow, window.sheetParent != nil else { return }
                window.preventsApplicationTerminationWhenModal = false
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let guide, guide.isPresented, !guide.needsReset, !guide.persist() {
            let alert = NSAlert()
            alert.messageText = guide.error ?? ""
            alert.addButton(withTitle: L10n.string("取消"))
            alert.addButton(withTitle: L10n.string("放弃未保存的练习并退出"))
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            guide.discardAndClose()
        }
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
    @StateObject private var navigation: AppNavigation

    init() {
        let initialStore = Self.makeStore()
        _store = StateObject(wrappedValue: initialStore)
        let initialNavigation = AppNavigation(store: initialStore)
        _navigation = StateObject(wrappedValue: initialNavigation)
        appDelegate.store = initialStore
        appDelegate.guide = initialNavigation.guide
    }

    private static func makeStore() -> TodoStore {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let isolatedURL = AppDataLocation.isolatedTestingURL(
               bundleIdentifier: Bundle.main.bundleIdentifier,
               enabled: Bundle.main.object(forInfoDictionaryKey: "DayVDOIsolatedTesting") as? Bool == true,
               applicationSupport: support
           ) {
            return TodoStore(fileURL: isolatedURL)
        }
        #if DEBUG
        // A test-only bundle may opt into an explicit data file. This remains
        // isolated even when a UI automation tool relaunches it without its environment.
        if let path = Bundle.main.object(forInfoDictionaryKey: "DayVDOTestingDataPath") as? String {
            return TodoStore(fileURL: URL(fileURLWithPath: path))
        }
        #endif
        // Finish loading arrangements and their task data before SwiftUI
        // creates the first window, so its first frame contains the saved plan.
        return TodoStore(loadsAsynchronously: false)
    }

    var body: some Scene {
        Window("DayVDO", id: "main") {
            AppRootView(store: store, navigation: navigation, guide: navigation.guide)
                .background { IconOnlyWindowToolbar() }
                .environmentObject(store)
                .environment(\.locale, store.settings.language.locale)
                .accentColor(store.settings.themeColor?.color)
                .tint(store.settings.themeColor?.color)
                .frame(minWidth: 760, minHeight: 468)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            DayVDOCommands(navigation: navigation, store: store)
        }

    }
}
