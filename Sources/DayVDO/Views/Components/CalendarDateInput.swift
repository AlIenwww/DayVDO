import AppKit
import Combine
import SwiftUI

struct CalendarDateHitRegion: Equatable {
    enum Target: Equatable {
        case item(UUID, startsHere: Bool, endsHere: Bool)
        case more(LocalDay)
    }
    var frame: CGRect
    var target: Target

    func mode(at point: CGPoint) -> CalendarDateDragMode {
        guard case let .item(_, startsHere, endsHere) = target else { return .create }
        if startsHere, point.x < frame.minX + 7 { return .start }
        if endsHere, point.x >= frame.maxX - 7 { return .end }
        return .move
    }
}

struct CalendarDateHitRegions: PreferenceKey {
    static let defaultValue: [LocalDay: [CalendarDateHitRegion]] = [:]
    static func reduce(value: inout [LocalDay: [CalendarDateHitRegion]], nextValue: () -> [LocalDay: [CalendarDateHitRegion]]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Each hosted week owns geometry without publishing it back into SwiftUI.
@MainActor
final class CalendarDateHitRegionSource {
    let changed = PassthroughSubject<[CalendarDateHitRegion], Never>()
    var regions: [CalendarDateHitRegion] = [] {
        didSet { if oldValue != regions { changed.send(regions) } }
    }
}

/// One mouse responder owns the entire gesture, even when a lazy week row disappears.
struct CalendarDateInput: NSViewRepresentable {
    @EnvironmentObject private var selection: CalendarTodoSelection
    @ObservedObject var interaction: CalendarDateInteraction
    let store: TodoStore
    var regionSource: CalendarDateHitRegionSource? = nil
    var select: (LocalDay) -> Void
    var showMore: (LocalDay) -> Void
    var create: (LocalDay, LocalDay) -> Void
    var change: (TodoItem) -> Void
    var edit: (TodoItem) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.selection = selection; view.store = store
        view.interaction = interaction
        view.regionSource = regionSource
        view.resolveItem = { store.item(withID: $0) }
        view.select = select; view.showMore = showMore; view.create = create
        view.change = change; view.edit = edit
        let regions = regionSource?.regions ?? interaction.hitRegions
        if view.regions != regions {
            view.regions = regions
        }
        if interaction.suppressed { view.stopWeekScrolling() }
    }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.stop() }

    final class InputView: NSView {
        override var isFlipped: Bool { true }
        var selection: CalendarTodoSelection?
        var store: TodoStore?
        var interaction: CalendarDateInteraction? {
            didSet {
                guard oldValue !== interaction else { return }
                subscribeToRegions()
            }
        }
        var regionSource: CalendarDateHitRegionSource? {
            didSet {
                if oldValue !== regionSource { subscribeToRegions() }
            }
        }
        private var regionsSubscription: AnyCancellable?
        private func subscribeToRegions() {
            let publisher = regionSource?.changed ?? interaction?.hitRegionsChanged
            regionsSubscription = publisher?.sink { [weak self] regions in self?.regions = regions }
            regions = regionSource?.regions ?? interaction?.hitRegions ?? []
        }
        var regions: [CalendarDateHitRegion] = [] {
            didSet {
                if oldValue != regions { window?.invalidateCursorRects(for: self) }
            }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            for region in regions {
                guard case let .item(_, startsHere, endsHere) = region.target else { continue }
                if startsHere {
                    registerResizeCursor(CGRect(x: region.frame.minX, y: region.frame.minY,
                                                width: min(7, region.frame.width), height: region.frame.height))
                }
                if endsHere {
                    registerResizeCursor(CGRect(x: max(region.frame.minX, region.frame.maxX - 7), y: region.frame.minY,
                                                width: min(7, region.frame.width), height: region.frame.height))
                }
            }
        }

        private func registerResizeCursor(_ rect: CGRect) {
            let visible = rect.intersection(visibleRect)
            guard !visible.isNull, !visible.isEmpty else { return }
            addCursorRect(visible, cursor: .resizeLeftRight)
        }
        var resolveItem: (UUID) -> TodoItem? = { _ in nil }
        var select: (LocalDay) -> Void = { _ in }
        var showMore: (LocalDay) -> Void = { _ in }
        var create: (LocalDay, LocalDay) -> Void = { _, _ in }
        var change: (TodoItem) -> Void = { _ in }
        var edit: (TodoItem) -> Void = { _ in }
        private struct Press {
            var point: CGPoint
            var item: TodoItem?
            var mode: CalendarDateDragMode
            var day: LocalDay
            var more: LocalDay?
            var clickCount: Int
        }
        private var press: Press?
        private var dragging = false
        private var keyMonitor: Any?
        private var releaseMonitor: Any?
        private var observers: [NSObjectProtocol] = []

        private var weekViewport: CalendarWeekNativeViewport? {
            calendarWeekViewport
        }

        func stopWeekScrolling() {
            guard let viewport = weekViewport, viewport.dragOwner === self else { return }
            viewport.endDrag()
        }

        private func day(at point: CGPoint) -> LocalDay? {
            if let viewport = weekViewport {
                guard point.y >= 0, point.y < bounds.height else { return nil }
                return viewport.day(at: convert(point, to: viewport))
            }
            return interaction?.day(at: point)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Wheel events keep reaching the existing SwiftUI scroll view underneath.
            if NSApp.currentEvent?.type == .scrollWheel { return nil }
            return super.hitTest(point)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { true }
        @objc func copy(_ sender: Any?) { if let store { selection?.copy(store) } }
        @objc func paste(_ sender: Any?) { if let store { selection?.paste(store) } }
        override func deleteBackward(_ sender: Any?) { if let store { selection?.requestDelete(store) } }
        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "c" { copy(nil); return }
                if event.charactersIgnoringModifiers == "v" { paste(nil); return }
            }
            if event.keyCode == 51 || event.keyCode == 117 { deleteBackward(nil); return }
            if event.keyCode == 36, let item = store?.item(withID: selection?.selectedID) { edit(item); return }
            if event.keyCode == 53 { selection?.selectedID = nil; return }
            super.keyDown(with: event)
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            let point = convert(event.locationInWindow, from: nil)
            guard let day = day(at: point), let store else { return nil }
            window?.makeFirstResponder(self)
            selection?.day = day
            let hit = regions.first { $0.frame.contains(point) }
            if case let .item(id, _, _) = hit?.target { selection?.selectedID = id }
            else { selection?.selectedID = nil }
            select(day)
            let menu = NSMenu()
            func add(_ title: String, tag: Int, enabled: Bool = true) {
                let entry = NSMenuItem(title: L10n.string(title), action: #selector(menuAction(_:)), keyEquivalent: "")
                entry.target = self; entry.tag = tag; entry.isEnabled = enabled; menu.addItem(entry)
            }
            menu.autoenablesItems = false
            if let item = store.item(withID: selection?.selectedID) {
                add("编辑", tag: 0)
                add(item.isCompleted ? "标记为未完成" : "标记为已完成", tag: 1, enabled: store.canModify)
                if item.status != .notStarted { add("标记为未开始", tag: 7, enabled: store.canModify) }
                add("标记为进行中", tag: 2, enabled: item.status != .inProgress && store.canModify)
                menu.addItem(.separator())
                add("拷贝", tag: 3)
                add("粘贴", tag: 4, enabled: store.canModify && NSPasteboard.general.data(forType: CalendarTodoSelection.pasteboardType) != nil)
                menu.addItem(.separator())
                add("删除", tag: 5, enabled: store.canModify)
            } else {
                add("新建待办", tag: 6, enabled: store.canModify)
                add("粘贴", tag: 4, enabled: store.canModify && NSPasteboard.general.data(forType: CalendarTodoSelection.pasteboardType) != nil)
            }
            return menu
        }
        @objc private func menuAction(_ sender: NSMenuItem) {
            guard let store, let selection else { return }
            let item = store.item(withID: selection.selectedID)
            switch sender.tag {
            case 0: if let item { edit(item) }
            case 1: if let item { _ = store.toggle(item) }
            case 2: if let item { _ = store.setStatus(.inProgress, for: item) }
            case 3: copy(nil)
            case 4: paste(nil)
            case 5: deleteBackward(nil)
            case 6: create(selection.day, selection.day)
            case 7: if let item { _ = store.setStatus(.notStarted, for: item) }
            default: break
            }
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            pointerDown(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
        }
        override func mouseDragged(with event: NSEvent) {
            pointerDragged(to: convert(event.locationInWindow, from: nil))
        }
        override func mouseUp(with event: NSEvent) {
            pointerUp(at: convert(event.locationInWindow, from: nil))
        }

        func pointerDown(at point: CGPoint, clickCount: Int) {
            guard let interaction, !interaction.suppressed, let day = day(at: point) else { return }
            let region = regions.first { $0.frame.contains(point) }
            var item: TodoItem?
            var more: LocalDay?
            if case let .item(id, _, _) = region?.target {
                guard let latest = resolveItem(id) else { return }
                item = latest
            }
            if case let .more(day) = region?.target { more = day }
            let mode = region?.mode(at: point) ?? .create
            press = Press(point: point, item: item, mode: mode, day: day, more: more, clickCount: clickCount)
            dragging = false
            if let item {
                selection?.selectedID = item.id
                selection?.day = day
                select(day)
            }
        }
        func pointerDragged(to point: CGPoint) {
            guard let press, press.more == nil, let interaction, !interaction.suppressed else { return }
            guard dragging || hypot(point.x - press.point.x, point.y - press.point.y) >= 4 else { return }
            dragging = true
            if let target = day(at: point) {
                interaction.update(anchor: press.day, target: target, item: press.item, mode: press.mode)
            }
            if let viewport = weekViewport {
                viewport.trackDrag(from: self, at: convert(point, to: viewport),
                    cancel: { [weak self] in self?.cancelPress() }) { [weak self, weak viewport] point in
                    guard let self, let viewport else { return }
                    self.pointerDragged(to: self.convert(point, from: viewport))
                }
            }
        }
        func pointerUp(at point: CGPoint) {
            defer { resetPress() }
            guard let press, let interaction, !interaction.suppressed, day(at: point) != nil else { return }
            if dragging {
                pointerDragged(to: point)
                interaction.finish(isValidTarget: true, create: create, change: change)
            } else if let more = press.more { selection?.selectedID = nil; showMore(more) }
            else if press.clickCount == 2, let item = press.item { edit(resolveItem(item.id) ?? item) }
            else if press.item == nil { selection?.selectedID = nil; selection?.day = press.day; select(press.day) }
        }
        func cancelPress() {
            guard press != nil else { return }
            stopWeekScrolling()
            interaction?.cancel()
        }
        private func resetPress() {
            guard press != nil else { return }
            let viewport = weekViewport
            press = nil; dragging = false
            interaction?.release()
            viewport?.endDrag()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, event.keyCode == 53, self.press != nil else { return event }
                self.cancelPress(); return nil
            }
            releaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetPress() }
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelPress() }
                })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if NSEvent.pressedMouseButtons & 1 == 0 { self?.resetPress() }
                    }
                })
        }
        func stop() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []; keyMonitor = nil; releaseMonitor = nil
            resetPress()
        }
    }
}
