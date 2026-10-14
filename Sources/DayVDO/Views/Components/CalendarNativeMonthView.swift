import AppKit
import SwiftUI

/// An opt-in, isolated comparison only. Release applications keep the established
/// scroll implementation until gesture and frame-time comparisons are complete.
enum CalendarNativeMonthExperiment {
    static var isEnabled: Bool {
        #if DEBUG
        Bundle.main.bundleIdentifier?.hasPrefix("com.wuyuchen.DayVDO.CompatibilityTest.") == true
            && Bundle.main.object(forInfoDictionaryKey: "DayVDONativeMonthPrototype") as? Bool == true
        #else
        false
        #endif
    }
}

/// Fixed document geometry: scrolling changes the clip origin, not the week layout.
struct CalendarNativeMonthGeometry {
    static let count = 209
    static let origin = 104
    static let visibleCount = 6
    var width: CGFloat
    var rowHeight: CGFloat

    var size: CGSize { CGSize(width: width, height: rowHeight * CGFloat(Self.count)) }
    func frame(at index: Int) -> CGRect {
        CGRect(x: 12, y: CGFloat(index) * rowHeight, width: max(1, width - 24), height: rowHeight)
    }
    func indices(in rect: CGRect) -> Range<Int> {
        guard rowHeight > 0, rect.minY.isFinite, rect.maxY.isFinite, !rect.isEmpty else { return 0..<0 }
        let first = max(0, min(Self.count, Int(floor(rect.minY / rowHeight))))
        let end = max(first, min(Self.count, Int(ceil(rect.maxY / rowHeight))))
        return first..<end
    }
    func clampedRow(_ row: CGFloat) -> CGFloat {
        min(CGFloat(Self.count - Self.visibleCount), max(0, row))
    }
}

struct CalendarNativeMonthView: NSViewRepresentable {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var selection: CalendarTodoSelection
    let calendar: Calendar
    let visibility: TodoFilterContext
    let topInset: CGFloat
    let displayedMonth: Date
    let selectedDate: Date
    let navigationID: UUID?
    let navigationDate: Date?
    let session: CalendarTimelineSession
    let select: (LocalDay) -> Void
    let visibleMonthChanged: (Date) -> Void
    let create: (LocalDay, LocalDay) -> Void
    let change: (TodoItem) -> Void
    let edit: (TodoItem) -> Void
    let showMore: (LocalDay) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> CalendarNativeMonthViewport {
        let view = CalendarNativeMonthViewport()
        context.coordinator.attach(view)
        return view
    }
    func updateNSView(_ view: CalendarNativeMonthViewport, context: Context) {
        context.coordinator.update(self)
    }
    static func dismantleNSView(_ view: CalendarNativeMonthViewport, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: CalendarNativeMonthView
        weak var viewport: CalendarNativeMonthViewport?
        let interaction = CalendarDateInteraction()
        private var anchor: LocalDay
        private var snapshot: CalendarWindowSnapshot?
        private var loaded = 0..<0
        private var lastNavigationID: UUID?
        private var month: Int
        private var monthDate: Date
        private var initialized = false
        private var changingGeometry = false
        private var appliedTopInset: CGFloat?
        private var observers: [NSObjectProtocol] = []
        private var eventMonitor: Any?
        private var settleTask: Task<Void, Never>?
        private let snapAnimator = CalendarNativeScrollAnimator()
        private var publishingMonth = false
        private var gestureStart: (row: CGFloat, time: TimeInterval)?
        private var gestureRelease: CalendarGestureSnapshot?
        private var lastSample: (row: CGFloat, time: TimeInterval)?
        private var releaseVelocity: CGFloat = 0

        init(_ parent: CalendarNativeMonthView) {
            self.parent = parent
            let initial = parent.session.topWeek?.date(timeZone: parent.calendar.timeZone)
                ?? CalendarMonthGrid.dates(containing: parent.displayedMonth, calendar: parent.calendar).first
                ?? parent.displayedMonth
            anchor = LocalDay(parent.calendar.dateInterval(of: .weekOfYear, for: initial)?.start ?? initial,
                              timeZone: parent.calendar.timeZone)
            month = parent.calendar.component(.month, from: parent.displayedMonth)
            monthDate = parent.calendar.dateInterval(of: .month, for: parent.displayedMonth)?.start ?? parent.displayedMonth
            lastNavigationID = parent.navigationID
        }

        func attach(_ view: CalendarNativeMonthViewport) {
            viewport = view
            view.collection.dataSource = self
            view.collection.delegate = self
            view.collection.register(CalendarNativeWeekCell.self,
                                     forItemWithIdentifier: CalendarNativeWeekCell.identifier)
            view.resized = { [weak self] in self?.resize() }
            view.scroll.contentView.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                object: view.scroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scrolled() }
                })
            observers.append(center.addObserver(forName: NSScrollView.didEndLiveScrollNotification,
                object: view.scroll, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleSettle() }
                })
            // Observe, rather than override NSScrollView.scrollWheel, so AppKit
            // remains responsible for native scrolling and momentum tracking.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.viewport, event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                if self.interaction.drag != nil || self.interaction.suppressed { return nil }
                self.wheel(event)
                return event
            }
            update(parent)
        }

        func update(_ value: CalendarNativeMonthView) {
            let visibilityChanged = parent.visibility != value.visibility
            parent = value
            guard let view = viewport else { return }
            view.headerHeight = value.topInset
            let input = view.input
            input.store = value.store; input.selection = value.selection; input.interaction = interaction
            input.resolveItem = { [weak store = value.store] in store?.item(withID: $0) }
            input.select = value.select; input.showMore = value.showMore
            input.create = value.create; input.change = value.change; input.edit = value.edit
            if visibilityChanged {
                if NSEvent.pressedMouseButtons & 1 != 0 { interaction.cancel() }
                else { interaction.release() }
            }
            if value.navigationID != lastNavigationID, let date = value.navigationDate {
                lastNavigationID = value.navigationID
                navigate(to: date)
            }
            prepareContent()
            refreshVisibleCells()
            resize()
        }

        private var row: CGFloat {
            guard let view = viewport else { return CGFloat(CalendarNativeMonthGeometry.origin) }
            return (view.scroll.contentView.bounds.minY + (appliedTopInset ?? 0))
                / max(1, view.weekLayout.geometry.rowHeight)
        }
        private func week(_ index: Int) -> LocalDay {
            anchor.adding(days: (index - CalendarNativeMonthGeometry.origin) * 7)
        }
        private func prepareContent() {
            let top = Int(row.rounded(.down))
            let range: Range<Int>
            if loaded.contains(top - 3), loaded.contains(top + 9) { range = loaded }
            else {
                let lower = min(CalendarNativeMonthGeometry.count - 30, max(0, top - 12))
                range = lower..<(lower + 30)
            }
            let key = CalendarWindowSnapshot.Key(revision: parent.store.contentRevision,
                firstDay: week(range.lowerBound), lastDay: week(range.upperBound - 1).adding(days: 6),
                timeZoneIdentifier: parent.calendar.timeZone.identifier,
                firstWeekday: parent.calendar.firstWeekday, visibility: parent.visibility)
            guard snapshot?.key != key else { return }
            // Prototype publishes a complete replacement in one step. There is
            // no nil/empty revision between the old and new visible weeks.
            snapshot = CalendarWindowSnapshot.build(key: key, items: parent.store.items, tags: parent.store.tags)
            loaded = range
        }

        private func resize() {
            guard let view = viewport, view.bounds.height >= 186, view.bounds.width > 24,
                  !changingGeometry else { return }
            let next = CalendarNativeMonthGeometry(width: view.bounds.width,
                rowHeight: max(1, view.bounds.height - view.topInset) / 6)
            guard next.size != view.weekLayout.geometry.size
                    || appliedTopInset != view.topInset else { return }
            snapAnimator.cancel()
            let preserved = initialized ? row : CGFloat(CalendarNativeMonthGeometry.origin)
            if interaction.drag != nil { interaction.cancel() }
            changingGeometry = true
            view.weekLayout.geometry = next
            view.weekLayout.invalidateLayout()
            view.collection.setFrameSize(next.size)
            view.collection.layoutSubtreeIfNeeded()
            // Reserve the bar in our document-coordinate math, keeping the
            // full native viewport available beneath the SwiftUI material.
            appliedTopInset = view.topInset
            view.scroll.contentView.scroll(to: CGPoint(x: 0,
                y: next.clampedRow(preserved) * next.rowHeight - view.topInset))
            view.scroll.reflectScrolledClipView(view.scroll.contentView)
            initialized = true
            changingGeometry = false
            scrolled()
        }

        private func scrolled() {
            guard initialized, !changingGeometry, let view = viewport else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if let previous = lastSample, now - previous.time >= 0.008 {
                releaseVelocity = (row - previous.row) / CGFloat(now - previous.time)
            }
            lastSample = (row, now)
            let oldKey = snapshot?.key
            prepareContent()
            if snapshot?.key != oldKey { refreshVisibleCells() }
            updateHitGeometry()
            parent.session.topWeek = week(Int(view.weekLayout.geometry.clampedRow(row).rounded()))
            let date = week(Int(row.rounded(.down)) + 3).date(timeZone: parent.calendar.timeZone)
            let next = parent.calendar.dateInterval(of: .month, for: date)?.start ?? date
            if next != monthDate {
                monthDate = next
                month = parent.calendar.component(.month, from: next)
                refreshVisibleCells()
                if !publishingMonth {
                    publishingMonth = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.viewport != nil else { return }
                        self.publishingMonth = false
                        self.parent.visibleMonthChanged(self.monthDate)
                    }
                }
            }
        }

        private func refreshVisibleCells() {
            guard let view = viewport else { return }
            for path in view.collection.indexPathsForVisibleItems() {
                if let cell = view.collection.item(at: path) as? CalendarNativeWeekCell {
                    configure(cell, at: path.item)
                }
            }
        }
        private func configure(_ cell: CalendarNativeWeekCell, at index: Int) {
            let day = week(index)
            let items = snapshot?.items(inWeek: day) ?? []
            let state = CalendarNativeWeekState(week: day,
                selected: LocalDay(parent.selectedDate, timeZone: parent.calendar.timeZone),
                month: month, items: items, visibility: parent.visibility)
            cell.configure(state: state, interaction: interaction, store: parent.store,
                selection: parent.selection, layout: snapshot?.dateLayoutsByWeek[day],
                select: parent.select, showMore: parent.showMore, edit: parent.edit)
            cell.regionsChanged = { [weak self] in self?.updateHitGeometry() }
        }
        private func updateHitGeometry() {
            guard let view = viewport else { return }
            interaction.viewport = view.bounds.size
            var frames: [LocalDay: CGRect] = [:]
            var regions: [CalendarDateHitRegion] = []
            for path in view.collection.indexPathsForVisibleItems().sorted() {
                let frame = view.collection.convert(view.weekLayout.geometry.frame(at: path.item), to: view)
                frames[week(path.item)] = frame
                if let cell = view.collection.item(at: path) as? CalendarNativeWeekCell {
                    regions += cell.regions.map {
                        CalendarDateHitRegion(frame: $0.frame.offsetBy(dx: frame.minX, dy: frame.minY), target: $0.target)
                    }
                }
            }
            interaction.frames = frames
            interaction.hitRegions = regions
        }

        private func navigate(to date: Date) {
            snapAnimator.cancel()
            settleTask?.cancel(); gestureStart = nil; gestureRelease = nil
            guard let target = CalendarMonthGrid.dates(containing: date, calendar: parent.calendar).first else { return }
            let day = LocalDay(target, timeZone: parent.calendar.timeZone)
            let index = CalendarNativeMonthGeometry.origin + CalendarScrollPolicy.weekOffset(
                from: anchor.date(timeZone: parent.calendar.timeZone), to: target, calendar: parent.calendar)
            if (52...(CalendarNativeMonthGeometry.count - 58)).contains(index) {
                scroll(to: CGFloat(index))
            } else {
                rebase(to: day)
            }
        }
        private func rebase(to day: LocalDay) {
            snapAnimator.cancel()
            guard let view = viewport else { return }
            changingGeometry = true
            anchor = day; snapshot = nil; loaded = 0..<0
            view.scroll.contentView.scroll(to: CGPoint(x: 0,
                y: CGFloat(CalendarNativeMonthGeometry.origin) * view.weekLayout.geometry.rowHeight - view.topInset))
            prepareContent()
            view.collection.reloadData()
            view.collection.layoutSubtreeIfNeeded()
            changingGeometry = false
            scrolled()
        }
        private func scroll(to target: CGFloat, animated: Bool = false,
                            completion: (() -> Void)? = nil) {
            guard let view = viewport else { return }
            snapAnimator.cancel()
            let y = view.weekLayout.geometry.clampedRow(target) * view.weekLayout.geometry.rowHeight - view.topInset
            let destination = NSPoint(x: 0, y: y)
            let update: (NSPoint) -> Void = { [weak self, weak view] origin in
                guard let self, let view else { return }
                view.scroll.contentView.scroll(to: origin)
                view.scroll.reflectScrolledClipView(view.scroll.contentView)
                self.scrolled()
            }
            if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                snapAnimator.start(from: view.scroll.contentView.bounds.origin, to: destination,
                    framesPerSecond: view.window?.screen?.maximumFramesPerSecond ?? 60,
                    update: update, completion: completion)
            } else {
                update(destination)
                completion?()
            }
        }
        private func wheel(_ event: NSEvent) {
            snapAnimator.cancel()
            settleTask?.cancel()
            let now = ProcessInfo.processInfo.systemUptime
            if event.phase == .began || (gestureStart == nil && event.momentumPhase.isEmpty) {
                gestureStart = (row, now); gestureRelease = nil
                lastSample = (row, now); releaseVelocity = 0
            }
            if event.phase == .ended, let start = gestureStart {
                gestureRelease = CalendarGestureSnapshot(startRow: start.row, currentRow: row,
                    duration: now - start.time, releaseVelocityInWeeksPerSecond: releaseVelocity,
                    usesPreciseDeltas: event.hasPreciseScrollingDeltas)
            }
            if event.phase.isEmpty && event.momentumPhase.isEmpty || event.momentumPhase == .ended {
                scheduleSettle()
            }
        }
        private func scheduleSettle() {
            settleTask?.cancel()
            settleTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                guard let self, let view = self.viewport else { return }
                let current = self.row
                var target = Int(current.rounded())
                if let released = self.gestureRelease {
                    let decision = CalendarScrollPolicy.destination(for: released)
                    let startMonth = self.parent.calendar.dateInterval(of: .month,
                        for: self.week(Int(released.startRow) + 3).date())?.start ?? self.monthDate
                    let direction = released.directMovementInWeeks >= 0 ? 1 : -1
                    let adjacent = self.parent.calendar.date(byAdding: .month, value: direction, to: startMonth)
                    let candidates = (-1...1).compactMap {
                        self.parent.calendar.date(byAdding: .month, value: $0, to: self.monthDate)
                    }.compactMap(self.monthRow)
                    target = CalendarScrollPolicy.targetIndex(for: decision, currentRow: current,
                        proposedMomentumRow: current, adjacentMonthIndex: adjacent.flatMap(self.monthRow),
                        monthCandidates: candidates)
                }
                let needsRebase = target < 52 || target > CalendarNativeMonthGeometry.count - 58
                let targetDay = self.week(Int(view.weekLayout.geometry.clampedRow(CGFloat(target))))
                self.scroll(to: CGFloat(target), animated: true) { [weak self] in
                    if needsRebase { self?.rebase(to: targetDay) }
                }
                self.gestureStart = nil; self.gestureRelease = nil; self.lastSample = nil
            }
        }
        private func monthRow(_ date: Date) -> Int? {
            guard let top = CalendarMonthGrid.dates(containing: date, calendar: parent.calendar).first else { return nil }
            return CalendarNativeMonthGeometry.origin + CalendarScrollPolicy.weekOffset(
                from: anchor.date(timeZone: parent.calendar.timeZone), to: top, calendar: parent.calendar)
        }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            CalendarNativeMonthGeometry.count
        }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: CalendarNativeWeekCell.identifier, for: indexPath)
            if let cell = cell as? CalendarNativeWeekCell { configure(cell, at: indexPath.item) }
            return cell
        }
        func stop() {
            snapAnimator.cancel()
            settleTask?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            viewport?.input.stop()
            viewport?.resized = nil
            viewport?.collection.dataSource = nil
            viewport?.collection.delegate = nil
            viewport = nil
        }
    }
}

/// Drive actual clip-view positions rather than relying on implicit animation
/// support for NSClipView.boundsOrigin. A cancelled snap never calls completion.
@MainActor
final class CalendarNativeScrollAnimator {
    private var timer: Timer?
    private struct Run {
        let id = UUID()
        let startTime: TimeInterval
        let from: NSPoint
        let to: NSPoint
        let curve: UnitCurve?
        let update: (NSPoint) -> Void
        let completion: (() -> Void)?
    }
    private var run: Run?

    func start(from: NSPoint, to: NSPoint, framesPerSecond: Int, curve: UnitCurve? = nil,
               update: @escaping (NSPoint) -> Void, completion: (() -> Void)? = nil) {
        cancel()
        guard abs(to.y - from.y) > 0.5 || abs(to.x - from.x) > 0.5 else {
            update(to)
            completion?()
            return
        }
        run = Run(startTime: ProcessInfo.processInfo.systemUptime, from: from, to: to, curve: curve,
                  update: update, completion: completion)
        let timer = Timer(timeInterval: 1 / Double(max(30, framesPerSecond)), repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let run else { return }
        let progress = min(1, (ProcessInfo.processInfo.systemUptime - run.startTime) / 0.24)
        let eased = CGFloat(run.curve?.value(at: progress) ?? (1 - pow(1 - progress, 3)))
        run.update(NSPoint(x: run.from.x + (run.to.x - run.from.x) * eased,
                           y: run.from.y + (run.to.y - run.from.y) * eased))
        if progress >= 1, self.run?.id == run.id {
            cancel()
            run.completion?()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        run = nil
    }
}

final class CalendarNativeMonthViewport: NSView {
    override var isFlipped: Bool { true }
    let scroll = NSScrollView()
    let collection = NSCollectionView()
    let weekLayout = CalendarNativeWeekLayout()
    let input = CalendarDateInput.InputView()
    let headerBackdrop = CalendarNativeHeaderBackdrop()
    private(set) var topInset: CGFloat = 0
    var headerHeight: CGFloat = 0 {
        didSet {
            if headerHeight != oldValue { needsLayout = true }
        }
    }
    var resized: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        collection.collectionViewLayout = weekLayout
        collection.backgroundColors = [.clear]
        collection.isSelectable = false
        scroll.documentView = collection
        addSubview(scroll); addSubview(input); addSubview(headerBackdrop)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let toolbarInset = max(0, window.map { convert($0.contentLayoutRect, from: nil).minY } ?? 0)
        topInset = headerHeight + toolbarInset
        scroll.frame = bounds; input.frame = bounds
        // The window already supplies its own toolbar material. Sample only
        // the date/weekday strip here, avoiding a second blur beneath it.
        headerBackdrop.frame = NSRect(x: 0, y: toolbarInset,
                                      width: bounds.width, height: headerHeight)
        resized?()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }
}

final class CalendarNativeHeaderBackdrop: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .titlebar
        blendingMode = .withinWindow
        state = .followsWindowActiveState
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class CalendarNativeWeekLayout: NSCollectionViewLayout {
    var geometry = CalendarNativeMonthGeometry(width: 1, rowHeight: 1)
    override var collectionViewContentSize: NSSize { geometry.size }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        geometry.indices(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard (0..<CalendarNativeMonthGeometry.count).contains(indexPath.item) else { return nil }
        let value = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        value.frame = geometry.frame(at: indexPath.item)
        return value
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { false }
}

private struct CalendarNativeWeekState: Equatable {
    let week: LocalDay
    let selected: LocalDay
    let month: Int
    let items: [CalendarWindowSnapshot.Item]
    let visibility: TodoFilterContext
}

private final class CalendarNativeWeekCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("CalendarNativeWeek")
    private var hosting: NSHostingView<AnyView>?
    private var state: CalendarNativeWeekState?
    var regions: [CalendarDateHitRegion] = []
    var regionsChanged: (() -> Void)?
    override func loadView() { view = NSView() }
    override func prepareForReuse() {
        super.prepareForReuse()
        state = nil; regions = []; regionsChanged = nil
    }
    func configure(state: CalendarNativeWeekState, interaction: CalendarDateInteraction,
                   store: TodoStore, selection: CalendarTodoSelection, layout: CalendarDateLayout?,
                   select: @escaping (LocalDay) -> Void, showMore: @escaping (LocalDay) -> Void,
                   edit: @escaping (TodoItem) -> Void) {
        guard self.state != state else { return }
        self.state = state
        let week = state.week
        let root = AnyView(CalendarDateWeekRow(interaction: interaction, week: week,
            selected: state.selected, month: state.month, items: state.items,
            visibility: state.visibility, preparedLayout: layout,
            select: select, showMore: showMore, edit: edit)
            .environmentObject(store).environmentObject(selection)
            .coordinateSpace(name: "calendarDateViewport")
            .onPreferenceChange(CalendarDateHitRegions.self) { [weak self] values in
                guard let self, self.state?.week == week else { return }
                let next = values[week] ?? []
                guard next != self.regions else { return }
                self.regions = next
                self.regionsChanged?()
            })
        if let hosting { hosting.rootView = root }
        else {
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            host.frame = view.bounds
            host.autoresizingMask = [.width, .height]
            view.addSubview(host)
            hosting = host
        }
    }
}
