import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today
    case all
    case calendar
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日待办"
        case .all: "总待办"
        case .calendar: "日历"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .all: "checklist"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var selection: SidebarDestination? = .today
    @State private var editingItem: TodoItem?
    @State private var editingProject: TodoProject?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SidebarDestination.allCases, selection: $selection) { destination in
                NavigationLink(value: destination) {
                    Label(L10n.string(destination.title), systemImage: destination.symbol)
                }
            }
            .navigationTitle(L10n.string("日迹"))
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: L10n.prefersCompactControls ? 210 : 240,
                max: 280
            )
        } detail: {
            Group {
                switch selection ?? .today {
                case .today:
                    TodayView(editingItem: $editingItem)
                case .all:
                    AllTodosView(
                        editingItem: $editingItem,
                        editingProject: $editingProject
                    )
                case .calendar:
                    CalendarView(
                        editingItem: $editingItem,
                        columnVisibility: $columnVisibility
                    )
                case .settings:
                    SettingsView()
                }
            }
            .toolbar {
                if selection == .today {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editingItem = TodoItem(
                                title: "",
                                dueDate: selection == .today ? .now : nil,
                                priority: store.settings.defaultPriority
                            )
                        } label: {
                            Label(L10n.string("新建待办…"), systemImage: "plus")
                        }
                        .help(L10n.string("新建待办 (⌘N)"))
                    }
                } else if selection == .all {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(L10n.string("新建待办…"), systemImage: "checkmark.circle") {
                                editingItem = TodoItem(
                                    title: "",
                                    priority: store.settings.defaultPriority
                                )
                            }
                            Button(L10n.string("新建大项目…"), systemImage: "folder.badge.plus") {
                                editingProject = TodoProject(title: "")
                            }
                        } label: {
                            Label(L10n.string("新建"), systemImage: "plus")
                        }
                        .menuIndicator(.hidden)
                        .help(L10n.string("新建待办或大项目"))
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $editingItem) { item in
            TodoEditorView(
                item: item,
                isEditing: store.items.contains { $0.id == item.id }
            ) { store.upsert($0) }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(
                project: project,
                isEditing: store.projects.contains { $0.id == project.id }
            ) { store.upsertProject($0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTodoRequested)) { _ in
            editingItem = TodoItem(
                title: "",
                dueDate: selection == .today ? .now : nil,
                priority: store.settings.defaultPriority
            )
        }
    }
}
