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

@MainActor @Observable
final class WorkspaceBrowsingState {
    var planningDay = LocalDay(.now)
    var columnVisibility: NavigationSplitViewVisibility = .all
    var allTodosQuery = ""
    var allTodosFilter = TodoFilterState()
    var calendarFilter = TodoFilterState()
    var allTodosScrollPosition = ScrollPosition(y: 0)
    var todayHourHeight: CGFloat = 90
    var todayScrollMinute: CGFloat?
    let calendarWeekPosition = CalendarWeekViewportPosition()
    var calendarSelectedDate = Date.now
    var calendarCurrentMonth = Date.now
    var calendarInspectorPresented = false
    let projectExpansionState = ProjectExpansionState()
}

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var browsing: WorkspaceBrowsingState
    private let commandsEnabled: Bool
    private let practiceGuide: OnboardingSession?

    init(initialDestination: SidebarDestination = .today, commandsEnabled: Bool = true,
         practiceGuide: OnboardingSession? = nil, browsingState: WorkspaceBrowsingState? = nil) {
        let initial = browsingState ?? WorkspaceBrowsingState()
        _browsing = State(initialValue: initial)
        self.commandsEnabled = commandsEnabled
        self.practiceGuide = practiceGuide
        _pagePresentation = State(initialValue: SidebarPagePresentation(initialDestination: initialDestination))
        if let day = practiceGuide?.progress.day {
            initial.planningDay = day
            _calendarToday = State(initialValue: day)
            initial.calendarSelectedDate = day.date()
            initial.calendarCurrentMonth = day.date()
            let wantsWeek = practiceGuide?.progress.step == .undoDate
            _practiceCalendarMode = State(initialValue: wantsWeek ? CalendarDisplayMode.week.rawValue : CalendarDisplayMode.month.rawValue)
            if let guide = practiceGuide {
                if let block = guide.targetSchedule {
                    initial.calendarWeekPosition.scrollMinute = CGFloat(max(0, block.startMinute - 30))
                }
                if guide.progress.step == .clearFilter, let id = guide.progress.tagID {
                    initial.calendarFilter.tagIDs = [id]
                }
                if guide.progress.step == .seeDates, let start = guide.targetTodo?.startDay {
                    initial.calendarSelectedDate = start.date()
                    initial.calendarCurrentMonth = start.date()
                }
            }
            initial.todayScrollMinute = 540
        }
    }
    @State private var pagePresentation = SidebarPagePresentation()
    @AppStorage("calendarDisplayMode") private var storedCalendarMode = CalendarDisplayMode.month.rawValue
    @State private var practiceCalendarMode = CalendarDisplayMode.month.rawValue
    @State private var editingItem: TodoItem?
    @State private var editingProject: TodoProject?
    @State private var searchFocusRequest = 0
    @State private var calendarToday = LocalDay(.now)
    @StateObject private var allTodosPresentationCache = AllTodosView.PresentationCache()
    @StateObject private var calendarWeekCache = CalendarWindowCache()
    @StateObject private var calendarWeekPresentationCache = CalendarWeekPresentationCache()
    @StateObject private var calendarWindowCache = CalendarWindowCache()
    @StateObject private var calendarTimelineSession = CalendarTimelineSession()
    @State private var isRecoveryPromptPresented = false
    @State private var isConfirmingEmptyRecovery = false
    @State private var showsLoadingIndicator = false

    private var workspace: some View {
        NavigationSplitView(columnVisibility: $browsing.columnVisibility) {
            SidebarDestinationList(
                selection: Binding(get: { selection }, set: selectDestination),
                themeColor: store.settings.themeColor
            ) {
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
                        selectedDay: $browsing.planningDay,
                        hourHeight: $browsing.todayHourHeight,
                        timelineScrollMinute: $browsing.todayScrollMinute,
                        isPractice: practiceGuide != nil
                    )
                case .all:
                    AllTodosView(
                        editingItem: $editingItem,
                        editingProject: $editingProject,
                        searchFocusRequest: searchFocusRequest,
                        query: $browsing.allTodosQuery,
                        filter: $browsing.allTodosFilter,
                        scrollPosition: $browsing.allTodosScrollPosition,
                        expansionState: browsing.projectExpansionState,
                        presentationCache: allTodosPresentationCache
                    )
                case .calendar:
                    CalendarView(
                        editingItem: $editingItem,
                        filter: $browsing.calendarFilter,
                        visibility: calendarFilterContext,
                        columnVisibility: $browsing.columnVisibility,
                        selectedDate: $browsing.calendarSelectedDate,
                        currentMonth: $browsing.calendarCurrentMonth,
                        weekPosition: browsing.calendarWeekPosition,
                        isInspectorPresented: $browsing.calendarInspectorPresented,
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
                        .guideTarget(.add)
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
        .overlay {
            if let practiceGuide, editingItem == nil, editingProject == nil {
                PracticeHint(guide: practiceGuide, page: displayedDestination)
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
        .sheetAllowingAppTermination(item: $editingItem) { item in
            TodoEditorView(
                item: item,
                isEditing: store.items.contains { $0.id == item.id }
            ) { store.upsert($0) }
        }
        .sheetAllowingAppTermination(item: $editingProject) { project in
            ProjectEditorView(
                project: project,
                isEditing: store.projects.contains { $0.id == project.id }
            ) { store.upsertProject($0) }
        }
    }

    private var routedWorkspace: some View {
        workspace
        .onChange(of: pagePresentation.selection) { _, destination in
            if practiceGuide == nil {
                navigation.currentDestination = destination ?? .today
                if destination != .settings { navigation.completeTutorialDiscovery() }
            }
        }
        .onChange(of: navigation.requestID) { _, _ in
            if practiceGuide == nil, let destination = navigation.requestedDestination { selection = destination }
        }
        .onChange(of: displayedDestination, initial: true) { _, destination in
            practiceGuide?.displayed(destination, week: practiceCalendarMode == CalendarDisplayMode.week.rawValue)
        }
        .onChange(of: practiceCalendarMode) { _, mode in
            practiceGuide?.displayed(displayedDestination, week: mode == CalendarDisplayMode.week.rawValue)
        }
        .onReceive(practiceGuide?.$revealRequest.dropFirst().eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if let guide = practiceGuide {
                browsing.columnVisibility = .all
                if guide.progress.step == .seeDates { practiceCalendarMode = CalendarDisplayMode.month.rawValue }
                if guide.course == .tour {
                    browsing.allTodosFilter.clear()
                    browsing.calendarFilter.clear()
                    browsing.allTodosQuery = ""
                    browsing.planningDay = guide.progress.day
                }
                // Keep the final Settings action for the user to perform.
                if guide.progress.step != .done { selectDestination(guide.progress.step.destination) }
            }
        }
        .onChange(of: browsing.allTodosQuery) { _, _ in reportFilter(.all) }
        .onChange(of: browsing.allTodosFilter) { _, _ in reportFilter(.all) }
        .onChange(of: browsing.calendarFilter) { _, _ in reportFilter(.calendar) }
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
    }

    var body: some View {
        routedWorkspace
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
        .allowAppTerminationDuringDialog()
        .alert(L10n.string("确认以空白数据继续？"), isPresented: $isConfirmingEmptyRecovery) {
            Button(L10n.string("以空白数据继续"), role: .destructive) {
                store.continueWithEmptyData()
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("现有损坏文件会被保留，但当前内容将替换为空白数据。"))
        }
        .allowAppTerminationDuringDialog()
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
            if destination == .calendar, let guide = practiceGuide {
                let day = guide.targetTodo?.startDay ?? guide.progress.day
                browsing.calendarSelectedDate = day.date()
                browsing.calendarCurrentMonth = day.date()
                if let block = guide.targetSchedule { browsing.calendarWeekPosition.scrollMinute = CGFloat(max(0, block.startMinute - 30)) }
            }
            selection = destination
        }
    }

    private func newTodo() {
        guard store.canModify, editingItem == nil, editingProject == nil else { return }
        let dueDate: Date? = switch selection {
        case .today: browsing.planningDay.date()
        case .calendar: browsing.calendarSelectedDate
        default: nil
        }
        var item = store.newItem(dueDate: dueDate)
        if let practiceGuide, practiceGuide.progress.step == .create, practiceGuide.targetTodo == nil {
            item.dueDate = practiceGuide.progress.day.date()
            practiceGuide.bindDraft(item.id)
            item.estimatedMinutes = 20
        }
        editingItem = item
    }

    private func reportFilter(_ page: SidebarDestination) {
        practiceGuide?.filtered(query: page == .all ? browsing.allTodosQuery : "", filter: page == .all ? browsing.allTodosFilter : browsing.calendarFilter, at: page)
    }

    private var calendarFilterContext: TodoFilterContext {
        .init(filter: browsing.calendarFilter, showCompleted: store.settings.showCompleted,
              today: calendarToday, startsOnMonday: store.settings.startWeekOnMonday)
    }

    private func refreshCalendarFilterDay() {
        let today = practiceGuide?.progress.day ?? LocalDay(.now)
        if calendarToday != today { calendarToday = today }
    }

    private func sanitizeCalendarFilter() {
        var updated = browsing.calendarFilter
        updated.sanitize(projectIDs: Set(store.projects.map(\.id)), tagIDs: Set(store.tags.map(\.id)))
        if updated != browsing.calendarFilter { browsing.calendarFilter = updated }
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
                calendar.dateInterval(of: .weekOfYear, for: browsing.calendarSelectedDate)?.start
                    ?? browsing.calendarSelectedDate,
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
        let month = calendar.dateInterval(of: .month, for: browsing.calendarCurrentMonth)?.start
            ?? browsing.calendarCurrentMonth
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
    let themeColor: TagColor?
    let selectionChanged: () -> Void

    var body: some View {
        List(SidebarDestination.allCases, selection: $selection) { destination in
            let selectedTheme = selection == destination ? themeColor : nil
            NavigationLink(value: destination) {
                Group {
                    if let selectedTheme {
                        let foreground = selectionForeground(for: selectedTheme)
                        Label {
                            Text(L10n.string(destination.title)).foregroundStyle(foreground)
                        } icon: {
                            Image(systemName: destination.symbol).foregroundStyle(foreground)
                        }
                    } else {
                        Label(L10n.string(destination.title), systemImage: destination.symbol)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .guideTarget(.sidebar(destination))
            .listItemTint(selectedTheme.map(selectionForeground) ?? themeColor?.color)
            .listRowBackground(selectedTheme.map {
                RoundedRectangle(cornerRadius: 7).fill($0.color).padding(.horizontal, 10)
            })
        }
        .listStyle(.sidebar)
        .background { SidebarSelectionHighlight(usesTheme: themeColor != nil) }
        // Keep the first row below the toolbar fade.
        .padding(.top, 12)
        .onChange(of: selection) { _, _ in selectionChanged() }
    }

    private func selectionForeground(for color: TagColor) -> Color {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        // Black and white have equal contrast at a relative luminance of about 0.179.
        return luminance > 0.179 ? .black : .white
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
