import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Only the active project's list observes hover changes. The page, headers,
/// and unchanged row content do not participate in each reorder update.
struct ProjectTaskList: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let project: TodoProject
    let children: [TodoItem]
    @Binding var editingItem: TodoItem?
    let today: LocalDay
    @StateObject var drag = ProjectTaskDragSession()

    var body: some View {
        let items = drag.orderedChildren(children)
        let offsets = drag.offsets(for: children, ordered: items)
        ProjectTaskStackLayout(context: .init(
            revision: store.contentRevision, ids: children.map(\.id), today: today,
            locale: L10n.locale.identifier, dynamicTypeSize: dynamicTypeSize
        )) {
            // Keep structural order fixed during hover. Reordering ForEach
            // relayouts every native row; offsets only move their presentation.
            ForEach(children) { item in
                ProjectTaskDragRow(
                    item: item, isFirst: item.id == items.first?.id,
                    isLast: item.id == items.last?.id,
                    isDragging: drag.preview?.itemID == item.id,
                    today: today, localeIdentifier: L10n.locale.identifier,
                    project: project, editingItem: $editingItem, drag: drag
                )
                .equatable()
                .offset(y: offsets[item.id, default: 0])
            }
            Color.clear
                .frame(height: 20)
                .contentShape(Rectangle())
                .padding(.leading, 28)
                .onDrop(of: [.text], delegate: drag.delegate(
                    projectID: project.id, targetID: nil, store: store, animation: animation
                ))
        }
        .padding(.top, 5)
        .background { FrameUpdateAnchor(scheduler: drag.scheduler) }
        .onDisappear { drag.cancel(animation: nil) }
        // Filtering or model changes invalidate the captured ordering. Hover
        // itself never changes the store, so this does not interrupt reordering.
        .onChange(of: children) { _, _ in drag.cancel(animation: nil) }
    }

    private var animation: Animation? {
        store.settings.animation(.spring(duration: 0.32, bounce: 0.16), for: .projectReorder, reduceMotion: reduceMotion)
    }
}

/// Hover only changes offsets. Reuse the measured row sizes instead of asking
/// every hosting/drop view for its intrinsic size on each animation frame.
private struct ProjectTaskStackLayout: Layout {
    struct Context: Equatable {
        let revision: UInt64
        let ids: [UUID]
        let today: LocalDay
        let locale: String
        let dynamicTypeSize: DynamicTypeSize
    }
    struct Cache {
        var context: Context?
        var width: CGFloat?
        var sizes: [CGSize] = []
        var size = CGSize.zero
    }
    let context: Context

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.sizes.count != subviews.count { cache.context = nil }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        measure(width: proposal.width, subviews: subviews, cache: &cache)
        return cache.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        measure(width: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = cache.sizes[index]
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
    }
    private func measure(width: CGFloat?, subviews: Subviews, cache: inout Cache) {
        guard cache.context != context || cache.width != width || cache.sizes.count != subviews.count else { return }
        cache.context = context
        cache.width = width
        cache.sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        cache.size = CGSize(width: width ?? cache.sizes.map(\.width).max() ?? 0,
            height: cache.sizes.reduce(0) { $0 + $1.height })
    }
}

private struct ProjectTaskDragRow: View, Equatable {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: TodoItem
    let isFirst: Bool
    let isLast: Bool
    let isDragging: Bool
    let today: LocalDay
    let localeIdentifier: String
    let project: TodoProject
    @Binding var editingItem: TodoItem?
    let drag: ProjectTaskDragSession

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.isFirst == rhs.isFirst && lhs.isLast == rhs.isLast
            && lhs.isDragging == rhs.isDragging && lhs.today == rhs.today
            && lhs.localeIdentifier == rhs.localeIdentifier && lhs.project == rhs.project
            && lhs.drag === rhs.drag
        // editingItem is the same owner's binding throughout this row's life.
        // Store and environment updates still invalidate the view independently.
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: isFirst ? 10 : 0, bottomLeading: isLast ? 10 : 0,
            bottomTrailing: isLast ? 10 : 0, topTrailing: isFirst ? 10 : 0
        ), style: .continuous)
        TodoRow(item: item, showsProject: false, showsOverdue: true) {
            editingItem = item
        }
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.055), in: shape)
        .overlay { shape.stroke(Color.secondary.opacity(0.12), lineWidth: 0.5) }
        .padding(.leading, 28)
        .opacity(isDragging ? 0.35 : 1)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            drag.recordHeight(height, for: item.id)
        }
        .onDrag {
            guard store.canModify else { return NSItemProvider() }
            drag.begin(itemID: item.id, projectID: project.id, orderedIDs: store.items(in: project).map(\.id))
            drag.watchForRelease(animation: animation)
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: drag.delegate(
            projectID: project.id, targetID: item.id, store: store, animation: animation
        ))
    }

    private var animation: Animation? {
        store.settings.animation(.spring(duration: 0.32, bounce: 0.16), for: .projectReorder, reduceMotion: reduceMotion)
    }
}

@MainActor
final class ProjectTaskDragSession: ObservableObject {
    @Published private(set) var preview: ProjectTaskDragPreview?
    let scheduler = FrameUpdateScheduler()
    private var lastReorderPoint: CGPoint?
    private var pendingTarget: UUID?
    private var releaseTask: Task<Void, Never>?
    private var rowHeights: [UUID: CGFloat] = [:]

    func begin(itemID: UUID, projectID: UUID, orderedIDs: [UUID]) {
        cancel(animation: nil)
        preview = ProjectTaskDragPreview(itemID: itemID, projectID: projectID, orderedIDs: orderedIDs)
    }

    func orderedChildren(_ children: [TodoItem]) -> [TodoItem] {
        guard let preview else { return children }
        let byID = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })
        return preview.orderedIDs.compactMap { byID[$0] }
    }

    func recordHeight(_ height: CGFloat, for id: UUID) {
        let previous = rowHeights[id]
        rowHeights[id] = height
        // A font/metadata change invalidates the captured offsets, just as a
        // content change does. Ordinary position animation never changes size.
        if preview != nil, previous != height { cancel(animation: nil) }
    }

    func offsets(for children: [TodoItem], ordered: [TodoItem]) -> [UUID: CGFloat] {
        guard preview != nil else { return [:] }
        var originalY: [UUID: CGFloat] = [:]
        var y: CGFloat = 0
        for item in children {
            guard let height = rowHeights[item.id] else { return [:] }
            originalY[item.id] = y
            y += height
        }
        y = 0
        var offsets: [UUID: CGFloat] = [:]
        for item in ordered {
            offsets[item.id] = y - originalY[item.id, default: y]
            y += rowHeights[item.id, default: 0]
        }
        return offsets
    }

    func hover(over targetID: UUID?, at point: CGPoint, animation: Animation?) {
        guard preview != nil else { return }
        pendingTarget = targetID
        scheduler.submit { [weak self] in
            self?.move(over: targetID, at: point, animation: animation)
        }
    }

    private func move(over targetID: UUID?, at point: CGPoint, animation: Animation?) {
        guard var next = preview else { return }
        // Animated rows can enter/exit under a stationary pointer. Those are
        // layout events, not a new intent to reverse the previous move.
        if let lastReorderPoint {
            let delta = point.y - lastReorderPoint.y // AppKit screen Y increases upwards.
            guard abs(delta) >= 2,
                  let source = next.orderedIDs.firstIndex(of: next.itemID) else { return }
            let target = targetID.flatMap { next.orderedIDs.firstIndex(of: $0) } ?? next.orderedIDs.count
            guard target == source || (target > source ? delta < 0 : delta > 0) else { return }
        }
        // Direction above distinguishes a real reversal from a displaced row;
        // it also allows reversing across the same neighbour without a detour.
        next.move(over: next.itemID)
        next.move(over: targetID)
        guard next.orderedIDs != preview?.orderedIDs else { return }
        withAnimation(animation) { preview = next }
        lastReorderPoint = point
    }

    func exit(targetID: UUID?) {
        if pendingTarget == targetID { scheduler.cancel() }
    }

    @discardableResult
    func commit(store: TodoStore, projectID: UUID, animation: Animation? = nil) -> Bool {
        scheduler.flush()
        guard let preview, preview.projectID == projectID, store.canModify else {
            cancel(animation: nil)
            return false
        }
        withAnimation(animation) {
            _ = store.moveProjectItem(preview.itemID, before: preview.followingID, in: projectID)
            cancel(animation: animation)
        }
        return true
    }

    func cancel(animation: Animation?) {
        scheduler.cancel()
        releaseTask?.cancel()
        releaseTask = nil
        lastReorderPoint = nil
        pendingTarget = nil
        if preview != nil { withAnimation(animation) { preview = nil } }
    }

    func watchForRelease(animation: Animation?) {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self?.cancel(animation: animation)
                    return
                }
            }
        }
    }

    func delegate(projectID: UUID, targetID: UUID?, store: TodoStore, animation: Animation?) -> ProjectTaskDropDelegate {
        ProjectTaskDropDelegate(accepts: { [weak self] in
            store.canModify && self?.preview?.projectID == projectID
        }, enter: { [weak self] in
            guard let self else { return }
            self.hover(over: targetID, at: self.pointerLocation(), animation: animation)
        }, exit: { [weak self] in
            self?.exit(targetID: targetID)
        }, commit: { [weak self] in
            guard let self else { return false }
            self.hover(over: targetID, at: self.pointerLocation(), animation: animation)
            return self.commit(store: store, projectID: projectID, animation: animation)
        })
    }

    private func pointerLocation() -> CGPoint {
        guard let view = scheduler.view, let window = view.window else { return NSEvent.mouseLocation }
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // Use the whole list's coordinates, not moving row coordinates. Edge
        // autoscroll still advances this point when the mouse stays stationary.
        return CGPoint(x: point.x, y: view.isFlipped ? -point.y : point.y)
    }
}
