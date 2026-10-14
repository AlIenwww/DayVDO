import AppKit
import Combine
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
    @State private var pagePresentation = SidebarPagePresentation()
    @AppStorage("calendarDisplayMode") private var calendarDisplayMode = CalendarDisplayMode.month.rawValue
    @State private var planningDay = LocalDay(.now)
    @State private var editingItem: TodoItem?
    @State private var editingProject: TodoProject?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchFocusRequest = 0
    @State private var allTodosQuery = ""
    @State private var allTodosFilter = TodoFilterState()
    @State private var calendarFilter = TodoFilterState()
    @State private var calendarToday = LocalDay(.now)
    private let calendarDayClock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var allTodosScrollPosition = ScrollPosition(y: 0)
    @State private var todayHourHeight: CGFloat = 90
    @State private var todayScrollMinute: CGFloat?
    @State private var calendarWeekHourHeight: CGFloat = 90
    @State private var calendarWeekScrollMinute: CGFloat?
    @State private var calendarSelectedDate = Date.now
    @State private var calendarCurrentMonth = Date.now
    @State private var calendarInspectorPresented = false
    @StateObject private var projectExpansionState = ProjectExpansionState()
    @StateObject private var allTodosPresentationCache = AllTodosView.PresentationCache()
    @StateObject private var calendarWeekCache = CalendarWindowCache()
    @StateObject private var calendarWeekPresentationCache = CalendarWeekPresentationCache()
    @StateObject private var calendarWindowCache = CalendarWindowCache()
    @StateObject private var calendarTimelineSession = CalendarTimelineSession()
    @State private var isRecoveryPromptPresented = false
    @State private var isConfirmingEmptyRecovery = false
    @State private var showsLoadingIndicator = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarDestinationList(presentation: pagePresentation) {
                pagePresentation.presentSelection(prepareCalendar: prepareCalendarForEntry)
            }
            // Native List can retain row labels when only the locale changes.
            // Recreate the sidebar, keeping the selected destination in its binding.
            .id(store.settings.language)
            .navigationTitle("DayVDO")
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: L10n.prefersCompactControls ? 210 : 240,
                max: 280
            )
        } detail: {
            Group {
                switch displayedDestination {
                case .today:
                    TodayView(
                        editingItem: $editingItem,
                        selectedDay: $planningDay,
                        hourHeight: $todayHourHeight,
                        timelineScrollMinute: $todayScrollMinute
                    )
                case .all:
                    AllTodosView(
                        editingItem: $editingItem,
                        editingProject: $editingProject,
                        searchFocusRequest: searchFocusRequest,
                        query: $allTodosQuery,
                        filter: $allTodosFilter,
                        scrollPosition: $allTodosScrollPosition,
                        expansionState: projectExpansionState,
                        presentationCache: allTodosPresentationCache
                    )
                case .calendar:
                    CalendarView(
                        editingItem: $editingItem,
                        filter: $calendarFilter,
                        visibility: calendarFilterContext,
                        columnVisibility: $columnVisibility,
                        selectedDate: $calendarSelectedDate,
                        currentMonth: $calendarCurrentMonth,
                        weekHourHeight: $calendarWeekHourHeight,
                        weekScrollMinute: $calendarWeekScrollMinute,
                        isInspectorPresented: $calendarInspectorPresented,
                        windowCache: calendarWindowCache,
                        weekCache: calendarWeekCache,
                        weekPresentationCache: calendarWeekPresentationCache,
                        timelineSession: calendarTimelineSession
                    )
                case .settings:
                    SettingsView()
                }
            }
            .transition(.identity)
            .animation(nil, value: displayedDestination)
            .toolbarBackground(.automatic, for: .windowToolbar)
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
                if displayedDestination == .today {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editingItem = TodoItem(
                                title: "",
                                dueDate: selection == .today ? planningDay.date() : (selection == .calendar ? calendarSelectedDate : nil),
                                priority: store.settings.defaultPriority
                            )
                        } label: {
                            Label(L10n.string("新建待办…"), systemImage: "plus")
                        }
                        .disabled(!store.canModify)
                        .help(L10n.string("新建待办 (⌘N)"))
                    }
                } else if displayedDestination == .all {
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
        .background { SidebarSelectionFeedbackWindow(feedback: pagePresentation.feedback) }
        .onDisappear { pagePresentation.cancelPendingPresentation() }
        .focusedSceneValue(
            \.dayVDOCommandActions,
            DayVDOCommandActions(
                newTodo: {
                    guard store.canModify else { return }
                    editingItem = TodoItem(
                        title: "",
                        dueDate: selection == .today ? planningDay.date() : (selection == .calendar ? calendarSelectedDate : nil),
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
        .onAppear {
            store.undoManager = undoManager
            if case .recoveryRequired = store.persistenceIssue {
                isRecoveryPromptPresented = true
            }
            updateLoadingIndicator()
            refreshCalendarFilterDay()
            sanitizeCalendarFilter()
        }
        .onReceive(calendarDayClock) { _ in refreshCalendarFilterDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshCalendarFilterDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCalendarFilterDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshCalendarFilterDay()
        }
        .onChange(of: store.projects) { _, _ in sanitizeCalendarFilter() }
        .onChange(of: store.tags) { _, _ in sanitizeCalendarFilter() }
        .onChange(of: store.persistenceIssue) { _, issue in
            if case .recoveryRequired = issue {
                isRecoveryPromptPresented = true
            }
        }
        .onChange(of: store.isInitialLoading) { _, _ in updateLoadingIndicator() }
        .task(id: calendarPrewarmTrigger) {
            guard !store.isInitialLoading else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, selection != .calendar else { return }
            prewarmCalendarWindow()
        }
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

    private var selection: SidebarDestination? {
        get { pagePresentation.selection }
        nonmutating set { pagePresentation.selection = newValue }
    }

    private var displayedDestination: SidebarDestination { pagePresentation.displayedDestination }

    private var calendarFilterContext: TodoFilterContext {
        .init(filter: calendarFilter, showCompleted: store.settings.showCompleted, today: calendarToday)
    }

    private func refreshCalendarFilterDay() {
        let today = LocalDay(.now)
        if calendarToday != today { calendarToday = today }
    }

    private func sanitizeCalendarFilter() {
        var updated = calendarFilter
        updated.sanitize(projectIDs: Set(store.projects.map(\.id)), tagIDs: Set(store.tags.map(\.id)))
        if updated != calendarFilter { calendarFilter = updated }
    }

    private var calendarPrewarmTrigger: CalendarPrewarmTrigger {
        CalendarPrewarmTrigger(
            revision: store.contentRevision,
            visibility: calendarFilterContext,
            startsOnMonday: store.settings.startWeekOnMonday,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            mode: calendarDisplayMode,
            firstDay: calendarEntryRequest()?.key.firstDay
        )
    }

    private func prewarmCalendarWindow() {
        _ = prepareCalendarWindow(priority: .utility)
    }

    private func prepareCalendarForEntry() -> CalendarEntryPreparation? {
        prepareCalendarWindow(priority: .userInitiated)
    }

    private func prepareCalendarWindow(priority: TaskPriority) -> CalendarEntryPreparation? {
        guard !store.isInitialLoading, let request = calendarEntryRequest() else { return nil }
        let isWeek = calendarDisplayMode == CalendarDisplayMode.week.rawValue
        let cache = isWeek ? calendarWeekCache : calendarWindowCache
        cache.prepare(request, priority: priority)
        if isWeek {
            _ = calendarWeekPresentationCache.value(
                for: .init(week: request.key.firstDay, revision: store.contentRevision,
                           visibility: calendarFilterContext),
                schedules: store.schedules, preview: nil,
                todo: { store.item(withID: $0) }
            )
        }
        return CalendarEntryPreparation(cache: cache, key: request.key)
    }

    private func calendarEntryRequest() -> CalendarWindowRequest? {
        if calendarDisplayMode == CalendarDisplayMode.week.rawValue {
            let calendar = AppCalendar.make(
                locale: L10n.locale, startsOnMonday: store.settings.startWeekOnMonday
            )
            let week = LocalDay(
                calendar.dateInterval(of: .weekOfYear, for: calendarSelectedDate)?.start
                    ?? calendarSelectedDate,
                timeZone: calendar.timeZone
            )
            return CalendarWindowRequest(
                key: CalendarWindowSnapshot.Key(
                    revision: store.contentRevision, firstDay: week,
                    lastDay: week.adding(days: 6),
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    firstWeekday: calendar.firstWeekday,
                    visibility: calendarFilterContext
                ), items: store.items, tags: store.tags
            )
        } else {
            return monthWindowRequest()
        }
    }

    private func monthWindowRequest() -> CalendarWindowRequest? {
        let calendar = AppCalendar.make(
            locale: L10n.locale,
            startsOnMonday: store.settings.startWeekOnMonday
        )
        let month = calendar.dateInterval(of: .month, for: calendarCurrentMonth)?.start
            ?? calendarCurrentMonth
        let restoredTop = calendarTimelineSession.topWeek.map {
            let date = $0.date(timeZone: calendar.timeZone)
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
        guard let monthWeek = restoredTop ?? CalendarMonthGrid.dates(containing: month, calendar: calendar).first,
              let lastDate = calendar.date(byAdding: .day, value: 41, to: monthWeek) else { return nil }
        let firstDay = LocalDay(monthWeek, timeZone: calendar.timeZone)
        let lastDay = LocalDay(lastDate, timeZone: calendar.timeZone)
        return CalendarWindowRequest(
            key: CalendarWindowSnapshot.Key(
                revision: store.contentRevision,
                firstDay: firstDay,
                lastDay: lastDay,
                timeZoneIdentifier: calendar.timeZone.identifier,
                firstWeekday: calendar.firstWeekday,
                visibility: calendarFilterContext
            ),
            items: store.items,
            tags: store.tags
        )
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

private struct SidebarDestinationList: View {
    @Bindable var presentation: SidebarPagePresentation
    let selectionChanged: () -> Void

    var body: some View {
        List(SidebarDestination.allCases, selection: $presentation.selection) { destination in
            NavigationLink(value: destination) {
                Label(L10n.string(destination.title), systemImage: destination.symbol)
            }
        }
        .listStyle(.sidebar)
        // Keep the first row below the toolbar's fade without overriding
        // the native selection colors or keyboard-focus behavior.
        .padding(.top, 12)
        .onChange(of: presentation.selection) { _, _ in selectionChanged() }
    }
}

private struct CalendarPrewarmTrigger: Hashable {
    var revision: UInt64
    var visibility: TodoFilterContext
    var startsOnMonday: Bool
    var timeZoneIdentifier: String
    var mode: String
    var firstDay: LocalDay?
}
