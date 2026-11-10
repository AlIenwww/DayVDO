import AppKit
import Combine
import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today
    case calendar
    case all
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
    @EnvironmentObject private var navigation: AppNavigation
    private let commandsEnabled: Bool
    private let practiceGuide: OnboardingSession?

    init(initialDestination: SidebarDestination = .today, commandsEnabled: Bool = true,
         practiceGuide: OnboardingSession? = nil) {
        self.commandsEnabled = commandsEnabled
        self.practiceGuide = practiceGuide
        _pagePresentation = State(initialValue: SidebarPagePresentation(initialDestination: initialDestination))
        if let day = practiceGuide?.progress.day {
            _planningDay = State(initialValue: day)
            _calendarToday = State(initialValue: day)
            _calendarSelectedDate = State(initialValue: day.date())
            _calendarCurrentMonth = State(initialValue: day.date())
            _todayScrollMinute = State(initialValue: 540)
        }
    }
    @State private var pagePresentation = SidebarPagePresentation()
    @AppStorage("calendarDisplayMode") private var storedCalendarMode = CalendarDisplayMode.month.rawValue
    @State private var practiceCalendarMode = CalendarDisplayMode.month.rawValue
    @State private var planningDay = LocalDay(.now)
    @State private var editingItem: TodoItem?
    @State private var editingProject: TodoProject?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchFocusRequest = 0
    @State private var allTodosQuery = ""
    @State private var allTodosFilter = TodoFilterState()
    @State private var calendarFilter = TodoFilterState()
    @State private var calendarToday = LocalDay(.now)
    @State private var allTodosScrollPosition = ScrollPosition(y: 0)
    @State private var todayHourHeight: CGFloat = 90
    @State private var todayScrollMinute: CGFloat?
    @State private var calendarWeekPosition = CalendarWeekViewportPosition()
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
    @State private var practiceScheduleEditor: DaySchedule?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarDestinationList(selection: Binding(get: { selection }, set: selectDestination)) {
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
                        timelineScrollMinute: $todayScrollMinute,
                        isPractice: practiceGuide != nil
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
                        weekPosition: calendarWeekPosition,
                        isInspectorPresented: $calendarInspectorPresented,
                        windowCache: calendarWindowCache,
                        weekCache: calendarWeekCache,
                        weekPresentationCache: calendarWeekPresentationCache,
                        timelineSession: calendarTimelineSession,
                        practiceDisplayMode: practiceGuide == nil ? nil : $practiceCalendarMode
                    )
                case .settings:
                    SettingsView()
                }
            }
            .transition(.identity)
            .animation(nil, value: displayedDestination)
            .toolbarBackground(.automatic, for: .windowToolbar)
            .disabled(!store.canModify && displayedDestination != .settings)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let practiceGuide {
                    GuidePracticeBar(guide: practiceGuide) { practiceScheduleEditor = $0 }
                }
            }
            .overlay {
                if showsLoadingIndicator && store.isInitialLoading {
                    ProgressView(L10n.string("正在载入待办…"))
                        .controlSize(.small)
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbar {
                if let practiceGuide {
                    ToolbarItem {
                        GuidePracticeMenu(guide: practiceGuide)
                    }
                }
                if displayedDestination == .today {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: newTodo) {
                            Label(L10n.string("新建待办…"), systemImage: "plus")
                        }
                        .disabled(!store.canModify)
                        .help(L10n.string("新建待办") + " (" + store.settings.shortcut(for: .newTodo).display + ")")
                    }
                } else if displayedDestination == .all {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(L10n.string("新建待办…"), systemImage: "checkmark.circle") {
                                newTodo()
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
            commandsEnabled ? DayVDOCommandActions(
                newTodo: newTodo,
                newProject: {
                    guard store.canModify else { return }
                    selection = .all
                    editingProject = TodoProject(title: "")
                },
                focusSearch: {
                    selection = .all
                    searchFocusRequest += 1
                },
                navigate: { destination in selectDestination(destination) }
            ) : nil
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
        .sheet(item: $practiceScheduleEditor) { schedule in
            ScheduleEditorView(schedule: schedule, isCreating: store.schedule(withID: schedule.id) == nil,
                close: { practiceScheduleEditor = nil },
                editTodo: { practiceScheduleEditor = nil; editingItem = $0 })
        }
        .onChange(of: pagePresentation.selection) { _, destination in
            if practiceGuide == nil { navigation.currentDestination = destination ?? .today }
        }
        .onChange(of: navigation.requestID) { _, _ in
            if practiceGuide == nil, let destination = navigation.requestedDestination { selection = destination }
        }
        .onChange(of: practiceGuide?.progress.step) { _, step in
            if let step, step != .discover { selection = .today }
        }
        .onAppear {
            store.undoManager = practiceGuide?.undoManager ?? navigation.undoManager
            if case .recoveryRequired = store.persistenceIssue {
                isRecoveryPromptPresented = true
            }
            refreshCalendarFilterDay()
            sanitizeCalendarFilter()
        }
        .onReceive(AppClock.refreshes) { _ in refreshCalendarFilterDay() }
        .onChange(of: store.projects) { _, _ in sanitizeCalendarFilter() }
        .onChange(of: store.tags) { _, _ in sanitizeCalendarFilter() }
        .onChange(of: store.persistenceIssue) { _, issue in
            if case .recoveryRequired = issue {
                isRecoveryPromptPresented = true
            }
        }
        .task(id: store.isInitialLoading) {
            showsLoadingIndicator = false
            guard store.isInitialLoading else { return }
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            showsLoadingIndicator = store.isInitialLoading
        }
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

    private var calendarDisplayMode: String {
        practiceGuide == nil ? storedCalendarMode : practiceCalendarMode
    }

    private func selectDestination(_ destination: SidebarDestination?) {
        if practiceGuide != nil, destination == .settings {
            navigation.navigate(to: .settings)
        } else {
            selection = destination
        }
    }

    private func newTodo() {
        guard store.canModify else { return }
        let dueDate: Date? = switch selection {
        case .today: planningDay.date()
        case .calendar: calendarSelectedDate
        default: nil
        }
        var item = store.newItem(dueDate: dueDate)
        if let practiceGuide, practiceGuide.progress.step == .create, practiceGuide.targetTodo == nil {
            item.dueDate = practiceGuide.progress.day.date()
            item.title = L10n.string("阅读 20 分钟")
            item.estimatedMinutes = 20
        }
        editingItem = item
    }

    private var calendarFilterContext: TodoFilterContext {
        .init(filter: calendarFilter, showCompleted: store.settings.showCompleted,
              today: calendarToday, startsOnMonday: store.settings.startWeekOnMonday)
    }

    private func refreshCalendarFilterDay() {
        let today = practiceGuide?.progress.day ?? LocalDay(.now)
        if calendarToday != today { calendarToday = today }
    }

    private func sanitizeCalendarFilter() {
        var updated = calendarFilter
        updated.sanitize(projectIDs: Set(store.projects.map(\.id)), tagIDs: Set(store.tags.map(\.id)))
        if updated != calendarFilter { calendarFilter = updated }
    }

    private var calendarPrewarmTrigger: CalendarPrewarmTrigger {
        CalendarPrewarmTrigger(
            revision: store.dateContentRevision,
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
                for: .init(week: request.key.firstDay.adding(days: 21), revision: store.timelineContentRevision,
                           visibility: calendarFilterContext),
                schedulesOnDay: { store.schedules(on: $0) }, preview: nil,
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
                    revision: store.dateContentRevision, firstDay: week.adding(days: -21),
                    lastDay: week.adding(days: 27),
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
                revision: store.dateContentRevision,
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


}

private struct SidebarDestinationList: View {
    @Binding var selection: SidebarDestination?
    let selectionChanged: () -> Void

    var body: some View {
        List(SidebarDestination.allCases, selection: $selection) { destination in
            NavigationLink(value: destination) {
                Label(L10n.string(destination.title), systemImage: destination.symbol)
            }
        }
        .listStyle(.sidebar)
        // Keep the first row below the toolbar's fade without overriding
        // the native selection colors or keyboard-focus behavior.
        .padding(.top, 12)
        .onChange(of: selection) { _, _ in selectionChanged() }
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
