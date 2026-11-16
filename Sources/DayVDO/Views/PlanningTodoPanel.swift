import SwiftUI

/// Keep list input independent while its content shares the timeline's native
/// scroll backdrop. Unhandled input goes to the page, bypassing the timeline.
struct PlanningTodoViewport: NSViewRepresentable {
    var panel: PlanningTodoPanel
    var isDropTarget: Bool
    var castsShadow: Bool

    func makeNSView(context: Context) -> AnchorView {
        let anchor = AnchorView()
        updateNSView(anchor, context: context)
        return anchor
    }

    func updateNSView(_ anchor: AnchorView, context: Context) {
        anchor.content = { topInset in
            AnyView(panel
                .contentMargins(.top, topInset, for: .scrollContent)
                .background(.background, ignoresSafeAreaEdges: [])
                .overlay {
                    if isDropTarget {
                        Rectangle().fill(Color.accentColor.opacity(0.08))
                            .overlay { Rectangle().strokeBorder(Color.accentColor, lineWidth: 2) }
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .leading) {
                    Color(nsColor: .separatorColor).frame(width: 1)
                }
                .shadow(color: .black.opacity(castsShadow ? 0.08 : 0), radius: 8, x: -4)
                .environment(\.self, context.environment))
        }
    }

    static func dismantleNSView(_ anchor: AnchorView, coordinator: ()) {
        anchor.detach()
    }

    /// The list stays inside the shared scroll surface, but its frame follows
    /// native clip bounds immediately rather than a later SwiftUI scroll update.
    final class AnchorView: NSView {
        private let host = HostingView(rootView: AnyView(EmptyView()))
        private weak var clipView: NSClipView?
        private var topInset: CGFloat = 0
        var content: ((CGFloat) -> AnyView)? {
            didSet { updateContent() }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            host.safeAreaRegions = []
            host.sizingOptions = []
            host.clipsToBounds = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
        }

        override func layout() {
            super.layout()
            attachIfNeeded()
            updateViewport()
        }

        private func attachIfNeeded() {
            guard window != nil, let clip = enclosingScrollView?.contentView else {
                detach()
                return
            }
            guard clipView !== clip else { return }
            detach()
            clipView = clip
            clip.postsBoundsChangedNotifications = true
            clip.postsFrameChangedNotifications = true
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged(_:)),
                                                       name: name, object: clip)
            }
            clip.addSubview(host, positioned: .above, relativeTo: clip.documentView)
            updateViewport()
        }

        @objc private func viewportChanged(_ notification: Notification) {
            updateViewport()
        }

        private func updateViewport() {
            guard let clip = clipView else { return }
            let inset = clip.enclosingScrollView?.contentInsets.top ?? 0
            if topInset != inset {
                topInset = inset
                updateContent()
            }
            let width = min(bounds.width, clip.bounds.width)
            let frame = NSRect(x: clip.bounds.maxX - width, y: clip.bounds.minY,
                               width: width, height: clip.bounds.height)
            if host.frame != frame { host.frame = frame }
        }

        private func updateContent() {
            if let content { host.rootView = content(topInset) }
        }

        func detach() {
            if let clip = clipView {
                for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                    NotificationCenter.default.removeObserver(self, name: name, object: clip)
                }
            }
            host.removeFromSuperview()
            clipView = nil
        }
    }

    final class HostingView: NSHostingView<AnyView> {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            routeInputToPage()
        }

        override func layout() {
            super.layout()
            routeInputToPage()
        }

        private func routeInputToPage() {
            if let timeline = enclosingScrollView {
                nextResponder = timeline.nextResponder
            }
        }
    }
}

enum PlanningTodoSectionKind: String, CaseIterable, Identifiable {
    case unscheduled = "未安排"
    case scheduled = "已安排"
    case completed = "已完成"

    var id: String { rawValue }

    var isExpandedByDefault: Bool {
        true
    }
}

struct PlanningTodoSection: Identifiable, Equatable {
    var kind: PlanningTodoSectionKind
    var items: [TodoItem]

    var id: PlanningTodoSectionKind { kind }
}

enum PlanningTodoPanelPolicy {
    static func sections(items: [TodoItem], schedules: [DaySchedule], showCompleted: Bool) -> [PlanningTodoSection] {
        let scheduledIDs = Set(schedules.compactMap(\.todoID))
        var unscheduled: [TodoItem] = [], scheduled: [TodoItem] = [], completed: [TodoItem] = []
        for item in items {
            if item.isCompleted {
                if showCompleted { completed.append(item) }
            } else if scheduledIDs.contains(item.id) {
                scheduled.append(item)
            } else {
                unscheduled.append(item)
            }
        }
        return [
            PlanningTodoSection(kind: .unscheduled, items: unscheduled),
            PlanningTodoSection(kind: .scheduled, items: scheduled),
            PlanningTodoSection(kind: .completed, items: completed)
        ].filter { !$0.items.isEmpty }
    }
}

struct PlanningTodoPanel: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: LocalDay
    let today: LocalDay
    var edit: (TodoItem) -> Void
    @Namespace private var cardPositions
    @State private var selectedID: UUID?
    @State private var expandedSections = Set(
        PlanningTodoSectionKind.allCases.filter(\.isExpandedByDefault)
    )

    private var dayItems: [TodoItem] { store.planningItems(on: day, today: today) }
    private var sections: [PlanningTodoSection] {
        PlanningTodoPanelPolicy.sections(
            items: dayItems,
            schedules: store.schedules(on: day),
            showCompleted: store.settings.showCompleted
        )
    }

    var body: some View {
        let sections = self.sections
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Section {
                            if expandedSections.contains(section.kind) {
                                ForEach(section.items) { item in
                                    PlanningTodoRow(
                                        snapshot: item,
                                        day: day,
                                        isOverdue: TaskDateRangePolicy.isOverdue(item, on: day, today: today),
                                        isSelected: selectedID == item.id,
                                        select: { selectedID = item.id },
                                        edit: edit
                                    )
                                    .matchedGeometryEffect(id: item.id, in: cardPositions)
                                    .padding(.horizontal, 12).padding(.bottom, 10)
                                    .transition(.opacity)
                                }
                            }
                        } header: {
                            Button {
                                withAnimation(store.settings.animation(.snappy(duration: 0.18), for: .planningSections, reduceMotion: reduceMotion)) {
                                    if expandedSections.contains(section.kind) {
                                        expandedSections.remove(section.kind)
                                    } else {
                                        expandedSections.insert(section.kind)
                                    }
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .rotationEffect(
                                            expandedSections.contains(section.kind)
                                                ? .zero
                                                : .degrees(-90)
                                        )
                                        .frame(width: 10)
                                        .accessibilityHidden(true)
                                    Text(L10n.string(section.kind.rawValue))
                                    Spacer()
                                    Text("\(section.items.count)")
                                        .monospacedDigit()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(
                                L10n.string(
                                    expandedSections.contains(section.kind)
                                        ? "已展开"
                                        : "已收回"
                                )
                            )
                        }
                    }
                    if sections.isEmpty {
                        Text(L10n.string("这一天暂无待办"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                }
                .animation(store.settings.animation(.snappy(duration: 0.28), for: .planningSections, reduceMotion: reduceMotion), value: sections)
                .id(day)
            }
            .scrollBounceBehavior(.always, axes: .vertical)
        }
        .onChange(of: day) { _, _ in selectedID = nil }
    }
}

private struct PlanningTodoRow: View {
    @EnvironmentObject private var store: TodoStore
    let snapshot: TodoItem
    let day: LocalDay
    let isOverdue: Bool
    let isSelected: Bool
    var select: () -> Void
    var edit: (TodoItem) -> Void
    @State private var isHovered = false
    @State private var isDurationHovered = false
    @State private var isEditingDuration = false
    @State private var confirmsDeletion = false
    @FocusState private var rowFocused: Bool

    // Lazy sections can retain a row's input snapshot when it changes groups.
    // Resolve its current model by stable identity for both content and actions.
    private var item: TodoItem {
        store.items.first { $0.id == snapshot.id } ?? snapshot
    }

    private var sectionKind: PlanningTodoSectionKind {
        if item.isCompleted { return .completed }
        return store.schedules(on: day).contains { $0.todoID == item.id }
            ? .scheduled : .unscheduled
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggle(item) } label: {
                TodoStatusIcon(status: item.status)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string(item.isCompleted ? "标记为未完成" : "标记为已完成"))
            .padding(.top, 2)
            .contextMenu { TodoStatusMenuItems(item: item) }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .layoutPriority(1)
                    if isOverdue {
                        OverdueBadge()
                    }
                }
                if let project = store.project(withID: item.projectID) {
                    Label(project.title, systemImage: "folder")
                        .lineLimit(1)
                }
                if let tag = store.tag(withID: item.tagID) {
                    TaskTagLabel(tag: tag)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 7) {
                Button {
                    isEditingDuration = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(estimateText ?? L10n.string("无"))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        isDurationHovered || isEditingDuration
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isDurationHovered || isEditingDuration
                                    ? Color.accentColor.opacity(0.45)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isDurationHovered || isEditingDuration ? Color.accentColor : Color.secondary)
                .onHover { isDurationHovered = $0 }
                .disabled(!store.canModify)
                .help(L10n.string("预计时长"))
                .accessibilityLabel(L10n.string("预计时长"))
                .accessibilityValue(
                    estimateText ?? L10n.string("无")
                )
                .popover(isPresented: $isEditingDuration, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("预计时长"))
                            .font(.headline)
                        DurationInput(minutes: item.estimatedMinutes, unit: store.settings.estimatedDurationUnit) { minutes in
                            updateDuration(minutes)
                        }
                    }
                    .padding(14)
                }

                HStack(spacing: 4) {
                    if item.priority != .none {
                        Image(systemName: item.priority.symbolName)
                            .foregroundStyle(item.priority.swiftUIColor)
                    }
                    Text(L10n.string(item.priority.title))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.trailing, 7)
            }
            .font(.caption)
            .fixedSize(horizontal: true, vertical: false)
        }
        .opacity(sectionKind == .completed ? 0.72 : 1)
        .padding(12)
        .background(cardBackground, in: cardShape)
        .overlay(alignment: .leading) {
            if sectionKind == .scheduled {
                Capsule()
                    .fill(Color.blue)
                    .frame(width: 3)
                    .padding(.vertical, 7)
                    .padding(.leading, 3)
                    .accessibilityHidden(true)
            }
        }
        .overlay { stateOutline }
        .overlay {
            cardShape
                .stroke(
                    isSelected || rowFocused ? Color.accentColor.opacity(0.75) : .clear,
                    lineWidth: 1.5
                )
        }
        .contentShape(cardShape)
        .onTapGesture(count: 2) { edit(item) }
        .onTapGesture { select() }
        .onHover { isHovered = $0 }
        .focusable()
        .focused($rowFocused)
        .onKeyPress(.space) {
            _ = store.toggle(item)
            return .handled
        }
        .onDrag { PlanningTodoTransfer.provider(for: item.id) }
        .contextMenu {
            Button(L10n.string("编辑待办")) { edit(item) }
            Divider()
            TodoStatusMenuItems(item: item)
            Divider()
            Button(L10n.string("删除待办"), role: .destructive) {
                if store.settings.confirmBeforeDeleting { confirmsDeletion = true }
                else { store.delete(item) }
            }.disabled(!store.canModify)
        }
        .confirmationDialog(L10n.format("删除“%@”？", item.title), isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button(L10n.string("删除"), role: .destructive) { store.delete(item) }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("删除后可以从“编辑”菜单撤销。"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(L10n.string(item.status.title))
        .accessibilityAction(named: L10n.string("标记为未开始")) {
            _ = store.setStatus(.notStarted, for: item)
        }
        .accessibilityAction(named: L10n.string("标记为进行中")) {
            _ = store.setStatus(.inProgress, for: item)
        }
        .accessibilityAction(named: L10n.string("标记为已完成")) {
            _ = store.setStatus(.completed, for: item)
        }
        .accessibilityHint(
            Text(
                [
                    store.project(withID: item.projectID)?.title,
                    store.tag(withID: item.tagID)?.name,
                    estimateText,
                    L10n.string(item.priority.title)
                ].compactMap { $0 }.joined(separator: ", ")
            )
        )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10)
    }

    private var estimateText: String? {
        item.estimatedMinutes.map(store.settings.estimatedDurationUnit.formatted)
    }

    private var cardBackground: Color {
        switch sectionKind {
        case .unscheduled:
            Color.secondary.opacity(isHovered ? 0.11 : 0.07)
        case .scheduled:
            Color.blue.opacity(isHovered ? 0.13 : 0.08)
        case .completed:
            Color.green.opacity(isHovered ? 0.10 : 0.06)
        }
    }

    @ViewBuilder
    private var stateOutline: some View {
        switch sectionKind {
        case .unscheduled:
            cardShape.stroke(
                Color.secondary.opacity(0.32),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        case .scheduled:
            cardShape.stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        case .completed:
            cardShape.stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        }
    }

    private func updateDuration(_ minutes: Int?) {
        guard store.canModify, minutes != item.estimatedMinutes else { return }
        var updated = item
        updated.estimatedMinutes = minutes
        _ = store.upsert(updated)
    }
}
