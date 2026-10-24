import SwiftUI

struct TodoFilterButton: View {
    @Binding var filter: TodoFilterState
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                if filter.isActive {
                    Text("\(filter.activeCategoryCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.accentColor, in: Circle())
                }
            }
            .foregroundStyle(filter.isActive ? Color.accentColor : Color.primary)
            .fixedSize(horizontal: true, vertical: false)
        }
        .help(L10n.string("筛选待办"))
        .accessibilityLabel(L10n.string("筛选待办"))
        .accessibilityValue(
            filter.isActive
                ? L10n.format("已启用 %lld 类筛选", filter.activeCategoryCount)
                : L10n.string("未启用筛选")
        )
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            TodoFilterPopover(filter: $filter)
        }
    }
}

struct TodoFilterPopover: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TodoFilterState
    @State private var isPickingStart = false
    @State private var isPickingEnd = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 136), spacing: 8)
    ]

    private var sortedProjects: [TodoProject] {
        store.projects.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("筛选"))
                    .font(.headline)
                Spacer()
                Button(L10n.string("清除全部")) { filter.clear() }
                    .buttonStyle(.borderless)
                    .disabled(!filter.isActive)
                    .accessibilityHint(L10n.string("移除所有筛选条件"))
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filterSection(L10n.string("状态")) {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                            ForEach(TodoItem.Status.allCases) { status in
                                filterChoice(
                                    title: L10n.string(status.title),
                                    symbol: status.symbolName,
                                    color: status.color,
                                    isSelected: filter.statuses.contains(status)
                                ) {
                                    toggle(status, at: \.statuses)
                                }
                            }

                            filterChoice(
                                title: L10n.string("已逾期"),
                                symbol: "exclamationmark.circle.fill",
                                color: .red,
                                isSelected: filter.overdueOnly
                            ) {
                                filter.overdueOnly.toggle()
                            }
                        }
                    }

                    filterSection(L10n.string("日期")) {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                            ForEach([TodoDateFilter.any, .undated], id: \.self) { preset in
                                filterChoice(
                                    title: L10n.string(preset.title), symbol: preset == .undated ? "calendar.badge.minus" : "calendar",
                                    color: .secondary, isSelected: filter.date == preset
                                ) { filter.date = preset }
                            }
                            filterChoice(
                                title: L10n.string("自定义"), symbol: "calendar.badge.clock",
                                color: .secondary, isSelected: filter.date.customRange != nil
                            ) {
                                if filter.date.customRange == nil {
                                    let today = LocalDay(.now)
                                    filter.date = .custom(today...today)
                                }
                            }
                            Menu {
                                ForEach(TodoDateFilter.presets.filter(\.usesRelativeDate), id: \.self) { preset in
                                    Button { filter.date = preset } label: {
                                        if filter.date == preset {
                                            Label(L10n.string(preset.title), systemImage: "checkmark")
                                        } else {
                                            Text(L10n.string(preset.title))
                                        }
                                    }
                                }
                            } label: {
                                filterChoiceLabel(
                                    title: L10n.string("更多"), symbol: "ellipsis",
                                    color: .secondary, isSelected: filter.date.usesRelativeDate
                                )
                            }
                            .menuIndicator(.hidden)
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .accessibilityLabel(L10n.string("更多"))
                            .accessibilityValue(L10n.string(filter.date.usesRelativeDate ? filter.date.title : "未选择"))
                            .help(L10n.string(filter.date.usesRelativeDate ? filter.date.title : "更多"))
                        }
                        if let range = filter.date.customRange {
                            customDateRow(title: "开始日期", day: range.lowerBound, isPresented: $isPickingStart) { day in
                                filter.date = .custom(day...max(day, range.upperBound))
                            }
                            customDateRow(title: "结束日期", day: range.upperBound, isPresented: $isPickingEnd) { day in
                                filter.date = .custom(min(day, range.lowerBound)...day)
                            }
                        }
                    }

                    filterSection(L10n.string("所属项目")) {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                filterListChoice(
                                    title: L10n.string("无归类"),
                                    symbol: "tray",
                                    isSelected: filter.includesUnassignedProject
                                ) {
                                    filter.includesUnassignedProject.toggle()
                                }

                                ForEach(sortedProjects) { project in
                                    filterListChoice(
                                        title: project.title,
                                        symbol: "folder",
                                        isSelected: filter.projectIDs.contains(project.id)
                                    ) {
                                        toggle(project.id, at: \.projectIDs)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(sortedProjects.count > 3 ? .visible : .hidden)
                        .frame(height: listHeight(itemCount: sortedProjects.count + 1))
                    }

                    filterSection(L10n.string("标签")) {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                filterListChoice(
                                    title: L10n.string("无标签"),
                                    symbol: "tag.slash",
                                    isSelected: filter.includesUntagged
                                ) {
                                    filter.includesUntagged.toggle()
                                }

                                ForEach(store.sortedTags) { tag in
                                    filterListChoice(
                                        title: tag.name,
                                        isSelected: filter.tagIDs.contains(tag.id),
                                        leading: { TaskTagDot(tag: tag, size: 9) }
                                    ) {
                                        toggle(tag.id, at: \.tagIDs)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(store.sortedTags.count > 3 ? .visible : .hidden)
                        .frame(height: listHeight(itemCount: store.sortedTags.count + 1))
                    }

                    filterSection(L10n.string("重要度")) {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                            ForEach(TodoItem.Priority.allCases) { priority in
                                filterChoice(
                                    title: L10n.string(priority.title),
                                    symbol: priority == .none ? nil : priority.symbolName,
                                    color: priority.swiftUIColor,
                                    isSelected: filter.priorities.contains(priority)
                                ) {
                                    toggle(priority, at: \.priorities)
                                }
                            }
                        }
                    }

                    filterSection(L10n.string("紧急度")) {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                            ForEach(TodoItem.Urgency.allCases) { urgency in
                                filterChoice(
                                    title: L10n.string(urgency.title),
                                    symbol: urgency.symbolName,
                                    color: urgency.filterColor,
                                    isSelected: filter.urgencies.contains(urgency)
                                ) {
                                    toggle(urgency, at: \.urgencies)
                                }
                            }
                        }
                    }
                }
                .padding(1)
            }
            .frame(maxHeight: 520)
        }
        .padding(16)
        .frame(width: 340)
        .editorEscapeDismissal(enabled: !isPickingStart && !isPickingEnd) { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("筛选待办"))
    }

    private func customDateRow(
        title: String, day: LocalDay, isPresented: Binding<Bool>, update: @escaping (LocalDay) -> Void
    ) -> some View {
        HStack {
            Text(L10n.string(title))
                .foregroundStyle(.secondary)
            Spacer()
            Button { isPresented.wrappedValue.toggle() } label: {
                HStack(spacing: 5) {
                    Text(day.date().formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)))
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.string(title))
            .accessibilityValue(day.date().formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)))
            .popover(isPresented: isPresented) {
                BorderlessCalendarPicker(selection: Binding(
                    get: { day.date() },
                    set: { update(LocalDay($0)); isPresented.wrappedValue = false }
                ), startsOnMonday: store.settings.startWeekOnMonday)
                .fixedSize().padding(10)
                .editorEscapeDismissal { isPresented.wrappedValue = false }
            }
        }
        .font(.callout)
        .padding(.horizontal, 4)
        .frame(minHeight: 30)
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func filterChoice(
        title: String,
        symbol: String?,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            filterChoiceLabel(title: title, symbol: symbol, color: color, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityValue(L10n.string(isSelected ? "已选择" : "未选择"))
    }

    private func filterChoiceLabel(
        title: String, symbol: String?, color: Color, isSelected: Bool
    ) -> some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 15)
                    .accessibilityHidden(true)
            }
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.14),
                    lineWidth: 1
                )
        }
    }

    private func filterListChoice(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        filterListChoice(
            title: title,
            isSelected: isSelected,
            leading: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                    .accessibilityHidden(true)
            },
            action: action
        )
    }

    private func filterListChoice<Leading: View>(
        title: String,
        isSelected: Bool,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading()
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityValue(L10n.string(isSelected ? "已选择" : "未选择"))
    }

    private func toggle<Value: Hashable>(
        _ value: Value,
        at keyPath: WritableKeyPath<TodoFilterState, Set<Value>>
    ) {
        var updated = filter
        if updated[keyPath: keyPath].contains(value) {
            updated[keyPath: keyPath].remove(value)
        } else {
            updated[keyPath: keyPath].insert(value)
        }
        filter = updated
    }

    private func listHeight(itemCount: Int) -> CGFloat {
        min(CGFloat(max(itemCount, 1)) * 31, 112)
    }
}

private extension TodoItem.Urgency {
    var filterColor: Color {
        switch self {
        case .none: .secondary
        case .canWait: .green
        case .today: .blue
        case .mustToday: .red
        }
    }
}
