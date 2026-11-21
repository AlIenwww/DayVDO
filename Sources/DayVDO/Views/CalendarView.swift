import AppKit
import SwiftUI

struct CalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nativeHeaderHeight: CGFloat = 0
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var filter: TodoFilterState
    let visibility: TodoFilterContext
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var selectedDate: Date
    @Binding var currentMonth: Date
    @AppStorage("calendarDisplayMode") private var storedDisplayMode = CalendarDisplayMode.month.rawValue
    @StateObject private var selection = CalendarTodoSelection()
    @State private var dateChange: TodoStore.DateChangeConfirmation?
    let weekPosition: CalendarWeekViewportPosition
    @State private var navigationRequest: CalendarNavigationRequest?
    @State private var visibleWeekFirstDay: LocalDay?
    @State private var isDatePickerPresented = false
    @State private var datePickerSelection = Date.now
    @Binding var isInspectorPresented: Bool
    @ObservedObject var windowCache: CalendarWindowCache
    let weekCache: CalendarWindowCache
    let weekPresentationCache: CalendarWeekPresentationCache
    let timelineSession: CalendarTimelineSession
    var practiceDisplayMode: Binding<String>? = nil

    private var displayMode: String { (practiceDisplayMode ?? $storedDisplayMode).wrappedValue }

    private var calendar: Calendar {
        AppCalendar.make(
            locale: L10n.locale,
            startsOnMonday: store.settings.startWeekOnMonday
        )
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        Group {
            if displayMode == CalendarDisplayMode.week.rawValue {
                CalendarWeekView(
                    calendar: calendar, visibility: visibility, selectedDate: $selectedDate,
                    position: weekPosition,
                    windowCache: weekCache,
                    presentationCache: weekPresentationCache,
                    navigationID: navigationRequest?.id, navigationDate: navigationRequest?.date,
                    visibleRangeChanged: { day in
                        visibleWeekFirstDay = day
                        let month = monthStart(for: day.adding(days: 3).date(timeZone: calendar.timeZone))
                        if !calendar.isDate(currentMonth, equalTo: month, toGranularity: .month) { currentMonth = month }
                    },
                    createTodo: createTodo, changeTodo: changeTodo,
                    editTodo: { editingItem = $0 },
                    showMore: { day in selectedDate = day.date(); isInspectorPresented = true }
                )
            } else if CalendarNativeMonthExperiment.isEnabled {
                GeometryReader { viewport in
                    CalendarNativeMonthView(
                        calendar: calendar, visibility: visibility,
                        topInset: nativeHeaderHeight,
                        displayedMonth: currentMonth, selectedDate: selectedDate,
                        navigationID: navigationRequest?.id, navigationDate: navigationRequest?.date,
                        session: timelineSession,
                        select: { selectedDate = $0.date() },
                        visibleMonthChanged: { currentMonth = $0 },
                        create: createTodo, change: changeTodo,
                        edit: { editingItem = $0 },
                        showMore: { selectedDate = $0.date(); isInspectorPresented = true }
                    )
                    .id(CalendarViewportIdentity(firstWeekday: calendar.firstWeekday,
                        timeZoneIdentifier: calendar.timeZone.identifier))
                }
                // Extend the measuring container too, so its safe-area inset
                // includes the fixed controls and the native view can draw
                // scrolling rows behind the entire title/weekday strip.
                .ignoresSafeArea(.container, edges: .top)
            } else {
                GeometryReader { viewport in
                    // NavigationSplitView first proposes an ideal height too small
                    // for the six date headers. Build the grid at its real size.
                    if viewport.size.height >= CalendarTimeline.minimumViewportHeight {
                        CalendarTimeline(
                            calendar: calendar,
                            visibility: visibility,
                            displayedMonth: currentMonth,
                            selectedDate: selectedDate,
                            navigationRequest: navigationRequest,
                            store: store,
                            windowCache: windowCache,
                            session: timelineSession,
                            onSelectDate: { selectedDate = $0 },
                            onVisibleMonthChange: { currentMonth = $0 },
                            createTodo: createTodo, changeTodo: changeTodo,
                            editTodo: { editingItem = $0 },
                            showMore: { day in selectedDate = day.date(); isInspectorPresented = true }
                        )
                        .id(CalendarViewportIdentity(
                            firstWeekday: calendar.firstWeekday,
                            timeZoneIdentifier: calendar.timeZone.identifier
                        ))
                        // Recreate row layout when all week heights change; the
                        // session restores the same top week into the new viewport.
                        .id(viewport.size.height)
                    }
                }
            }
        }
        .pageTopBar(blendsNativeContent: CalendarNativeMonthExperiment.isEnabled
                    && displayMode == CalendarDisplayMode.month.rawValue) {
            VStack(spacing: 0) {
                calendarToolbar
                if displayMode == CalendarDisplayMode.month.rawValue {
                    weekdayHeader
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                nativeHeaderHeight = height
            }
        }
        .environmentObject(selection)
        .onAppear { selection.day = LocalDay(selectedDate) }
        .onChange(of: selectedDate) { _, date in selection.day = LocalDay(date) }
        .onChange(of: editingItem) { _, item in
            if item == nil { selection.draft = nil }
        }
        .onChange(of: visibility) { _, _ in clearHiddenSelection() }
        .onChange(of: store.dateContentRevision) { _, _ in
            clearHiddenSelection()
            if let draft = selection.draft, store.item(withID: draft.id) != nil { selection.draft = nil }
            if let id = selection.selectedID, store.item(withID: id) == nil { selection.selectedID = nil }
        }
        .confirmationDialog(L10n.format("删除“%@”？", selection.pendingDelete?.title ?? ""),
            isPresented: Binding(get: { selection.pendingDelete != nil }, set: { if !$0 { selection.pendingDelete = nil } }),
            titleVisibility: .visible) {
                Button(L10n.string("删除"), role: .destructive) {
                    if let item = selection.pendingDelete { _ = store.delete(item) }
                    selection.pendingDelete = nil; selection.selectedID = nil
                }
                Button(L10n.string("取消"), role: .cancel) { selection.pendingDelete = nil }
            } message: { Text(L10n.string("删除后可以从“编辑”菜单撤销。")) }
        .allowAppTerminationDuringDialog()
        .dateChangeConfirmation($dateChange) { _ in }
        .onChange(of: displayMode) { _, _ in
            visibleWeekFirstDay = nil
            currentMonth = monthStart(for: selectedDate)
            timelineSession.topWeek = nil
            navigate(to: selectedDate)
        }
        .inspector(isPresented: $isInspectorPresented) {
            dayDetail
                .inspectorColumnWidth(min: 230, ideal: 300, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                CalendarDisplayModePicker(selection: practiceDisplayMode ?? $storedDisplayMode).guideTarget(.mode)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                TodoFilterButton(filter: $filter).guideTarget(.filter)
                Button { createTodo(LocalDay(selectedDate), LocalDay(selectedDate)) } label: {
                    Label(L10n.string("新建待办…"), systemImage: "plus")
                }
                .help(L10n.string("新建待办") + " (" + store.settings.shortcut(for: .newTodo).display + ")")
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let willPresentInspector = !isInspectorPresented
                    withAnimation(inspectorAnimation) {
                        isInspectorPresented = willPresentInspector
                        if willPresentInspector {
                            columnVisibility = .detailOnly
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                }
                .help(L10n.string(isInspectorPresented ? "隐藏日期详情" : "显示日期详情"))
                .accessibilityLabel(L10n.string(isInspectorPresented ? "隐藏日期详情" : "显示日期详情"))
                .accessibilityValue(L10n.string(isInspectorPresented ? "已展开" : "已收回"))
            }
        }
        .navigationTitle(L10n.string("日历"))
        .onChange(of: columnVisibility) { _, newVisibility in
            guard newVisibility != .detailOnly, isInspectorPresented else { return }
            withAnimation(inspectorAnimation) {
                isInspectorPresented = false
            }
        }
    }

    private var inspectorAnimation: Animation? {
        store.settings.animation(.snappy(duration: 0.28), for: .calendarInspector, reduceMotion: reduceMotion)
    }

    private var calendarToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                calendarDateButton.fixedSize()
                Spacer(minLength: 8)
                calendarNavigationControls.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                calendarDateButton
                HStack { Spacer(minLength: 0); calendarNavigationControls }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 54)
    }

    private var calendarDateButton: some View {
        Button {
            datePickerSelection = selectedDate
            isDatePickerPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(currentMonth.formatted(.dateTime.year().month(.wide).locale(L10n.locale)))
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.string("选择日期"))
        .popover(isPresented: $isDatePickerPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("跳转到日期"))
                    .font(.headline)
                BorderlessCalendarPicker(
                    selection: $datePickerSelection,
                    startsOnMonday: store.settings.startWeekOnMonday
                )
                    .fixedSize()
            }
            .padding(16)
            .onChange(of: datePickerSelection) { _, newDate in
                selectedDate = newDate
                navigate(to: newDate)
                isDatePickerPresented = false
            }
        }

    }

    private var calendarNavigationControls: some View {
        ControlGroup {
            Button(L10n.string("今天")) {
                let today = Date.now
                selectedDate = today
                navigate(to: today)
            }

            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(L10n.string(displayMode == CalendarDisplayMode.week.rawValue ? "上一周" : "上个月"))

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(L10n.string(displayMode == CalendarDisplayMode.week.rawValue ? "下一周" : "下个月"))
        }
        .controlGroupStyle(.navigation)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            }
        }
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(calendar.component(.day, from: selectedDate))")
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(calendar.isDateInToday(selectedDate) ? Color.accentColor : Color.primary)
                    .frame(minWidth: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate.formatted(.dateTime.year().month(.wide).locale(L10n.locale)))
                        .font(.headline)
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).locale(L10n.locale)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider()

            HStack {
                Text(L10n.string("待办事项"))
                    .font(.headline)
                Spacer()
                Button {
                    editingItem = store.newItem(dueDate: selectedDate)
                } label: {
                    Label(L10n.string("添加"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help(L10n.string("为这一天添加待办"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            let items = store.calendarItems(on: selectedDate, visibility: visibility)
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L10n.string(filter.isActive ? "没有找到结果" : "这一天暂无安排"))
                        .font(.callout.weight(.medium))
                    Text(L10n.string(filter.isActive ? "请尝试其他关键词或筛选条件。" : "你可以在这里添加一项待办。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items.map(\.id), id: \.self) { id in
                    CalendarDetailTodoRow(id: id) { editingItem = $0 }
                }
                .listStyle(.inset)
                .id(LocalDay(selectedDate, timeZone: calendar.timeZone))
            }
        }
    }

    private func clearHiddenSelection() {
        if let id = selection.selectedID,
           store.item(withID: id).map({ visibility.includes($0) }) != true {
            selection.selectedID = nil
        }
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func createTodo(_ start: LocalDay, _ end: LocalDay) {
        let draft = store.newItem(startDate: start.date(), dueDate: end.date())
        selection.draft = draft
        editingItem = draft
    }

    private func changeTodo(_ proposed: TodoItem) {
        guard var latest = store.item(withID: proposed.id) else { return }
        latest.startDay = proposed.startDay; latest.dueDay = proposed.dueDay
        if let request = store.dateChangeConfirmation(for: latest) { dateChange = request }
        else { _ = store.upsert(latest) }
    }

    private func navigate(to date: Date) {
        selection.selectedID = nil
        let destination = displayMode == CalendarDisplayMode.week.rawValue
            ? (calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date) : date
        navigationRequest = CalendarNavigationRequest(date: destination)
    }

    private func moveMonth(by value: Int) {
        if displayMode == CalendarDisplayMode.week.rawValue {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            let first = visibleWeekFirstDay ?? LocalDay(weekStart, timeZone: calendar.timeZone)
            navigationRequest = CalendarNavigationRequest(date: first.adding(days: value * 7).date(timeZone: calendar.timeZone))
            selection.selectedID = nil
            return
        }
        guard let target = calendar.date(byAdding: .month, value: value, to: currentMonth) else { return }
        navigate(to: target)
    }
}

private struct CalendarDetailTodoRow: View {
    @EnvironmentObject private var store: TodoStore
    let id: UUID
    let edit: (TodoItem) -> Void

    var body: some View {
        if let item = store.item(withID: id) {
            TodoRow(item: item, showsDate: false, animatesCalendarStatus: true) {
                if let latest = store.item(withID: id) {
                    edit(latest)
                }
            }
            .onDrag { PlanningTodoTransfer.provider(for: item.id) }
        }
    }
}

struct CalendarViewportIdentity: Hashable {
    let firstWeekday: Int
    let timeZoneIdentifier: String
}

private struct CalendarNavigationRequest {
    let id = UUID()
    let date: Date
}

private struct CalendarTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let weekCount = 30
    private static let visibleWeekCount = 6
    static let minimumViewportHeight = CGFloat(visibleWeekCount) * CalendarDateWeekRow.dateHeaderHeight
    private static let centerIndex = 12
    private static let cacheEdgeBuffer = 10
    private static let virtualEdgeBuffer = 52
    // Keep enough runway for gestures before the idle rebase without
    // constructing years of unnecessary virtual rows.
    private static let virtualWeekRange = -104...104
    private static let initialLoadedWeekRange = -centerIndex...(weekCount - centerIndex - 1)

    let calendar: Calendar
    let visibility: TodoFilterContext
    let displayedMonth: Date
    let selectedDate: Date
    let navigationRequest: CalendarNavigationRequest?
    let store: TodoStore
    @ObservedObject var windowCache: CalendarWindowCache
    let session: CalendarTimelineSession
    let onSelectDate: (Date) -> Void
    let onVisibleMonthChange: (Date) -> Void
    let createTodo: (LocalDay, LocalDay) -> Void
    let changeTodo: (TodoItem) -> Void
    let editTodo: (TodoItem) -> Void
    let showMore: (LocalDay) -> Void
    @StateObject private var dateInteraction = CalendarDateInteraction()
    @Namespace private var dragPositions

    @State private var timelineAnchorWeek: Date
    @State private var loadedWeekRange = 0...(Self.visibleWeekCount - 1)
    // Every week has the same height. Pixel positioning avoids resolving all
    // virtual rows as scroll targets whenever the month view is recreated.
    @State private var position = ScrollPosition()
    // Bookkeeping changes every scroll tick, but does not change row content.
    @State private var scrollState: CalendarTimelineScrollState
    @State private var navigationOffset: CGFloat = 0
    @State private var navigationOpacity = 1.0
    @State private var gestureTracker = CalendarGestureTracker()

    init(
        calendar: Calendar,
        visibility: TodoFilterContext,
        displayedMonth: Date,
        selectedDate: Date,
        navigationRequest: CalendarNavigationRequest?,
        store: TodoStore,
        windowCache: CalendarWindowCache,
        session: CalendarTimelineSession,
        onSelectDate: @escaping (Date) -> Void,
        onVisibleMonthChange: @escaping (Date) -> Void,
        createTodo: @escaping (LocalDay, LocalDay) -> Void,
        changeTodo: @escaping (TodoItem) -> Void,
        editTodo: @escaping (TodoItem) -> Void,
        showMore: @escaping (LocalDay) -> Void
    ) {
        self.calendar = calendar
        self.visibility = visibility
        self.displayedMonth = displayedMonth
        self.selectedDate = selectedDate
        self.navigationRequest = navigationRequest
        self.store = store
        self.windowCache = windowCache
        self.session = session
        self.onSelectDate = onSelectDate
        self.onVisibleMonthChange = onVisibleMonthChange
        self.createTodo = createTodo; self.changeTodo = changeTodo
        self.editTodo = editTodo; self.showMore = showMore

        let month = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let restoredTop = session.topWeek.map {
            let date = $0.date(timeZone: calendar.timeZone)
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
        let initialTop = restoredTop
            ?? CalendarMonthGrid.dates(containing: month, calendar: calendar).first
            ?? month
        _timelineAnchorWeek = State(initialValue: initialTop)
        _scrollState = State(initialValue: CalendarTimelineScrollState(month: month))
    }

    var body: some View {
        GeometryReader { geometry in
            let rowHeight = max(1, geometry.size.height / CGFloat(Self.visibleWeekCount))
            let snapshot = currentSnapshot

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Self.virtualWeekRange, id: \.self) { weekOffset in
                        Group {
                            if loadedWeekRange.contains(weekOffset) {
                                CalendarDateWeekRow(
                                    interaction: dateInteraction,
                                    week: LocalDay(week(at: weekOffset), timeZone: calendar.timeZone),
                                    selected: LocalDay(selectedDate, timeZone: calendar.timeZone),
                                    month: calendar.component(.month, from: displayedMonth),
                                    items: snapshot?.items(inWeek: LocalDay(week(at: weekOffset), timeZone: calendar.timeZone)) ?? [],
                                    visibility: visibility,
                                    preparedLayout: snapshot?.dateLayoutsByWeek[LocalDay(week(at: weekOffset), timeZone: calendar.timeZone)],
                                    dragPositions: dragPositions,
                                    select: { onSelectDate($0.date()) }, showMore: showMore,
                                    edit: editTodo
                                )
                            } else {
                                Color.clear.accessibilityHidden(true)
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
                .padding(.horizontal, 12)
                .background(CalendarScrollIndicatorHider())
            }
            .scrollClipDisabled()
            .scrollDisabled(dateInteraction.drag != nil || dateInteraction.suppressed)
            .onPreferenceChange(CalendarWeekFrames.self) { dateInteraction.frames = $0 }
            .onAppear { dateInteraction.viewport = geometry.size }
            .onChange(of: geometry.size) { _, size in if dateInteraction.drag != nil { dateInteraction.cancel() }; dateInteraction.viewport = size }
            .onPreferenceChange(CalendarDateHitRegions.self) { regions in
                let updated = regions.keys.sorted().flatMap { regions[$0] ?? [] }
                if dateInteraction.hitRegions != updated { dateInteraction.hitRegions = updated }
            }
            .overlay {
                CalendarDateInput(interaction: dateInteraction, store: store,
                    select: { onSelectDate($0.date()) }, showMore: showMore,
                    create: createTodo, change: changeTodo, edit: editTodo)
            }
            .scrollPosition($position)
            .defaultScrollAnchor(UnitPoint(x: 0, y: CalendarScrollPolicy.initialWeekAnchor(
                range: Self.virtualWeekRange, visibleCount: Self.visibleWeekCount
            )), for: .initialOffset)
            .scrollTargetBehavior(
                CalendarScrollTargetBehavior(
                    calendar: calendar,
                    timelineAnchorWeek: timelineAnchorWeek,
                    virtualWeekRange: Self.virtualWeekRange,
                    visibleWeekCount: Self.visibleWeekCount,
                    tracker: gestureTracker
                )
            )
            .scrollIndicators(.hidden)
            .offset(y: navigationOffset)
            .opacity(navigationOpacity)
            .onScrollGeometryChange(for: CalendarViewportGeometry.self) { scrollGeometry in
                let currentRowHeight = max(
                    1,
                    scrollGeometry.containerSize.height / CGFloat(Self.visibleWeekCount)
                )
                return CalendarViewportGeometry(
                    rowPosition: CGFloat(Self.virtualWeekRange.lowerBound)
                        + (scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top) / currentRowHeight,
                    rowHeight: currentRowHeight,
                    topInset: scrollGeometry.contentInsets.top
                )
            } action: { _, viewport in
                // ScrollGeometry includes the bar in its offset; ScrollPosition
                // and scroll targets already use content coordinates. Restore
                // the stable week when the system resolves a new top inset.
                if scrollState.scrollTopInset != viewport.topInset {
                    scrollState.scrollTopInset = viewport.topInset
                    scrollState.lastViewportHeight = viewport.rowHeight
                    preserveViewport(at: clampedTopRow(Int(scrollState.latestWeekOffset.rounded())))
                    return
                }
                viewportGeometryChanged(viewport)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                let currentRowHeight = max(
                    1,
                    context.geometry.containerSize.height / CGFloat(Self.visibleWeekCount)
                )
                var rowPosition = CGFloat(Self.virtualWeekRange.lowerBound)
                    + (context.geometry.contentOffset.y + context.geometry.contentInsets.top) / currentRowHeight

                if let resizeAnchor = scrollState.viewportResizeAnchorRow {
                    guard newPhase == .interacting else { return }
                    scrollState.viewportResizeAnchorRow = nil
                    rowPosition = CGFloat(resizeAnchor)
                    scrollState.latestWeekOffset = rowPosition
                }

                if newPhase == .interacting, oldPhase != .interacting {
                    scrollState.lastMovementDirection = nil
                    refreshLoadedWeeks(around: rowPosition, direction: nil, force: true)
                    gestureTracker.begin(at: rowPosition)
                }
                if oldPhase == .interacting, newPhase != .interacting {
                    let velocityInWeeks = (context.velocity?.dy ?? 0) / currentRowHeight
                    let projectedRow = rowPosition + max(
                        -CGFloat(CalendarScrollPolicy.maximumPredictiveDistance),
                        min(
                            CGFloat(CalendarScrollPolicy.maximumPredictiveDistance),
                            velocityInWeeks * 0.22
                        )
                    )
                    refreshLoadedWeeks(
                        around: rowPosition,
                        direction: CalendarScrollDirection(
                            signedMovement: projectedRow - rowPosition
                        ),
                        predictedRow: projectedRow,
                        force: true
                    )
                    gestureTracker.release(
                        at: rowPosition,
                        systemVelocity: velocityInWeeks
                    )
                }
                if newPhase == .animating {
                    gestureTracker.cancelForProgrammaticScroll()
                }
                if newPhase == .idle {
                    gestureTracker.finish()
                    rebaseVirtualTimelineIfNeeded(at: rowPosition)
                }
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let navigationRequest,
                      navigationRequest.id != scrollState.lastNavigationID else { return }
                scrollState.lastNavigationID = navigationRequest.id
                navigate(to: navigationRequest.date)
            }
            .task { prepareSnapshot() }
            .onChange(of: loadedWeekRange) { _, _ in prepareSnapshot() }
            .onChange(of: timelineAnchorWeek) { _, _ in prepareSnapshot() }
            .onChange(of: store.dateContentRevision) { _, _ in prepareSnapshot() }
            .onChange(of: visibility) { _, _ in
                if NSEvent.pressedMouseButtons & 1 != 0 { dateInteraction.cancel() }
                else { dateInteraction.release() }
                dateInteraction.hitRegions = []
                prepareSnapshot()
            }
        }
        .coordinateSpace(name: "calendarDateViewport")
        .onDisappear { dateInteraction.release() }
    }

    private func viewportGeometryChanged(
        _ viewport: CalendarViewportGeometry
    ) {
        // Initial ideal-size proposals must not replace the saved logical week.
        guard scrollState.hasEstablishedInitialPosition
                || CalendarScrollPolicy.viewportHasSettled(reportedRow: viewport.rowPosition, at: 0) else { return }
        let heightChanged = CalendarScrollPolicy.viewportHeightChanged(
            from: scrollState.lastViewportHeight,
            to: viewport.rowHeight
        )
        scrollState.lastViewportHeight = viewport.rowHeight

        if heightChanged {
            let preservedRow = scrollState.viewportResizeAnchorRow
                ?? clampedTopRow(Int(scrollState.latestWeekOffset.rounded()))
            scrollState.viewportResizeAnchorRow = preservedRow
            preserveViewport(at: preservedRow)
            return
        }

        if let preservedRow = scrollState.viewportResizeAnchorRow {
            guard CalendarScrollPolicy.viewportHasSettled(
                reportedRow: viewport.rowPosition,
                at: preservedRow
            ) else {
                preserveViewport(at: preservedRow)
                return
            }
            scrollState.viewportResizeAnchorRow = nil
            geometryChanged(to: CGFloat(preservedRow))
            return
        }

        geometryChanged(to: viewport.rowPosition)
    }

    private func preserveViewport(
        at preservedRow: Int
    ) {
        // During live window resizing SwiftUI can report the old pixel offset with
        // the new row height. Converting that transient pair into a week index can
        // move the 30-week cache away from the visible content and leave a blank
        // calendar. Keep the last stable week anchored until layout catches up.
        gestureTracker.cancelForProgrammaticScroll()
        scrollState.lastMovementDirection = nil
        refreshLoadedWeeks(
            around: CGFloat(preservedRow),
            direction: nil,
            force: true
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollState.latestWeekOffset = CGFloat(preservedRow)
            scroll(to: preservedRow)
        }
    }

    private func geometryChanged(to rowPosition: CGFloat) {
        guard rowPosition.isFinite else { return }
        let isInitialPosition = !scrollState.hasEstablishedInitialPosition
        if !scrollState.hasEstablishedInitialPosition {
            guard abs(rowPosition) <= 1 else { return }
            scrollState.hasEstablishedInitialPosition = true
        }
        let direction = CalendarScrollDirection(
            signedMovement: rowPosition - scrollState.latestWeekOffset
        ) ?? scrollState.lastMovementDirection
        // Initial anchors measure the virtual content before drawing. Keep
        // offscreen date rows cheap until the first user scroll starts.
        if !isInitialPosition {
            refreshLoadedWeeks(around: rowPosition, direction: direction)
        }

        if let movementDirection = CalendarScrollDirection(
            signedMovement: rowPosition - scrollState.latestWeekOffset
        ) {
            scrollState.lastMovementDirection = movementDirection
        }
        scrollState.latestWeekOffset = rowPosition
        session.topWeek = LocalDay(
            week(at: clampedTopRow(Int(rowPosition.rounded()))),
            timeZone: calendar.timeZone
        )
        gestureTracker.update(to: rowPosition)

        let centerDayOffset = Int(((rowPosition + 3) * 7).rounded())
        guard let centerDate = calendar.date(
            byAdding: .day,
            value: centerDayOffset,
            to: timelineAnchorWeek
        ) else { return }
        let month = monthStart(for: centerDate)
        guard !calendar.isDate(month, equalTo: scrollState.lastReportedMonth, toGranularity: .month) else {
            return
        }

        scrollState.lastReportedMonth = month
        onVisibleMonthChange(month)
    }

    private func refreshLoadedWeeks(
        around rowPosition: CGFloat,
        direction: CalendarScrollDirection?,
        predictedRow: CGFloat? = nil,
        force: Bool = false
    ) {
        guard rowPosition.isFinite else { return }
        let visibleTop = Int(floor(rowPosition))
        let visibleBottom = Int(ceil(rowPosition)) + Self.visibleWeekCount - 1
        let cacheMiss = visibleTop < loadedWeekRange.lowerBound
            || visibleBottom > loadedWeekRange.upperBound
        let approachesEdge: Bool
        switch direction {
        case .later:
            approachesEdge = loadedWeekRange.upperBound - visibleBottom
                <= Self.cacheEdgeBuffer
        case .earlier:
            approachesEdge = visibleTop - loadedWeekRange.lowerBound
                <= Self.cacheEdgeBuffer
        case nil:
            approachesEdge = loadedWeekRange.upperBound - visibleBottom
                <= Self.cacheEdgeBuffer
                || visibleTop - loadedWeekRange.lowerBound <= Self.cacheEdgeBuffer
        }
        guard force || cacheMiss || approachesEdge else { return }

        let newRange: ClosedRange<Int>
        if let predictedRow, predictedRow.isFinite {
            newRange = CalendarScrollPolicy.predictiveCacheWindow(
                currentTop: visibleTop,
                predictedTop: Int(predictedRow.rounded()),
                direction: direction,
                cacheCount: Self.weekCount,
                visibleCount: Self.visibleWeekCount,
                limits: Self.virtualWeekRange
            )
        } else {
            newRange = CalendarScrollPolicy.cacheWindow(
                around: visibleTop,
                direction: direction,
                cacheCount: Self.weekCount,
                visibleCount: Self.visibleWeekCount,
                limits: Self.virtualWeekRange
            )
        }
        guard newRange != loadedWeekRange else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            loadedWeekRange = newRange
        }
    }

    private func rebaseVirtualTimelineIfNeeded(at rowPosition: CGFloat) {
        guard scrollState.hasEstablishedInitialPosition, !scrollState.isRecentering, rowPosition.isFinite else { return }
        let maximumTopRow = Self.virtualWeekRange.upperBound - Self.visibleWeekCount + 1
        let needsRecentering = rowPosition
            <= CGFloat(Self.virtualWeekRange.lowerBound + Self.virtualEdgeBuffer)
            || rowPosition >= CGFloat(maximumTopRow - Self.virtualEdgeBuffer)
        guard needsRecentering else { return }

        let visibleWeek = week(at: Int(rowPosition.rounded()))

        scrollState.isRecentering = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineAnchorWeek = visibleWeek
            loadedWeekRange = Self.initialLoadedWeekRange
            scroll(to: 0)
            scrollState.latestWeekOffset = 0
            scrollState.lastMovementDirection = nil
        }

        Task { @MainActor in
            await Task.yield()
            scrollState.isRecentering = false
        }
    }

    private func navigate(to date: Date) {
        guard let targetWeek = monthAnchorWeek(for: date) else { return }
        scrollState.viewportResizeAnchorRow = nil
        gestureTracker.cancelForProgrammaticScroll()
        scrollState.lastMovementDirection = nil

        let targetIndex = index(of: targetWeek)
        let currentIndex = Int(scrollState.latestWeekOffset.rounded())
        let currentWeek = week(at: currentIndex)
        let distance = abs(targetIndex - currentIndex)
        let maximumTopRow = Self.virtualWeekRange.upperBound - Self.visibleWeekCount + 1
        let animate = !reduceMotion && store.settings.animates(.calendarScroll)

        if (Self.virtualWeekRange.lowerBound...maximumTopRow).contains(targetIndex), distance <= 10 {
            let navigationRange = CalendarScrollPolicy.cacheWindowCovering(
                currentTop: currentIndex,
                targetTop: targetIndex,
                cacheCount: Self.weekCount,
                visibleCount: Self.visibleWeekCount,
                limits: Self.virtualWeekRange
            )
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                loadedWeekRange = navigationRange
            }
            Task { @MainActor in
                await Task.yield()
                withAnimation(animate ? .easeOut(duration: 0.32) : nil) {
                    scroll(to: targetIndex)
                }
            }
            return
        }

        let direction: CGFloat = targetWeek >= currentWeek ? 1 : -1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineAnchorWeek = targetWeek
            // A distant jump can keep logical row zero unchanged. Publish the
            // new month and saved week even if no scroll-geometry event follows.
            scrollState.lastReportedMonth = monthStart(for: date)
            onVisibleMonthChange(scrollState.lastReportedMonth)
            session.topWeek = LocalDay(targetWeek, timeZone: calendar.timeZone)
            loadedWeekRange = Self.initialLoadedWeekRange
            scroll(to: 0)
            scrollState.latestWeekOffset = 0
            scrollState.lastMovementDirection = nil
            navigationOffset = animate ? direction * 18 : 0
            navigationOpacity = animate ? 0 : 1
        }

        guard animate else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.2)) {
                navigationOffset = 0
                navigationOpacity = 1
            }
        }
    }

    private func scroll(to row: Int) {
        guard let rowHeight = scrollState.lastViewportHeight else { return }
        position.scrollTo(y: CGFloat(row - Self.virtualWeekRange.lowerBound) * rowHeight)
    }

    private func week(at index: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: index, to: timelineAnchorWeek)
            ?? timelineAnchorWeek
    }

    private func index(of week: Date) -> Int {
        CalendarScrollPolicy.weekOffset(from: timelineAnchorWeek, to: week, calendar: calendar)
    }

    private func monthAnchorWeek(for date: Date) -> Date? {
        CalendarMonthGrid.dates(containing: monthStart(for: date), calendar: calendar).first
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func clampedTopRow(_ row: Int) -> Int {
        let maximumTopRow = Self.virtualWeekRange.upperBound - Self.visibleWeekCount + 1
        return min(max(row, Self.virtualWeekRange.lowerBound), maximumTopRow)
    }

    private var currentSnapshot: CalendarWindowSnapshot? {
        guard let key = snapshotRequest?.key else { return nil }
        return windowCache.snapshotForDisplay(matching: key)
    }

    private func prepareSnapshot() {
        if let request = snapshotRequest { windowCache.prepare(request) }
    }

    private var snapshotRequest: CalendarWindowRequest? {
        let cacheRange = loadedWeekRange.count < Self.weekCount
            ? Self.initialLoadedWeekRange : loadedWeekRange
        let firstDate = week(at: cacheRange.lowerBound)
        guard let lastDate = calendar.date(
            byAdding: .day,
            value: (cacheRange.count * 7) - 1,
            to: firstDate
        ) else { return nil }
        let firstDay = LocalDay(firstDate, timeZone: calendar.timeZone)
        let lastDay = LocalDay(lastDate, timeZone: calendar.timeZone)
        return CalendarWindowRequest(
            key: CalendarWindowSnapshot.Key(
                revision: store.dateContentRevision,
                firstDay: firstDay,
                lastDay: lastDay,
                timeZoneIdentifier: calendar.timeZone.identifier,
                firstWeekday: calendar.firstWeekday,
                visibility: visibility
            ),
            items: store.items,
            tags: store.tags
        )
    }
}

/// Keep per-pixel scroll bookkeeping out of SwiftUI's view dependencies.
/// Only the loaded range and visible month publish actual content changes.
private final class CalendarTimelineScrollState {
    var latestWeekOffset: CGFloat = 0
    var lastMovementDirection: CalendarScrollDirection?
    var hasEstablishedInitialPosition = false
    var lastNavigationID: UUID?
    var lastReportedMonth: Date
    var isRecentering = false
    var scrollTopInset: CGFloat = 0
    var lastViewportHeight: CGFloat?
    var viewportResizeAnchorRow: Int?

    init(month: Date) { lastReportedMonth = month }
}

private struct CalendarViewportGeometry: Equatable {
    let rowPosition: CGFloat
    let rowHeight: CGFloat
    let topInset: CGFloat
}

private final class CalendarGestureTracker {
    private struct Sample {
        let timestamp: TimeInterval
        let rowPosition: CGFloat
    }

    private var generation = 0
    private var consumedGeneration = -1
    private var isTracking = false
    private var startTimestamp: TimeInterval = 0
    private var startRow: CGFloat = 0
    private var latestRow: CGFloat = 0
    private var samples: [Sample] = []
    private var releasedSystemVelocity: CGFloat?

    func begin(at rowPosition: CGFloat) {
        generation &+= 1
        isTracking = true
        startTimestamp = ProcessInfo.processInfo.systemUptime
        startRow = rowPosition
        latestRow = rowPosition
        releasedSystemVelocity = nil
        samples = [Sample(timestamp: startTimestamp, rowPosition: rowPosition)]
    }

    func update(to rowPosition: CGFloat) {
        guard isTracking, rowPosition.isFinite else { return }
        let now = ProcessInfo.processInfo.systemUptime
        latestRow = rowPosition
        samples.append(Sample(timestamp: now, rowPosition: rowPosition))
        trimSamples(relativeTo: now)
    }

    func release(at rowPosition: CGFloat, systemVelocity: CGFloat) {
        guard isTracking else { return }
        update(to: rowPosition)
        releasedSystemVelocity = systemVelocity
    }

    func consumeSnapshot(fallbackSystemVelocity: CGFloat) -> CalendarGestureSnapshot? {
        guard isTracking, consumedGeneration != generation else { return nil }
        consumedGeneration = generation

        let now = ProcessInfo.processInfo.systemUptime
        trimSamples(relativeTo: now)
        let measuredVelocity: CGFloat
        if let first = samples.first,
           let last = samples.last,
           last.timestamp - first.timestamp >= 0.008 {
            measuredVelocity = (last.rowPosition - first.rowPosition)
                / CGFloat(last.timestamp - first.timestamp)
        } else {
            measuredVelocity = 0
        }
        let systemVelocity = releasedSystemVelocity ?? fallbackSystemVelocity
        let releaseVelocity = abs(measuredVelocity) >= 0.01 ? measuredVelocity : systemVelocity

        return CalendarGestureSnapshot(
            startRow: startRow,
            currentRow: latestRow,
            duration: max(0, now - startTimestamp),
            releaseVelocityInWeeksPerSecond: releaseVelocity,
            usesPreciseDeltas: true
        )
    }

    func cancelForProgrammaticScroll() {
        isTracking = false
        consumedGeneration = generation
        samples.removeAll(keepingCapacity: true)
        releasedSystemVelocity = nil
    }

    func finish() {
        isTracking = false
        samples.removeAll(keepingCapacity: true)
        releasedSystemVelocity = nil
    }

    private func trimSamples(relativeTo timestamp: TimeInterval) {
        let cutoff = timestamp - CalendarScrollPolicy.velocitySampleWindow
        while samples.count > 2, samples[1].timestamp < cutoff {
            samples.removeFirst()
        }
    }
}

private struct CalendarScrollTargetBehavior: ScrollTargetBehavior {
    let calendar: Calendar
    let timelineAnchorWeek: Date
    let virtualWeekRange: ClosedRange<Int>
    let visibleWeekCount: Int
    let tracker: CalendarGestureTracker

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let rowHeight = context.containerSize.height / CGFloat(visibleWeekCount)
        guard rowHeight > 0, rowHeight.isFinite else { return }

        let proposedRow = CGFloat(virtualWeekRange.lowerBound) + target.rect.minY / rowHeight
        let fallbackVelocity = context.velocity.dy / rowHeight
        guard let snapshot = tracker.consumeSnapshot(
            fallbackSystemVelocity: fallbackVelocity
        ) else {
            // Coarse mouse wheels don't always create a SwiftUI interaction phase.
            let requestedRow = CalendarScrollPolicy.nearestWeekIndex(
                for: proposedRow,
                direction: nil
            )
            target.rect.origin.y = contentOffset(for: clampedTopRow(requestedRow)) * rowHeight
            return
        }

        let decision = CalendarScrollPolicy.destination(for: snapshot)
        let adjacentMonthIndex: Int?
        if case let .adjacentMonth(direction: direction) = decision {
            adjacentMonthIndex = adjacentMonthRow(
                from: snapshot.startRow,
                direction: direction
            )
        } else {
            adjacentMonthIndex = nil
        }
        let monthCandidates = candidateMonthRows(near: proposedRow)
        let requestedRow = CalendarScrollPolicy.targetIndex(
            for: decision,
            currentRow: snapshot.currentRow,
            proposedMomentumRow: proposedRow,
            adjacentMonthIndex: adjacentMonthIndex,
            monthCandidates: monthCandidates
        )

        target.rect.origin.y = contentOffset(for: clampedTopRow(requestedRow)) * rowHeight
    }

    private func adjacentMonthRow(
        from startRow: CGFloat,
        direction: CalendarScrollDirection
    ) -> Int? {
        let startMonth = viewportMonth(at: startRow)
        guard let targetMonth = calendar.date(
            byAdding: .month,
            value: direction.rawValue,
            to: startMonth
        ) else { return nil }
        return row(forMonth: targetMonth)
    }

    private func candidateMonthRows(near proposedRow: CGFloat) -> [Int] {
        let projectedMonth = viewportMonth(at: proposedRow)
        let maximumTopRow = virtualWeekRange.upperBound - visibleWeekCount + 1
        return (-1...1).compactMap { monthDelta -> Int? in
            guard let month = calendar.date(
                byAdding: .month,
                value: monthDelta,
                to: projectedMonth
            ), let row = row(forMonth: month),
                  (virtualWeekRange.lowerBound...maximumTopRow).contains(row) else {
                return nil
            }
            return row
        }
    }

    private func viewportMonth(at row: CGFloat) -> Date {
        let centerDayOffset = Int(((row + 3) * 7).rounded())
        let centerDate = calendar.date(
            byAdding: .day,
            value: centerDayOffset,
            to: timelineAnchorWeek
        ) ?? timelineAnchorWeek
        return calendar.dateInterval(of: .month, for: centerDate)?.start ?? centerDate
    }

    private func row(forMonth month: Date) -> Int? {
        guard let anchor = CalendarMonthGrid.dates(
            containing: calendar.dateInterval(of: .month, for: month)?.start ?? month,
            calendar: calendar
        ).first else { return nil }
        return CalendarScrollPolicy.weekOffset(from: timelineAnchorWeek, to: anchor, calendar: calendar)
    }

    private func clampedTopRow(_ row: Int) -> Int {
        let maximumTopRow = virtualWeekRange.upperBound - visibleWeekCount + 1
        return min(max(row, virtualWeekRange.lowerBound), maximumTopRow)
    }

    private func contentOffset(for logicalRow: Int) -> CGFloat {
        CGFloat(logicalRow - virtualWeekRange.lowerBound)
    }
}

private struct CalendarScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollIndicatorProbeView {
        ScrollIndicatorProbeView()
    }

    func updateNSView(_ nsView: ScrollIndicatorProbeView, context: Context) {
        nsView.hideEnclosingScroller()
    }
}

private final class ScrollIndicatorProbeView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideEnclosingScroller()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideEnclosingScroller()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func hideEnclosingScroller() {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.verticalScroller?.isHidden = true
                return
            }
            ancestor = view.superview
        }
    }
}
