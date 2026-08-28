import SwiftUI
import AppKit
import QuartzCore

struct CalendarView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var selectedDate = Date.now
    @State private var currentMonth = Date.now
    @State private var navigationRequest: CalendarNavigationRequest?
    @State private var isDatePickerPresented = false
    @State private var datePickerSelection = Date.now
    @State private var isInspectorPresented = false

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = store.settings.startWeekOnMonday ? 2 : 1
        value.locale = L10n.locale
        return value
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
            CalendarNativeTimeline(
                calendar: calendar,
                displayedMonth: currentMonth,
                selectedDate: selectedDate,
                navigationRequest: navigationRequest,
                store: store,
                onSelectDate: { selectedDate = $0 },
                onVisibleMonthChange: { currentMonth = $0 }
            )
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
        .onAppear {
            currentMonth = monthStart(for: .now)
        }
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
                datePickerSelection = currentMonth
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
                    BorderlessCalendarPicker(selection: $datePickerSelection)
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
                    editingItem = TodoItem(title: "", dueDate: selectedDate, priority: store.settings.defaultPriority)
                } label: {
                    Label(L10n.string("添加"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help(L10n.string("为这一天添加待办"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            let items = store.items(on: selectedDate)
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
                List(items) { item in
                    TodoRow(item: item, showsDate: false) { editingItem = item }
                }
                .listStyle(.inset)
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

private struct CalendarNavigationRequest {
    let id = UUID()
    let date: Date
}

private struct CalendarNativeTimeline: NSViewRepresentable {
    let calendar: Calendar
    let displayedMonth: Date
    let selectedDate: Date
    let navigationRequest: CalendarNavigationRequest?
    let store: TodoStore
    let onSelectDate: (Date) -> Void
    let onVisibleMonthChange: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CalendarCollectionScrollView {
        let scrollView = CalendarCollectionScrollView()
        let collectionView = NSCollectionView()
        let layout = NSCollectionViewFlowLayout()

        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            CalendarWeekCollectionItem.self,
            forItemWithIdentifier: CalendarWeekCollectionItem.identifier
        )
        collectionView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        collectionView.autoresizingMask = [.width]

        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        scrollView.verticalScroller = nil
        scrollView.hasVerticalScroller = false

        context.coordinator.attach(
            scrollView: scrollView,
            collectionView: collectionView,
            layout: layout
        )
        return scrollView
    }

    func updateNSView(_ scrollView: CalendarCollectionScrollView, context: Context) {
        context.coordinator.update(parent: self)
        context.coordinator.updateLayout()
        context.coordinator.refreshVisibleItems()

        if let request = navigationRequest,
           request.id != context.coordinator.lastNavigationID {
            context.coordinator.lastNavigationID = request.id
            context.coordinator.navigate(to: request.date, animated: true)
        }
    }

    static func dismantleNSView(_ nsView: CalendarCollectionScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        private static let weekCount = 30
        private static let centerIndex = weekCount / 2
        private static let recenterThreshold = 7

        var parent: CalendarNativeTimeline
        var lastNavigationID: UUID?

        private weak var scrollView: CalendarCollectionScrollView?
        private weak var collectionView: NSCollectionView?
        private weak var layout: NSCollectionViewFlowLayout?
        private var boundsObserver: NSObjectProtocol?
        private var rowHeight: CGFloat = 1
        private var visibleMonth: Date
        private var timelineAnchorWeek: Date
        private var hasPositionedInitially = false
        private var isProgrammaticScroll = false
        private var isRecenteringTimeline = false
        private var isPreparingNavigation = false
        private var gestureStartMonth: Date?

        init(parent: CalendarNativeTimeline) {
            self.parent = parent
            let month = parent.calendar.dateInterval(of: .month, for: parent.displayedMonth)?.start
                ?? parent.displayedMonth
            self.visibleMonth = month
            self.timelineAnchorWeek = CalendarMonthGrid.dates(containing: month, calendar: parent.calendar).first
                ?? month
        }

        func attach(
            scrollView: CalendarCollectionScrollView,
            collectionView: NSCollectionView,
            layout: NSCollectionViewFlowLayout
        ) {
            self.scrollView = scrollView
            self.collectionView = collectionView
            self.layout = layout

            scrollView.onGestureBegan = { [weak self] in
                guard let self else { return }
                self.cancelProgrammaticAnimation()
                self.gestureStartMonth = self.monthAtViewport()
            }
            scrollView.onGestureEnded = { [weak self] startY, endY, signedDelta in
                self?.settleGesture(startY: startY, endY: endY, signedDelta: signedDelta)
            }
            scrollView.onViewportSizeChanged = { [weak self] in
                self?.updateLayout()
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.visibleBoundsDidChange()
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateLayout()
                self.positionInitiallyIfNeeded()
            }
        }

        func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
            scrollView?.onViewportSizeChanged = nil
        }

        func update(parent: CalendarNativeTimeline) {
            let weekdayChanged = self.parent.calendar.firstWeekday != parent.calendar.firstWeekday
            let selectionChanged = !parent.calendar.isDate(
                self.parent.selectedDate,
                inSameDayAs: parent.selectedDate
            )
            self.parent = parent

            if weekdayChanged {
                visibleMonth = monthStart(for: parent.displayedMonth)
                timelineAnchorWeek = CalendarMonthGrid.dates(
                    containing: visibleMonth,
                    calendar: parent.calendar
                ).first ?? visibleMonth
                collectionView?.reloadData()
                setViewport(toWeekOffset: 0, animated: false)
            } else if selectionChanged {
                refreshVisibleItems()
            }
        }

        func updateLayout() {
            guard let scrollView, let collectionView, let layout else { return }
            let viewportSize = scrollView.contentSize
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            let newRowHeight = viewportSize.height / 6
            let newItemSize = NSSize(
                width: max(1, viewportSize.width - layout.sectionInset.left - layout.sectionInset.right),
                height: newRowHeight
            )
            guard abs(layout.itemSize.width - newItemSize.width) > 0.5 ||
                    abs(layout.itemSize.height - newItemSize.height) > 0.5 else { return }

            let preservedRowPosition = rowHeight > 0
                ? scrollView.contentView.bounds.minY / rowHeight
                : CGFloat(Self.centerIndex)
            rowHeight = newRowHeight
            layout.itemSize = newItemSize
            layout.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()

            if hasPositionedInitially {
                let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
                let maximumY = max(0, contentHeight - viewportSize.height)
                let targetY = min(max(preservedRowPosition * newRowHeight, 0), maximumY)
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func positionInitiallyIfNeeded() {
            guard !hasPositionedInitially else { return }
            hasPositionedInitially = true
            navigate(to: .now, animated: false)
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            1
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            Self.weekCount
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: CalendarWeekCollectionItem.identifier,
                for: indexPath
            )
            guard let weekItem = item as? CalendarWeekCollectionItem else { return item }
            configure(weekItem, at: indexPath)
            return weekItem
        }

        func refreshVisibleItems() {
            guard let collectionView else { return }
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard let item = collectionView.item(at: indexPath) as? CalendarWeekCollectionItem else { continue }
                configure(item, at: indexPath)
            }
        }

        private func configure(_ item: CalendarWeekCollectionItem, at indexPath: IndexPath) {
            let offset = weekOffset(for: indexPath.item)
            let week = weekStart(at: offset)
            let content = CalendarWeekRow(
                weekStart: week,
                displayedMonth: visibleMonth,
                selectedDate: parent.selectedDate,
                calendar: parent.calendar,
                onSelectDate: { [weak self] date in
                    self?.selectDate(date)
                }
            )
            .environmentObject(parent.store)
            item.setContent(AnyView(content))
        }

        private func selectDate(_ date: Date) {
            parent.onSelectDate(date)
            refreshVisibleItems()
        }

        func navigate(to date: Date, animated: Bool) {
            guard let targetWeek = monthAnchorWeek(for: date) else { return }
            let targetOffset = weekOffset(forWeek: targetWeek)
            let safeLimit = Self.centerIndex - 6

            if abs(targetOffset) <= safeLimit {
                setViewport(toWeekOffset: targetOffset, animated: animated)
                return
            }

            let currentWeek = weekStart(at: topWeekOffset())
            let approachOffset = animated ? (targetWeek > currentWeek ? -8 : 8) : 0
            isPreparingNavigation = true
            timelineAnchorWeek = targetWeek
            collectionView?.reloadData()
            updateLayout()
            setViewport(toWeekOffset: approachOffset, animated: false)

            guard animated else {
                isPreparingNavigation = false
                visibleBoundsDidChange()
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.collectionView?.layoutSubtreeIfNeeded()
                self.isPreparingNavigation = false
                self.setViewport(toWeekOffset: 0, animated: true)
            }
        }

        private func setViewport(toWeekOffset offset: Int, animated: Bool) {
            guard let scrollView, let collectionView else { return }
            let index = itemIndex(forWeekOffset: offset)
            guard (0..<Self.weekCount).contains(index) else { return }

            collectionView.layoutSubtreeIfNeeded()
            let indexPath = IndexPath(item: index, section: 0)
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                collectionView.scrollToItems(at: [indexPath], scrollPosition: .top)
                DispatchQueue.main.async { [weak self] in
                    self?.setViewport(toWeekOffset: offset, animated: animated)
                }
                return
            }

            let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
            let maximumY = max(0, contentHeight - scrollView.contentSize.height)
            let targetY = min(max(attributes.frame.minY, 0), maximumY)
            let targetPoint = NSPoint(x: 0, y: targetY)

            if animated, abs(scrollView.contentView.bounds.minY - targetY) > 0.5 {
                isProgrammaticScroll = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.42
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, let scrollView = self.scrollView else { return }
                        self.isProgrammaticScroll = false
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        self.visibleBoundsDidChange()
                    }
                }
            } else {
                scrollView.contentView.setBoundsOrigin(targetPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                visibleBoundsDidChange()
            }
        }

        private func cancelProgrammaticAnimation() {
            guard isProgrammaticScroll, let scrollView else { return }
            isProgrammaticScroll = false
            scrollView.contentView.layer?.removeAllAnimations()
        }

        private func settleGesture(startY: CGFloat, endY: CGFloat, signedDelta: CGFloat) {
            guard !isProgrammaticScroll, rowHeight > 0 else { return }
            let movement = abs(signedDelta) > 0.5 ? signedDelta : endY - startY
            guard abs(movement) > 0.5 else { return }

            let direction = movement > 0 ? -1 : 1
            let startMonth = gestureStartMonth ?? monthAtViewport()
            gestureStartMonth = nil
            guard let targetMonth = parent.calendar.date(
                byAdding: .month,
                value: direction,
                to: startMonth
            ) else { return }
            let targetOffset = weekOffset(forMonth: targetMonth)
            setViewport(toWeekOffset: targetOffset, animated: true)
        }

        private func recenterTimelineIfNeeded() {
            let offset = topWeekOffset()
            guard !isProgrammaticScroll,
                  !isRecenteringTimeline,
                  abs(offset) >= Self.recenterThreshold,
                  let collectionView,
                  let scrollView else { return }

            isRecenteringTimeline = true
            timelineAnchorWeek = weekStart(at: offset)
            collectionView.reloadData()
            collectionView.layoutSubtreeIfNeeded()
            let centeredY = CGFloat(Self.centerIndex) * rowHeight
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: centeredY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isRecenteringTimeline = false
        }

        private func visibleBoundsDidChange() {
            guard !isPreparingNavigation else { return }
            recenterTimelineIfNeeded()
            let offset = topWeekOffset()
            let week = weekStart(at: offset)
            let viewportCenter = parent.calendar.date(byAdding: .day, value: 21, to: week) ?? week
            let month = monthStart(for: viewportCenter)
            guard !parent.calendar.isDate(month, equalTo: visibleMonth, toGranularity: .month) else { return }

            visibleMonth = month
            refreshVisibleItems()
            parent.onVisibleMonthChange(month)
        }

        private func monthAtViewport() -> Date {
            let week = weekStart(at: topWeekOffset())
            let viewportCenter = parent.calendar.date(byAdding: .day, value: 21, to: week) ?? week
            return monthStart(for: viewportCenter)
        }

        private func topWeekOffset() -> Int {
            guard let scrollView, rowHeight > 0 else { return 0 }
            let index = Int((scrollView.contentView.bounds.minY / rowHeight).rounded())
            return weekOffset(for: min(max(index, 0), Self.weekCount - 1))
        }

        private func weekOffset(for itemIndex: Int) -> Int {
            itemIndex - Self.centerIndex
        }

        private func itemIndex(forWeekOffset offset: Int) -> Int {
            Self.centerIndex + offset
        }

        private func weekStart(at offset: Int) -> Date {
            parent.calendar.date(byAdding: .weekOfYear, value: offset, to: timelineAnchorWeek)
                ?? timelineAnchorWeek
        }

        private func weekOffset(forMonth month: Date) -> Int {
            guard let targetWeek = monthAnchorWeek(for: month) else { return 0 }
            return weekOffset(forWeek: targetWeek)
        }

        private func weekOffset(forWeek targetWeek: Date) -> Int {
            let dayDistance = parent.calendar.dateComponents(
                [.day],
                from: timelineAnchorWeek,
                to: targetWeek
            ).day ?? 0
            return dayDistance / 7
        }

        private func monthAnchorWeek(for date: Date) -> Date? {
            CalendarMonthGrid.dates(
                containing: monthStart(for: date),
                calendar: parent.calendar
            ).first
        }

        private func monthAnchorWeekOffset(near offset: Int) -> Int {
            let week = weekStart(at: offset)
            let viewportCenter = parent.calendar.date(byAdding: .day, value: 21, to: week) ?? week
            return weekOffset(forMonth: viewportCenter)
        }

        private func monthStart(for date: Date) -> Date {
            parent.calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }
}

private final class CalendarCollectionScrollView: NSScrollView {
    var onGestureBegan: (() -> Void)?
    var onGestureEnded: ((CGFloat, CGFloat, CGFloat) -> Void)?
    var onViewportSizeChanged: (() -> Void)?

    private var gestureStartY: CGFloat?
    private var accumulatedSignedDelta: CGFloat = 0
    private var gestureEndWorkItem: DispatchWorkItem?
    private var isIgnoringMomentum = false
    private var lastViewportSize = NSSize.zero
    private var isViewportUpdateScheduled = false

    override var hasVerticalScroller: Bool {
        get { false }
        set { super.hasVerticalScroller = false }
    }

    override var verticalScroller: NSScroller? {
        get { nil }
        set { super.verticalScroller = nil }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeScrollers()
    }

    override func layout() {
        super.layout()
        removeScrollers()
        scheduleViewportUpdateIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        if isIgnoringMomentum, !event.momentumPhase.isEmpty {
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                isIgnoringMomentum = false
            }
            return
        }

        if event.phase.contains(.began) || gestureStartY == nil {
            gestureEndWorkItem?.cancel()
            gestureStartY = contentView.bounds.minY
            accumulatedSignedDelta = 0
            isIgnoringMomentum = false
            onGestureBegan?()
        }

        accumulatedSignedDelta += event.scrollingDeltaY
        super.scrollWheel(with: event)

        if event.phase.contains(.cancelled) {
            finishGesture(ignoreMomentum: false)
        } else if event.phase.contains(.ended) {
            finishGesture(ignoreMomentum: true)
        } else if event.momentumPhase.contains(.began) {
            gestureEndWorkItem?.cancel()
            gestureEndWorkItem = nil
        } else if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            finishGesture(ignoreMomentum: false)
        } else if event.phase.isEmpty && event.momentumPhase.isEmpty {
            scheduleGestureEnd(after: 0.06)
        }
    }

    private func scheduleGestureEnd(after delay: TimeInterval) {
        gestureEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishGesture(ignoreMomentum: false)
        }
        gestureEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func finishGesture(ignoreMomentum: Bool) {
        gestureEndWorkItem?.cancel()
        gestureEndWorkItem = nil
        guard let startY = gestureStartY else { return }
        let endY = contentView.bounds.minY
        let signedDelta = accumulatedSignedDelta
        gestureStartY = nil
        accumulatedSignedDelta = 0
        isIgnoringMomentum = ignoreMomentum
        onGestureEnded?(startY, endY, signedDelta)
    }

    private func removeScrollers() {
        if super.hasVerticalScroller {
            super.hasVerticalScroller = false
        }
        if super.hasHorizontalScroller {
            super.hasHorizontalScroller = false
        }
        super.verticalScroller?.isHidden = true
        super.horizontalScroller?.isHidden = true
    }

    private func scheduleViewportUpdateIfNeeded() {
        let newSize = contentSize
        guard abs(newSize.width - lastViewportSize.width) > 0.5 ||
                abs(newSize.height - lastViewportSize.height) > 0.5 else { return }

        lastViewportSize = newSize
        guard !isViewportUpdateScheduled else { return }
        isViewportUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isViewportUpdateScheduled = false
            self.onViewportSizeChanged?()
        }
    }
}

private final class CalendarWeekCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("CalendarWeekCollectionItem")

    private var hostingView: NSHostingView<AnyView>?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    func setContent(_ content: AnyView) {
        if let hostingView {
            hostingView.rootView = content
            return
        }

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.hostingView = hostingView
    }
}

private struct CalendarWeekRow: View {
    let weekStart: Date
    let displayedMonth: Date
    let selectedDate: Date
    let calendar: Calendar
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
    @EnvironmentObject private var store: TodoStore

    let date: Date
    let displayedMonth: Date
    let selectedDate: Date
    let calendar: Calendar
    let onSelectDate: (Date) -> Void

    var body: some View {
        let items = store.items(on: date)
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
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.accentColor.opacity(item.isCompleted ? 0.05 : 0.13),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
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
            .opacity(belongsToMonth ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            date.formatted(.dateTime.year().month(.wide).day().locale(L10n.locale))
        )
        .accessibilityValue(L10n.format("%lld 项待办", items.count))
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
