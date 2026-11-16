import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, animation, planning, calendar, shortcuts, help, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "通用"
        case .animation: "动画"
        case .planning: "待办与安排"
        case .calendar: "日历"
        case .shortcuts: "快捷键"
        case .help: "帮助"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .animation: "play.rectangle"
        case .planning: "checklist"
        case .calendar: "calendar"
        case .shortcuts: "keyboard"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    var currentDestination: SidebarDestination
    @Published var settingsCategory = SettingsCategory.general
    @Published private(set) var requestID = 0
    private(set) var requestedDestination: SidebarDestination?
    let undoManager = UndoManager()
    let guide: OnboardingSession

    init(store: TodoStore) {
        currentDestination = store.settings.startupPage.destination
        guide = OnboardingSession(formal: store)
    }

    func navigate(to destination: SidebarDestination) {
        if guide.isPresented, !guide.close() { return }
        currentDestination = destination
        requestedDestination = destination
        requestID += 1
    }
}
