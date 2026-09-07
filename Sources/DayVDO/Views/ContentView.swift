import AppKit
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
    @Environment(\.undoManager) private var undoManager
    @State private var selection: SidebarDestination? = .today
    @State private var planningDay = LocalDay(.now)
    @State private var editingItem: TodoItem?
    @State private var editingProject: TodoProject?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchFocusRequest = 0
    @State private var allTodosQuery = ""
    @State private var allTodosFilter = AllTodosFilter.all
    @State private var allTodosTagFilter = AllTodosTagFilter.all
    @State private var calendarSelectedDate = Date.now
    @State private var calendarCurrentMonth = Date.now
    @State private var calendarInspectorPresented = false
    @StateObject private var projectExpansionState = ProjectExpansionState()
    @State private var isRecoveryPromptPresented = false
    @State private var isConfirmingEmptyRecovery = false
    @State private var showsLoadingIndicator = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SidebarDestination.allCases, selection: $selection) { destination in
                NavigationLink(value: destination) {
                    Label(L10n.string(destination.title), systemImage: destination.symbol)
                }
            }
            .navigationTitle("DayVDO")
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: L10n.prefersCompactControls ? 210 : 240,
                max: 280
            )
        } detail: {
            Group {
                switch selection ?? .today {
                case .today:
                    TodayView(editingItem: $editingItem, selectedDay: $planningDay)
                case .all:
                    AllTodosView(
                        editingItem: $editingItem,
                        editingProject: $editingProject,
                        searchFocusRequest: searchFocusRequest,
                        query: $allTodosQuery,
                        filter: $allTodosFilter,
                        tagFilter: $allTodosTagFilter,
                        expansionState: projectExpansionState
                    )
                case .calendar:
                    CalendarView(
                        editingItem: $editingItem,
                        columnVisibility: $columnVisibility,
                        selectedDate: $calendarSelectedDate,
                        currentMonth: $calendarCurrentMonth,
                        isInspectorPresented: $calendarInspectorPresented
                    )
                case .settings:
                    SettingsView()
                }
            }
            .disabled(!store.canModify)
            .overlay {
                if showsLoadingIndicator && store.isInitialLoading {
                    ProgressView(L10n.string("正在载入待办…"))
                        .controlSize(.small)
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbar {
                if selection == .today {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editingItem = TodoItem(
                                title: "",
                                dueDate: selection == .today ? planningDay.date() : nil,
                                priority: store.settings.defaultPriority
                            )
                        } label: {
                            Label(L10n.string("新建待办…"), systemImage: "plus")
                        }
                        .disabled(!store.canModify)
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
                        .disabled(!store.canModify)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(
            \.dayVDOCommandActions,
            DayVDOCommandActions(
                newTodo: {
                    guard store.canModify else { return }
                    editingItem = TodoItem(
                        title: "",
                        dueDate: selection == .today ? planningDay.date() : nil,
                        priority: store.settings.defaultPriority
                    )
                },
                newProject: {
                    guard store.canModify else { return }
                    selection = .all
                    editingProject = TodoProject(title: "")
                },
                focusSearch: {
                    selection = .all
                    searchFocusRequest += 1
                },
                navigate: { destination in selection = destination }
            )
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            persistenceBanner
        }
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
        .onChange(of: selection) { old, new in
            if new == .today && old != .today { planningDay = LocalDay(.now) }
        }
        .onAppear {
            store.undoManager = undoManager
            if case .recoveryRequired = store.persistenceIssue {
                isRecoveryPromptPresented = true
            }
            updateLoadingIndicator()
        }
        .onChange(of: store.persistenceIssue) { _, issue in
            if case .recoveryRequired = issue {
                isRecoveryPromptPresented = true
            }
        }
        .onChange(of: store.isInitialLoading) { _, _ in updateLoadingIndicator() }
        .alert(L10n.string("无法读取待办数据"), isPresented: $isRecoveryPromptPresented) {
            if case .recoveryRequired(let hasBackup, _) = store.persistenceIssue, hasBackup {
                Button(L10n.string("恢复最近备份")) { store.restoreLatestBackup() }
            }
            Button(L10n.string("以空白数据继续"), role: .destructive) {
                isConfirmingEmptyRecovery = true
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("主数据文件已损坏。DayVDO 已保留原文件；取消后应用将保持只读。"))
        }
        .alert(L10n.string("确认以空白数据继续？"), isPresented: $isConfirmingEmptyRecovery) {
            Button(L10n.string("以空白数据继续"), role: .destructive) {
                store.continueWithEmptyData()
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("现有损坏文件会被保留，但当前内容将替换为空白数据。"))
        }
    }

    @ViewBuilder
    private var persistenceBanner: some View {
        if let issue = store.persistenceIssue {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(persistenceMessage(issue))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if case .saveFailed = issue {
                    Button(L10n.string("重试")) { store.retryPersistence() }
                } else if case .recoveryFailed = issue {
                    Button(L10n.string("重试")) { store.retryPersistence() }
                } else {
                    Button(L10n.string("处理…")) { isRecoveryPromptPresented = true }
                }
                Button(L10n.string("打开数据文件夹")) {
                    NSWorkspace.shared.open(store.dataDirectoryURL)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func persistenceMessage(_ issue: TodoStore.PersistenceIssue) -> String {
        switch issue {
        case .recoveryRequired(_, let backupDate):
            if let backupDate {
                return L10n.format(
                    "数据需要恢复；最近备份：%@。处理前应用保持只读。",
                    backupDate.formatted(date: .abbreviated, time: .shortened)
                )
            }
            return L10n.string("数据需要恢复；处理前应用保持只读。")
        case .recoveryFailed(_, let message):
            return L10n.format("无法完成数据恢复：%@", message)
        case .saveFailed(let message):
            return L10n.format("无法保存更改：%@", message)
        }
    }

    private func updateLoadingIndicator() {
        guard store.isInitialLoading else {
            showsLoadingIndicator = false
            return
        }
        showsLoadingIndicator = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if store.isInitialLoading {
                showsLoadingIndicator = true
            }
        }
    }
}
