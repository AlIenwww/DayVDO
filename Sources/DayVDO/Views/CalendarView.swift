import AppKit
import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var selectedDate: Date
    @Binding var currentMonth: Date
    @State private var navigationRequest: CalendarNavigationRequest?
    @State private var isDatePickerPresented = false
    @State private var datePickerSelection = Date.now
    @Binding var isInspectorPresented: Bool
    @ObservedObject var windowCache: CalendarWindowCache
    let timelineSession: CalendarTimelineSession

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
        VStack(spacing: 0) {
            calendarToolbar
            weekdayHeader
            CalendarTimeline(
                calendar: calendar,
                displayedMonth: currentMonth,
                selectedDate: selectedDate,
                navigationRequest: navigationRequest,
                store: store,
                windowCache: windowCache,
                session: timelineSession,
                onSelectDate: { selectedDate = $0 },
                onVisibleMonthChange: { currentMonth = $0 }
            )
            .id(CalendarViewportIdentity(
                firstWeekday: calendar.firstWeekday,
                timeZoneIdentifier: calendar.timeZone.identifier
            ))
        }
        .background(.background)
        .inspector(isPresented: $isInspectorPresented) {
            dayDetail
                .inspectorColumnWidth(min: 230, ideal: 300, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let willPresentInspector = !isInspectorPresented
                    withAnimation(.snappy(duration: 0.28)) {
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
            withAnimation(.snappy(duration: 0.28)) {
                isInspectorPresented = false
            }
        }
    }

    private var calendarToolbar: some View {
        HStack(spacing: 8) {
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

            Spacer()

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
            .help(L10n.string("上个月"))

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(L10n.string("下个月"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .frame(height: 54)
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
        .background(.bar)
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
                    editingItem = TodoItem(
                        title: "",
                        dueDate: selectedDate,
                        priority: store.settings.defaultPriority
                    )
                } label: {
                    Label(L10n.string("添加"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help(L10n.string("为这一天添加待办"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            let items = store.calendarItems(on: selectedDate)
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L10n.string("这一天暂无安排"))
                        .font(.callout.weight(.medium))
                    Text(L10n.string("你可以在这里添加一项待办。"))
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

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func navigate(to date: Date) {
        navigationRequest = CalendarNavigationRequest(date: date)
    }

    private func moveMonth(by value: Int) {
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
            TodoRow(item: item, showsDate: false) {
                if let latest = store.item(withID: id) {
                    edit(latest)
                }
            }
        }
    }
}

private struct CalendarViewportIdentity: Hashable {
    let firstWeekday: Int
    let timeZoneIdentifier: String
}

private struct CalendarNavigationRequest {
    let id = UUID()
    let date: Date
}

private struct CalendarTimeline: View {
    private static let weekCount = 30
    private static let visibleWeekCount = 6
    private static let centerIndex = 12
    private static let cacheEdgeBuffer = 10
    private static let virtualEdgeBuffer = 52
    private static let virtualWeekRange = -1040...1040
    private static let initialLoadedWeekRange = -centerIndex...(weekCount - centerIndex - 1)

    let calendar: Calendar
    let displayedMonth: Date
    let selectedDate: Date
    let navigationRequest: CalendarNavigationRequest?
    let store: TodoStore
    @ObservedObject var windowCache: CalendarWindowCache
    let session: CalendarTimelineSession
    let onSelectDate: (Date) -> Void
    let onVisibleMonthChange: (Date) -> Void

    @State private var timelineAnchorWeek: Date
    @State private var loadedWeekRange = Self.initialLoadedWeekRange
    @State private var topWeekOffset: Int? = 0
    @State private var latestWeekOffset: CGFloat = 0
    @State private var lastMovementDirection: CalendarScrollDirection?
    @State private var hasEstablishedInitialPosition = false
    @State private var lastNavigationID: UUID?
    @State private var lastReportedMonth: Date
    @State private var isRecentering = false
    @State private var navigationOffset: CGFloat = 0
    @State private var navigationOpacity = 1.0
    @State private var gestureTracker = CalendarGestureTracker()
    @State private var lastViewportHeight: CGFloat?
    @State private var viewportResizeAnchorRow: Int?

    init(
        calendar: Calendar,
        displayedMonth: Date,
        selectedDate: Date,
        navigationRequest: CalendarNavigationRequest?,
        store: TodoStore,
        windowCache: CalendarWindowCache,
        session: CalendarTimelineSession,
        onSelectDate: @escaping (Date) -> Void,
        onVisibleMonthChange: @escaping (Date) -> Void
    ) {
        self.calendar = calendar
        self.displayedMonth = displayedMonth
        self.selectedDate = selectedDate
        self.navigationRequest = navigationRequest
        self.store = store
        self.windowCache = windowCache
        self.session = session
        self.onSelectDate = onSelectDate
        self.onVisibleMonthChange = onVisibleMonthChange

        let month = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let restoredTop = session.topWeek?.date(timeZone: calendar.timeZone)
        let initialTop = restoredTop
            ?? CalendarMonthGrid.dates(containing: month, calendar: calendar).first
            ?? month
        _timelineAnchorWeek = State(initialValue: initialTop)
        _lastReportedMonth = State(initialValue: month)
    }

    var body: some View {
        GeometryReader { geometry in
            let rowHeight = max(1, geometry.size.height / CGFloat(Self.visibleWeekCount))

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Self.virtualWeekRange, id: \.self) { weekOffset in
                            Group {
                                if loadedWeekRange.contains(weekOffset) {
                                    CalendarWeekRow(
                                        weekStart: week(at: weekOffset),
                                        displayedMonth: displayedMonth,
                                        selectedDate: selectedDate,
                                        calendar: calendar,
                                        snapshot: windowCache.snapshot,
                                        onSelectDate: onSelectDate
                                    )
                                } else {
                                    Color.clear.accessibilityHidden(true)
                                }
                            }
                            .frame(height: rowHeight)
                            .id(weekOffset)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                    .background(CalendarScrollIndicatorHider())
                }
                .scrollPosition(id: $topWeekOffset, anchor: .top)
                .task {
                    // Resolve the initial week after the newly sized scroll view
                    // has laid out its targets, instead of retaining old offsets.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(0, anchor: .top)
                    }
                }
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
                            + scrollGeometry.contentOffset.y / currentRowHeight,
                        rowHeight: currentRowHeight
                    )
                } action: { _, viewport in
                    viewportGeometryChanged(viewport, scrollProxy: scrollProxy)
                }
                .onScrollPhaseChange { oldPhase, newPhase, context in
                    let currentRowHeight = max(
                        1,
                        context.geometry.containerSize.height / CGFloat(Self.visibleWeekCount)
                    )
                    var rowPosition = CGFloat(Self.virtualWeekRange.lowerBound)
                        + context.geometry.contentOffset.y / currentRowHeight

                    if let resizeAnchor = viewportResizeAnchorRow {
                        guard newPhase == .interacting else { return }
                        viewportResizeAnchorRow = nil
                        rowPosition = CGFloat(resizeAnchor)
                        latestWeekOffset = rowPosition
                    }

                    if newPhase == .interacting, oldPhase != .interacting {
                        lastMovementDirection = nil
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
                          navigationRequest.id != lastNavigationID else { return }
                    lastNavigationID = navigationRequest.id
                    navigate(to: navigationRequest.date)
                }
                .task { prepareSnapshot() }
                .onChange(of: loadedWeekRange) { _, _ in prepareSnapshot() }
                .onChange(of: timelineAnchorWeek) { _, _ in prepareSnapshot() }
                .onChange(of: store.contentRevision) { _, _ in prepareSnapshot() }
                .onChange(of: store.settings.showCompleted) { _, _ in prepareSnapshot() }
            }
        }
    }

    private func viewportGeometryChanged(
        _ viewport: CalendarViewportGeometry,
        scrollProxy: ScrollViewProxy
    ) {
        let heightChanged = CalendarScrollPolicy.viewportHeightChanged(
            from: lastViewportHeight,
            to: viewport.rowHeight
        )
        lastViewportHeight = viewport.rowHeight

        if heightChanged {
            let preservedRow = viewportResizeAnchorRow
                ?? clampedTopRow(Int(latestWeekOffset.rounded()))
            viewportResizeAnchorRow = preservedRow
            preserveViewport(at: preservedRow, scrollProxy: scrollProxy)
            return
        }

        if let preservedRow = viewportResizeAnchorRow {
            guard CalendarScrollPolicy.viewportHasSettled(
                reportedRow: viewport.rowPosition,
                at: preservedRow
            ) else {
                preserveViewport(at: preservedRow, scrollProxy: scrollProxy)
                return
            }
            viewportResizeAnchorRow = nil
            geometryChanged(to: CGFloat(preservedRow))
            return
        }

        geometryChanged(to: viewport.rowPosition)
    }

    private func preserveViewport(
        at preservedRow: Int,
        scrollProxy: ScrollViewProxy
    ) {
        // During live window resizing SwiftUI can report the old pixel offset with
        // the new row height. Converting that transient pair into a week index can
        // move the 30-week cache away from the visible content and leave a blank
        // calendar. Keep the last stable week anchored until layout catches up.
        gestureTracker.cancelForProgrammaticScroll()
        lastMovementDirection = nil
        refreshLoadedWeeks(
            around: CGFloat(preservedRow),
            direction: nil,
            force: true
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            topWeekOffset = preservedRow
            latestWeekOffset = CGFloat(preservedRow)
            scrollProxy.scrollTo(preservedRow, anchor: .top)
        }
    }

    private func geometryChanged(to rowPosition: CGFloat) {
        guard rowPosition.isFinite else { return }
        if !hasEstablishedInitialPosition {
            guard abs(rowPosition) <= 1 else { return }
            hasEstablishedInitialPosition = true
        }
        let direction = CalendarScrollDirection(
            signedMovement: rowPosition - latestWeekOffset
        ) ?? lastMovementDirection
        refreshLoadedWeeks(around: rowPosition, direction: direction)

        if let movementDirection = CalendarScrollDirection(
            signedMovement: rowPosition - latestWeekOffset
        ) {
            lastMovementDirection = movementDirection
        }
        latestWeekOffset = rowPosition
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
        guard !calendar.isDate(month, equalTo: lastReportedMonth, toGranularity: .month) else {
            return
        }

        lastReportedMonth = month
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
        guard hasEstablishedInitialPosition, !isRecentering, rowPosition.isFinite else { return }
        let maximumTopRow = Self.virtualWeekRange.upperBound - Self.visibleWeekCount + 1
        let needsRecentering = rowPosition
            <= CGFloat(Self.virtualWeekRange.lowerBound + Self.virtualEdgeBuffer)
            || rowPosition >= CGFloat(maximumTopRow - Self.virtualEdgeBuffer)
        guard needsRecentering else { return }

        let visibleWeek = week(at: Int(rowPosition.rounded()))

        isRecentering = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineAnchorWeek = visibleWeek
            loadedWeekRange = Self.initialLoadedWeekRange
            topWeekOffset = 0
            latestWeekOffset = 0
            lastMovementDirection = nil
        }

        Task { @MainActor in
            await Task.yield()
            isRecentering = false
        }
    }

    private func navigate(to date: Date) {
        guard let targetWeek = monthAnchorWeek(for: date) else { return }
        viewportResizeAnchorRow = nil
        gestureTracker.cancelForProgrammaticScroll()
        lastMovementDirection = nil

        let targetIndex = index(of: targetWeek)
        let currentIndex = Int(latestWeekOffset.rounded())
        let currentWeek = week(at: currentIndex)
        let distance = abs(
            calendar.dateComponents([.weekOfYear], from: currentWeek, to: targetWeek).weekOfYear ?? 0
        )
        let maximumTopRow = Self.virtualWeekRange.upperBound - Self.visibleWeekCount + 1

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
                topWeekOffset = nil
            }
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeOut(duration: 0.32)) {
                    topWeekOffset = targetIndex
                }
            }
            return
        }

        let direction: CGFloat = targetWeek >= currentWeek ? 1 : -1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineAnchorWeek = targetWeek
            loadedWeekRange = Self.initialLoadedWeekRange
            topWeekOffset = 0
            latestWeekOffset = 0
            lastMovementDirection = nil
            navigationOffset = direction * 18
            navigationOpacity = 0
        }

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.2)) {
                navigationOffset = 0
                navigationOpacity = 1
            }
        }
    }

    private func week(at index: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: index, to: timelineAnchorWeek)
            ?? timelineAnchorWeek
    }

    private func index(of week: Date) -> Int {
        let days = calendar.dateComponents([.day], from: timelineAnchorWeek, to: week).day ?? 0
        return days / 7
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

    private func prepareSnapshot() {
        let firstDate = week(at: loadedWeekRange.lowerBound)
        guard let lastDate = calendar.date(
            byAdding: .day,
            value: (loadedWeekRange.count * 7) - 1,
            to: firstDate
        ) else { return }
        let firstDay = LocalDay(firstDate, timeZone: calendar.timeZone)
        let lastDay = LocalDay(lastDate, timeZone: calendar.timeZone)
        windowCache.prepare(CalendarWindowRequest(
            key: CalendarWindowSnapshot.Key(
                revision: store.contentRevision,
                firstDay: firstDay,
                lastDay: lastDay,
                timeZoneIdentifier: calendar.timeZone.identifier,
                firstWeekday: calendar.firstWeekday,
                showCompleted: store.settings.showCompleted
            ),
            items: store.items,
            tags: store.tags
        ))
    }
}

private struct CalendarViewportGeometry: Equatable {
    let rowPosition: CGFloat
    let rowHeight: CGFloat
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
        let days = calendar.dateComponents([.day], from: timelineAnchorWeek, to: anchor).day ?? 0
        return days / 7
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

private struct CalendarWeekRow: View {
    let weekStart: Date
    let displayedMonth: Date
    let selectedDate: Date
    let calendar: Calendar
    let snapshot: CalendarWindowSnapshot?
    let onSelectDate: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                let date = calendar.date(byAdding: .day, value: column, to: weekStart) ?? weekStart
                CalendarDayCell(
                    date: date,
                    displayedMonth: displayedMonth,
                    selectedDate: selectedDate,
                    calendar: calendar,
                    items: snapshot?.items(
                        on: LocalDay(date, timeZone: calendar.timeZone)
                    ) ?? [],
                    onSelectDate: onSelectDate
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            CalendarGridLines(columns: 7, rows: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let displayedMonth: Date
    let selectedDate: Date
    let calendar: Calendar
    let items: [CalendarWindowSnapshot.Item]
    let onSelectDate: (Date) -> Void

    var body: some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let belongsToMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        Button {
            onSelectDate(date)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(today || selected ? .semibold : .regular))
                    .foregroundStyle(
                        selected ? Color.white :
                            (today ? Color.accentColor : (belongsToMonth ? Color.primary : Color.secondary))
                    )
                    .frame(width: 23, height: 23)
                    .background(selected ? Color.accentColor : Color.clear, in: Circle())

                ForEach(items.prefix(2)) { item in
                    let itemColor = item.tagColor?.color ?? Color.accentColor
                    HStack(spacing: 3) {
                        if item.status == .inProgress {
                            Image(systemName: item.status.symbolName)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                        if item.hasProject {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.title)
                            .strikethrough(item.isCompleted)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .padding(.horizontal, 4)
                    .padding(.leading, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        itemColor.opacity(item.isCompleted ? 0.05 : 0.13),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(itemColor.opacity(item.isCompleted ? 0.45 : 0.9))
                            .frame(width: 2)
                            .padding(.vertical, 2)
                    }
                }

                if items.count > 2 {
                    Text(L10n.format("另有 %lld 项", items.count - 2))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
            .opacity(belongsToMonth ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(
            date.formatted(.dateTime.year().month(.wide).day().locale(L10n.locale))
        )
        .accessibilityValue(L10n.format("%lld 项待办", items.count))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(today ? L10n.string("今天") : "")
    }
}

private struct CalendarGridLines: View {
    let columns: Int
    let rows: Int

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for column in 0...columns {
                    let x = geometry.size.width * CGFloat(column) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                for row in 0...rows {
                    let y = geometry.size.height * CGFloat(row) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
        }
    }
}
