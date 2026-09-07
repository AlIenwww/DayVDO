import SwiftUI

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
        return [
            PlanningTodoSection(kind: .unscheduled, items: items.filter {
                !$0.isCompleted && !scheduledIDs.contains($0.id)
            }),
            PlanningTodoSection(kind: .scheduled, items: items.filter {
                !$0.isCompleted && scheduledIDs.contains($0.id)
            }),
            PlanningTodoSection(kind: .completed, items: showCompleted ? items.filter(\.isCompleted) : [])
        ].filter { !$0.items.isEmpty }
    }
}

struct PlanningTodoPanel: View {
    @EnvironmentObject private var store: TodoStore
    let day: LocalDay
    var edit: (TodoItem) -> Void
    @State private var selectedID: UUID?
    @State private var expandedSections = Set(
        PlanningTodoSectionKind.allCases.filter(\.isExpandedByDefault)
    )

    private var dayItems: [TodoItem] { store.allItems(on: day) }
    private var sections: [PlanningTodoSection] {
        PlanningTodoPanelPolicy.sections(
            items: dayItems,
            schedules: store.schedules,
            showCompleted: store.settings.showCompleted
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            if expandedSections.contains(section.kind) {
                                ForEach(section.items) { item in
                                    PlanningTodoRow(
                                        item: item,
                                        sectionKind: section.kind,
                                        isSelected: selectedID == item.id,
                                        select: { selectedID = item.id },
                                        edit: edit
                                    )
                                    .padding(.horizontal, 12).padding(.bottom, 10)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        } header: {
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
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
                            .background(.background)
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
            }
        }
        .background(.background)
        .onChange(of: day) { _, _ in selectedID = nil }
    }
}

private struct PlanningTodoRow: View {
    @EnvironmentObject private var store: TodoStore
    let item: TodoItem
    let sectionKind: PlanningTodoSectionKind
    let isSelected: Bool
    var select: () -> Void
    var edit: (TodoItem) -> Void
    @State private var isHovered = false
    @State private var isDurationHovered = false
    @State private var isEditingDuration = false
    @State private var confirmsDeletion = false
    @FocusState private var rowFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string(item.isCompleted ? "标记为未完成" : "标记为已完成"))
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .layoutPriority(1)
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
                        Text(item.estimatedMinutes.map { L10n.format("%lld 分钟", $0) } ?? L10n.string("无"))
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
                    item.estimatedMinutes.map { L10n.format("%lld 分钟", $0) } ?? L10n.string("无")
                )
                .popover(isPresented: $isEditingDuration, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("预计时长"))
                            .font(.headline)
                        DurationInput(minutes: item.estimatedMinutes) { minutes in
                            updateDuration(minutes)
                        }
                    }
                    .padding(14)
                }

                HStack(spacing: 4) {
                    Image(systemName: item.priority.symbolName)
                        .foregroundStyle(item.priority.swiftUIColor)
                    Text(L10n.string(item.priority.title))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
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
        .onDrag { PlanningTodoTransfer.provider(for: item.id) }
        .contextMenu {
            Button(L10n.string("编辑待办")) { edit(item) }
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
        .accessibilityHint(
            Text(
                [
                    store.project(withID: item.projectID)?.title,
                    store.tag(withID: item.tagID)?.name,
                    item.estimatedMinutes.map { L10n.format("%lld 分钟", $0) },
                    L10n.string(item.priority.title)
                ].compactMap { $0 }.joined(separator: ", ")
            )
        )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10)
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
