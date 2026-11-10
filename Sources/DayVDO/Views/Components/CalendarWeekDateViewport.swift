import AppKit
import Combine
import SwiftUI

@MainActor
final class CalendarWeekPageActivity: ObservableObject {
    @Published var isActive: Bool
    init(isActive: Bool) { self.isActive = isActive }
}

/// AppKit owns the horizontal position throughout tracking, inertia and snapping.
/// Hosted weeks have fixed frames; changing the clip origin never relays through
/// SwiftUI ScrollPosition. The axis material is a sibling above the same viewport.
struct CalendarWeekDateViewport<Content: View>: NSViewRepresentable {
    let week: LocalDay
    let firstDay: LocalDay
    var leadingInset: CGFloat = 0
    var navigationID: UUID?
    var navigationDay: LocalDay?
    var animatesScroll = true
    /// Omit scroll positions; bindings and observed models update hosted pages.
    var contentVersion: AnyHashable?
    var axis: AnyView = AnyView(EmptyView())
    var visibleDayChanged: (LocalDay) -> Void = { _ in }
    var settledAtDay: (LocalDay) -> Void
    @ViewBuilder var content: (LocalDay) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> CalendarWeekNativeViewport {
        let view = CalendarWeekNativeViewport()
        context.coordinator.attach(view)
        return view
    }
    func updateNSView(_ view: CalendarWeekNativeViewport, context: Context) {
        context.coordinator.update(self, environment: context.environment)
    }
    static func dismantleNSView(_ view: CalendarWeekNativeViewport, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor final class Coordinator {
        private var parent: CalendarWeekDateViewport
        private weak var view: CalendarWeekNativeViewport?
        private var anchor: LocalDay
        private let radius = 52
        private struct HostedWeek {
            let view: NSHostingView<AnyView>
            let activity: CalendarWeekPageActivity
        }
        private var hosts: [Int: HostedWeek] = [:]
        private var width: CGFloat = 0
        private var height: CGFloat = 0
        private var displayedFirstDay: LocalDay
        private var appliedFirstDay: LocalDay
        private var lastNavigationID: UUID?
        private var visibleDay: LocalDay?
        private var environment = EnvironmentValues()
        private var layingOut = false
        private var publication: Task<Void, Never>?
        private var hasRenderedContent = false
        init(_ parent: CalendarWeekDateViewport) {
            self.parent = parent; anchor = parent.week; displayedFirstDay = parent.firstDay
            appliedFirstDay = parent.firstDay
            lastNavigationID = parent.navigationID
        }
        func attach(_ view: CalendarWeekNativeViewport) {
            self.view = view
            view.resized = { [weak self] in self?.resize() }
            view.scroll.scrolled = { [weak self] in self?.scrolled() }
            view.scroll.settled = { [weak self] in self?.settled() }
            view.resolveDay = { [weak self] point in
                guard let self, let view = self.view, self.columnWidth > 0,
                      point.x >= self.parent.leadingInset, point.x < view.bounds.width else { return nil }
                let column = Int(floor((view.scroll.contentView.bounds.minX + point.x) / self.columnWidth))
                return self.anchor.adding(days: column - self.radius * 7)
            }
        }
        func update(_ parent: CalendarWeekDateViewport, environment: EnvironmentValues) {
            let contentChanged = !hasRenderedContent || parent.contentVersion == nil
                || self.parent.contentVersion != parent.contentVersion
                || self.environment.colorScheme != environment.colorScheme
                || self.environment.colorSchemeContrast != environment.colorSchemeContrast
                || self.environment.locale != environment.locale
                || self.environment.dynamicTypeSize != environment.dynamicTypeSize
                || self.environment.layoutDirection != environment.layoutDirection
                || self.environment.isEnabled != environment.isEnabled
                || self.environment.accessibilityReduceMotion != environment.accessibilityReduceMotion
            self.parent = parent; self.environment = environment
            guard let view else { return }
            view.leadingInset = parent.leadingInset
            view.scroll.animatesScroll = parent.animatesScroll
            if contentChanged {
                view.axis.rootView = AnyView(parent.axis.environment(\.self, environment))
            }
            let explicitNavigation = lastNavigationID != parent.navigationID
            lastNavigationID = parent.navigationID
            // A native navigation is published on the next SwiftUI turn. An
            // unrelated parent refresh can still carry the previous input day;
            // only a changed input is a new command, never a reason to jump back.
            let rangeChanged = appliedFirstDay != parent.firstDay
            appliedFirstDay = parent.firstDay
            let target = explicitNavigation ? (parent.navigationDay ?? parent.firstDay) : parent.firstDay
            if explicitNavigation || rangeChanged {
                displayedFirstDay = target
                view.scroll.resetGesture()
                if abs(anchor.distance(to: target)) > (radius - 4) * 7 { rebase(to: target) }
                scroll(to: target)
            }
            resize()
            if contentChanged {
                for (index, host) in hosts { host.view.rootView = page(index, activity: host.activity) }
                hasRenderedContent = true
            }
            if explicitNavigation { publish(target, settled: true) }
        }
        private var columnWidth: CGFloat { width / 7 }
        private func day(_ index: Int) -> LocalDay { anchor.adding(days: (index - radius) * 7) }
        private func page(_ index: Int, activity: CalendarWeekPageActivity) -> AnyView {
            AnyView(parent.content(day(index)).environmentObject(activity).environment(\.self, environment))
        }
        private func resize() {
            guard let view, !layingOut else { return }
            let newWidth = max(1, view.bounds.width - parent.leadingInset)
            let newHeight = view.bounds.height
            guard newHeight > 0, abs(newWidth - width) > 0.01 || abs(newHeight - height) > 0.01 else { return }
            view.cancelDrag()
            layingOut = true
            view.scroll.resetGesture()
            width = newWidth; height = newHeight
            view.scroll.columnWidth = columnWidth
            view.scroll.leadingInset = parent.leadingInset
            view.document.frame = CGRect(x: 0, y: 0, width: width * CGFloat(radius * 2 + 1), height: height)
            view.scroll.contentInsets = NSEdgeInsets(top: 0, left: parent.leadingInset, bottom: 0, right: 0)
            for (index, host) in hosts { host.view.frame = frame(index) }
            scroll(to: displayedFirstDay)
            layingOut = false
            scrolled()
        }
        private func frame(_ index: Int) -> CGRect { CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height) }
        private func scroll(to day: LocalDay) {
            guard let view, width > 0 else { return }
            let x = CGFloat(radius * 7 + anchor.distance(to: day)) * columnWidth - parent.leadingInset
            view.scroll.contentView.scroll(to: CGPoint(x: x, y: 0))
            view.scroll.reflectScrolledClipView(view.scroll.contentView)
            scrolled()
        }
        private func scrolled() {
            guard let view, width > 0, !layingOut else { return }
            let rect = view.scroll.contentView.bounds
            // Include the entire covered strip and prebuild neighboring weeks.
            // These are ordinary hosted views, so a covered column is not culled.
            let first = Int(floor((rect.minX + parent.leadingInset) / width))
            let last = Int(floor((rect.maxX - 0.01) / width))
            let range = max(0, first - 1)...min(radius * 2, last + 1)
            let column = Int(((rect.minX + parent.leadingInset) / columnWidth).rounded())
            let active = activeRange(column: column)
            for index in range where hosts[index] == nil {
                let activity = CalendarWeekPageActivity(isActive: active.contains(index))
                let host = NSHostingView(rootView: page(index, activity: activity))
                host.sizingOptions = []
                host.frame = frame(index)
                view.document.addSubview(host)
                hosts[index] = HostedWeek(view: host, activity: activity)
            }
            for index in Array(hosts.keys) where !range.contains(index) {
                // The native mouse responder keeps receiving the gesture after
                // its starting week leaves the visible cache.
                if let owner = view.dragOwner, let host = hosts[index], owner.isDescendant(of: host.view) { continue }
                hosts.removeValue(forKey: index)?.view.removeFromSuperview()
            }
            let offset = column - radius * 7
            let day = anchor.adding(days: offset)
            guard day != visibleDay else { return }
            visibleDay = day
            publish(day)
        }
        private func publish(_ day: LocalDay, settled: Bool = false) {
            publication?.cancel()
            // Bounds notifications can arrive during representable layout.
            publication = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                let active = self.activeRange(column: self.radius * 7 + self.anchor.distance(to: day))
                for (index, host) in self.hosts where host.activity.isActive != active.contains(index) {
                    host.activity.isActive = active.contains(index)
                }
                self.parent.visibleDayChanged(day)
                if settled { self.parent.settledAtDay(day) }
            }
        }
        private func activeRange(column: Int) -> ClosedRange<Int> {
            let first = max(0, (column - 1) / 7)
            return first...max(first, min(radius * 2, (column + 7) / 7))
        }
        private func settled() {
            guard let day = visibleDay else { return }
            displayedFirstDay = day
            parent.settledAtDay(day)
            if abs(anchor.distance(to: day)) >= (radius - 4) * 7 { rebase(to: day); scroll(to: day) }
        }
        private func rebase(to day: LocalDay) {
            anchor = anchor.adding(days: Int(floor(Double(anchor.distance(to: day)) / 7)) * 7)
            hosts.values.forEach { $0.view.removeFromSuperview() }; hosts.removeAll()
        }
        func stop() {
            view?.endDrag(settles: false)
            publication?.cancel(); view?.scroll.stop()
            view?.resized = nil; view?.scroll.scrolled = nil; view?.scroll.settled = nil
            view?.resolveDay = nil
        }
    }
}

final class CalendarWeekNativeViewport: NSView {
    override var isFlipped: Bool { true }
    let scroll = CalendarWeekHorizontalScrollView()
    let document = FlippedView()
    let backdrop = NSVisualEffectView()
    let axis = NSHostingView(rootView: AnyView(EmptyView()))
    var leadingInset: CGFloat = 0 { didSet { if oldValue != leadingInset { needsLayout = true } } }
    var resized: (() -> Void)?
    var resolveDay: ((CGPoint) -> LocalDay?)?
    private(set) weak var dragOwner: NSView?
    private var dragPoint = CGPoint.zero
    private var dragUpdate: ((CGPoint) -> Void)?
    private var dragCancellation: (() -> Void)?
    private var dragDirection = 0
    private var dragTimer: Timer?

    func day(at point: CGPoint) -> LocalDay? { resolveDay?(point) }

    func trackDrag(from owner: NSView, at point: CGPoint, cancel: @escaping () -> Void,
                   update: @escaping (CGPoint) -> Void) {
        if dragOwner == nil { scroll.resetGesture() }
        dragOwner = owner; dragPoint = point; dragUpdate = update; dragCancellation = cancel
        let direction = CalendarWeekDragScrollPolicy.direction(at: point, in: bounds, leadingInset: leadingInset)
        guard direction != dragDirection else { return }
        dragTimer?.invalidate(); dragTimer = nil
        dragDirection = direction
        guard direction != 0 else { return }
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.dragOwner != nil else { return }
                self.scroll.scrollDuringDrag(days: self.dragDirection) { [weak self] in
                    guard let self else { return }
                    self.dragUpdate?(self.dragPoint)
                }
            }
        }
        dragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func endDrag(settles: Bool = true) {
        guard dragOwner != nil else { return }
        dragTimer?.invalidate(); dragTimer = nil; dragDirection = 0
        dragOwner = nil; dragUpdate = nil; dragCancellation = nil
        scroll.resetGesture()
        if settles {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.dragOwner == nil else { return }
                self.scroll.settled?()
            }
        }
    }
    func cancelDrag() { dragCancellation?() }
    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = document
        backdrop.material = .headerView; backdrop.blendingMode = .withinWindow
        backdrop.state = .followsWindowActiveState
        axis.sizingOptions = []
        addSubview(scroll); addSubview(backdrop); addSubview(axis)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        scroll.frame = bounds
        backdrop.frame = CGRect(x: 0, y: 0, width: leadingInset, height: bounds.height)
        axis.frame = backdrop.frame
        resized?()
    }
    final class FlippedView: NSView { override var isFlipped: Bool { true } }
}

/// Routes just the horizontal gesture out of nested vertical panes. Native
/// The OS supplies momentum deltas; only this clip view applies their movement.
final class CalendarWeekHorizontalScrollView: NSScrollView {
    enum Motion { case idle, tracking, waitingForMomentum, momentum, snapping, settled }
    private(set) var motion = Motion.idle
    var columnWidth: CGFloat = 1
    var leadingInset: CGFloat = 0
    var animatesScroll = true
    var scrolled: (() -> Void)?
    var settled: (() -> Void)?
    private var monitor: Any?
    private var boundsObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var horizontal: Bool?
    private var contactTime: TimeInterval?
    private var ignoresMomentum = false
    private var processingWheel = false
    private var start: (row: CGFloat, time: TimeInterval)?
    private var samples: [(row: CGFloat, time: TimeInterval)] = []
    private var release: CalendarGestureSnapshot?
    private var fallback: Timer?
    private let animator = CalendarNativeScrollAnimator()
    private var row: CGFloat { (contentView.bounds.minX + leadingInset) / columnWidth }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        guard window != nil else { return }
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrolled?() }
            }
        endObserver = NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification,
            object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.processingWheel, self.motion == .idle else { return }
                    self.snap()
                }
            }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.route(event) == true ? nil : event
        }
    }
    override func scrollWheel(with event: NSEvent) {
        // Vertical events bubble here from a nested pane only at its boundary.
        // Never convert them to a horizontal gesture.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { _ = route(event) }
    }
    @discardableResult func route(_ event: NSEvent, pressedMouseButtons: Int = NSEvent.pressedMouseButtons) -> Bool {
        guard event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)),
              !event.modifierFlags.contains(.control), pressedMouseButtons == 0 else { return false }
        let directBegin = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        if directBegin {
            resetGesture(); ignoresMomentum = false
            contactTime = event.timestamp
        }
        if !event.momentumPhase.isEmpty && ignoresMomentum { return true }
        if horizontal == nil || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            if max(abs(event.scrollingDeltaX), abs(event.scrollingDeltaY)) > 0.01 {
                horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }
        }
        guard horizontal == true else { return false }
        if start == nil && (event.phase.contains(.ended) || event.phase.contains(.cancelled)) { return true }
        processingWheel = true; defer { processingWheel = false }
        if !event.momentumPhase.isEmpty {
            guard motion == .waitingForMomentum || motion == .momentum else { return true }
            fallback?.invalidate(); motion = .momentum
            move(with: event)
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { snap() }
            return true
        }
        if motion != .tracking {
            animator.cancel(); fallback?.invalidate(); ignoresMomentum = false
            motion = .tracking; start = (row, contactTime ?? event.timestamp)
            release = nil; samples = [(row, event.timestamp)]
        }
        move(with: event)
        // Use event timestamps and a 100 ms sample window, as month view does.
        // A final zero-delta release must not turn a fast flick into a slow drag.
        if abs(event.scrollingDeltaX) > 0.01 {
            samples.append((row, event.timestamp))
            while samples.count > 2 && event.timestamp - samples[1].time > CalendarScrollPolicy.velocitySampleWindow {
                samples.removeFirst()
            }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            finishDirect(at: event.timestamp, precise: event.hasPreciseScrollingDeltas)
        } else if event.phase.isEmpty {
            // Mouse wheels have no release phases. Coalesce their ticks, without
            // cancelling an animation on every tick or delaying phased gestures.
            scheduleFallback { [weak self] in self?.finishDirect(at: event.timestamp, precise: false) }
        }
        return true
    }
    private func move(with event: NSEvent) {
        // Applying the OS pixel deltas directly avoids NSScrollView's additional
        // asynchronous wheel animation competing with the release snap.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * horizontalLineScroll
        let maximum = max(-leadingInset, (documentView?.bounds.width ?? 0) - bounds.width)
        let x = min(maximum, max(-leadingInset, contentView.bounds.minX - delta))
        contentView.scroll(to: CGPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
    private func finishDirect(at time: TimeInterval, precise: Bool) {
        guard motion == .tracking, let start else { return }
        let first = samples.first ?? (row, time)
        let last = samples.last ?? first
        let velocity = (last.row - first.row) / CGFloat(max(0.001, last.time - first.time))
        let snapshot = CalendarGestureSnapshot(startRow: start.row, currentRow: row,
            duration: max(0, time - start.time), releaseVelocityInWeeksPerSecond: velocity,
            usesPreciseDeltas: precise)
        release = snapshot
        if case .momentumMonth = CalendarScrollPolicy.destination(for: snapshot) {
            motion = .waitingForMomentum
            scheduleFallback { [weak self] in
                guard let self, self.motion == .waitingForMomentum else { return }
                self.snap()
            }
        } else { snap() }
    }
    private func scheduleFallback(_ action: @escaping @MainActor () -> Void) {
        fallback?.invalidate()
        let timer = Timer(timeInterval: 0.032, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        fallback = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func snap() {
        guard motion != .snapping && motion != .settled else { return }
        fallback?.invalidate(); ignoresMomentum = true; motion = .snapping
        let target = CalendarWeekScrollPolicy.targetDay(release: release, currentDay: row)
        let maximum = max(-leadingInset, (documentView?.bounds.width ?? 0) - bounds.width)
        let x = min(maximum, max(-leadingInset, CGFloat(target) * columnWidth - leadingInset))
        start = nil; release = nil; samples.removeAll()
        let update: (NSPoint) -> Void = { [weak self] point in
            guard let self else { return }
            self.contentView.scroll(to: point); self.reflectScrolledClipView(self.contentView)
        }
        let complete: () -> Void = { [weak self] in
            guard let self else { return }
            self.motion = .settled; self.settled?()
        }
        if !animatesScroll || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            update(CGPoint(x: x, y: 0)); complete()
        } else {
            animator.start(from: contentView.bounds.origin, to: CGPoint(x: x, y: 0),
                framesPerSecond: window?.screen?.maximumFramesPerSecond ?? 60, curve: .easeInOut,
                update: update, completion: complete)
        }
    }
    func resetGesture() {
        if motion != .idle { ignoresMomentum = true }
        fallback?.invalidate(); animator.cancel()
        motion = .idle; horizontal = nil; contactTime = nil
        start = nil; release = nil; samples.removeAll()
    }
    func scrollDuringDrag(days: Int, update: @escaping () -> Void) {
        let maximum = max(-leadingInset, (documentView?.bounds.width ?? 0) - bounds.width)
        let target = CGPoint(x: min(maximum, max(-leadingInset,
            contentView.bounds.minX + CGFloat(days) * columnWidth)), y: 0)
        let apply: (CGPoint) -> Void = { [weak self] point in
            guard let self else { return }
            self.contentView.scroll(to: point)
            self.reflectScrolledClipView(self.contentView)
            update()
        }
        if !animatesScroll || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            apply(target)
        } else {
            animator.start(from: contentView.bounds.origin, to: target,
                framesPerSecond: window?.screen?.maximumFramesPerSecond ?? 60, curve: .easeInOut,
                update: apply, completion: {})
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        monitor = nil; boundsObserver = nil; endObserver = nil
        resetGesture()
    }
}

enum CalendarWeekDragScrollPolicy {
    static func direction(at point: CGPoint, in bounds: CGRect, leadingInset: CGFloat) -> Int {
        guard point.y >= bounds.minY, point.y < bounds.maxY,
              point.x >= leadingInset, point.x < bounds.maxX else { return 0 }
        if point.x < leadingInset + 28 { return -1 }
        if point.x > bounds.maxX - 28 { return 1 }
        return 0
    }
}

/// Keeps the original schedule's gesture attached while its week scrolls away.
struct CalendarWeekDragAnchor: NSViewRepresentable {
    let view: AnchorView
    func makeNSView(context: Context) -> AnchorView { view }
    func updateNSView(_ view: AnchorView, context: Context) {}

    final class AnchorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        private var viewport: CalendarWeekNativeViewport? { calendarWeekViewport }
        var isInWeekViewport: Bool { viewport != nil }
        func day(at point: CGPoint) -> LocalDay? {
            guard point.y >= 0, point.y < bounds.height, let viewport else { return nil }
            return viewport.day(at: convert(point, to: viewport))
        }
        func track(at point: CGPoint, cancel: @escaping () -> Void, update: @escaping (CGPoint) -> Void) {
            guard let viewport else { return }
            viewport.trackDrag(from: self, at: convert(point, to: viewport), cancel: cancel) { [weak self, weak viewport] point in
                guard let self, let viewport else { return }
                update(self.convert(point, from: viewport))
            }
        }
        func endDrag() {
            guard let viewport, viewport.dragOwner === self else { return }
            viewport.endDrag()
        }
    }
}

extension NSView {
    var calendarWeekViewport: CalendarWeekNativeViewport? {
        var ancestor = superview
        while let view = ancestor {
            if let viewport = view as? CalendarWeekNativeViewport { return viewport }
            ancestor = view.superview
        }
        return nil
    }
}

/// Month view measures direct movement in rows (weeks). Here the same gesture
/// is measured in columns (days), and its large snap boundary is a week.
enum CalendarWeekScrollPolicy {
    static func targetDay(release: CalendarGestureSnapshot?, currentDay: CGFloat) -> Int {
        guard let release else { return Int(currentDay.rounded()) }
        switch CalendarScrollPolicy.destination(for: release) {
        case .none:
            return Int(release.startRow.rounded())
        case let .nearestWeek(direction):
            return CalendarScrollPolicy.nearestWeekIndex(for: currentDay, direction: direction)
        case let .adjacentMonth(direction):
            return Int(floor(release.startRow / 7)) * 7 + direction.rawValue * 7
        case let .momentumMonth(direction):
            return CalendarScrollPolicy.nearestWeekIndex(for: currentDay / 7, direction: direction) * 7
        }
    }
}
