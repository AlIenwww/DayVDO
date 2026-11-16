import SwiftUI
import AppKit

struct TodoEditorView: View {
    @Environment(\.practiceDay) private var practiceDay
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @State private var draft: TodoItem
    @State private var dateInput: TaskDateInput
    @State private var isShowingStartDatePicker = false
    @State private var isShowingDeadlinePicker = false
    @State private var isShowingProjectPicker = false
    @State private var isShowingTagPicker = false
    @State private var isEstimateValid = true
    @State private var dateChange: TodoStore.DateChangeConfirmation?
    @State private var newProjectDraft: TodoProject?
    @FocusState private var titleIsFocused: Bool

    let isEditing: Bool
    let onSave: (TodoItem) -> Bool

    init(item: TodoItem, isEditing: Bool, onSave: @escaping (TodoItem) -> Bool) {
        _draft = State(initialValue: item)
        _dateInput = State(initialValue: TaskDateInput(item: item))
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editorTitle)
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(L10n.string("待办名称"), text: $draft.title, prompt: Text(L10n.string("添加待办事项")))
                        .font(.title2.weight(.medium))
                        .textFieldStyle(.plain)
                        .focused($titleIsFocused)

                    TextField(L10n.string("备注"), text: $draft.notes, prompt: Text(L10n.string("添加备注")), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                }
                .padding(20)

                Group {
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("所属项目"))
                        Spacer()
                        projectPicker
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                }

                Divider().padding(.leading, 50)

                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(L10n.string("标签"))
                    Spacer()
                    TaskTagPicker(selection: $draft.tagID, isPresented: $isShowingTagPicker)
                }
                .padding(.horizontal, 20)
                .frame(height: 46)

                Divider()

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(L10n.string("日期"))
                            Spacer()
                            Toggle(L10n.string("设置日期"), isOn: Binding(
                                get: { dateInput.hasDate },
                                set: { dateInput.setHasDate($0, defaultDay: draft.startDay ?? draft.dueDay ?? LocalDay(.now)) }
                            ))
                                .labelsHidden()
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 46)

                        if dateInput.hasDate {
                            Divider().padding(.leading, 50)
                            dateRangeRow(
                                title: L10n.string("任务日期"),
                                day: dateInput.startDay ?? LocalDay(.now),
                                isPresented: $isShowingStartDatePicker,
                                confirm: { dateInput.confirmTaskDay() }
                            ) { dateInput.chooseTaskDay(LocalDay($0)) }

                            if dateInput.showsEndDate {
                                Divider().padding(.leading, 50)
                                dateRangeRow(
                                    title: L10n.string("结束日期"),
                                    day: dateInput.deadline ?? LocalDay(.now),
                                    isPresented: $isShowingDeadlinePicker
                                ) { dateInput.chooseEndDay(LocalDay($0)) }
                            }

                            if !dateInput.isValid {
                                Text(L10n.string("结束日期不能早于任务日期。"))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 50)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .disabled(practiceDay != nil)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 10) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("预计时长"))
                        Spacer()
                        DurationInput(minutes: draft.estimatedMinutes, unit: store.settings.estimatedDurationUnit,
                                      updatesDraft: true,
                                      onValidityChange: { isEstimateValid = $0 }) { draft.estimatedMinutes = $0 }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)

                    Divider()

                    HStack(spacing: 10) {
                        Image(systemName: "flag")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("重要度"))
                        Spacer()
                        FixedWidthPopUp(
                            label: L10n.string("重要度"),
                            selection: $draft.priority,
                            options: TodoItem.Priority.allCases,
                            title: { L10n.string($0.title) },
                            symbolName: { $0 == .none ? nil : $0.symbolName },
                            iconColor: { $0 == .none ? nil : $0.displayColor }
                        )
                        .frame(width: optionWidth, height: 26)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 10) {
                        Image(systemName: "bolt")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("紧急度"))
                        Spacer()
                        FixedWidthPopUp(
                            label: L10n.string("紧急度"),
                            selection: $draft.urgency,
                            options: TodoItem.Urgency.allCases,
                            title: { L10n.string($0.title) },
                            symbolName: { $0 == .none ? nil : $0.symbolName },
                            iconColor: { $0 == .none ? nil : $0.displayColor }
                        )
                        .frame(width: optionWidth, height: 26)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        draft.normalizedTitle.isEmpty
                            || !store.canModify
                            || !isEstimateValid
                            || !dateInput.isValid
                    )
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .dateChangeConfirmation($dateChange) { _ in dismiss() }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .editorEscapeDismissal(
            enabled: dateChange == nil && !isShowingStartDatePicker && !isShowingDeadlinePicker
                && !isShowingProjectPicker && !isShowingTagPicker,
            cancel: { dismiss() }
        )
        .task {
            await Task.yield()
            titleIsFocused = true
        }
    }

    private func save() {
        let candidate = dateInput.applying(to: draft)
        guard dateInput.isValid, candidate.hasValidDateRange else { return }
        if let request = store.dateChangeConfirmation(for: candidate) {
            dateChange = request
            return
        }
        if onSave(candidate) || (store.canModify && store.items.contains(candidate)) {
            dismiss()
        }
    }

    private func dateRangeRow(
        title: String,
        day: LocalDay,
        isPresented: Binding<Bool>,
        confirm: (() -> Void)? = nil,
        update: @escaping (Date) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 20, height: 1)
            Text(title)
            Spacer()
            Button {
                isPresented.wrappedValue.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(
                        day.date().formatted(
                            .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
                        )
                    )
                    .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(
                day.date().formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale))
            )
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                VStack(alignment: .trailing, spacing: 8) {
                    BorderlessCalendarPicker(
                        selection: Binding(
                            get: { day.date() },
                            set: { newDate in update(newDate) }
                        ),
                        startsOnMonday: store.settings.startWeekOnMonday
                    )
                    .fixedSize()
                    if let confirm {
                        Button(L10n.string("完成")) {
                            confirm()
                            isPresented.wrappedValue = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(10)
                .editorEscapeDismissal { isPresented.wrappedValue = false }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 42)
    }

    private var projectPicker: some View {
        TaskAssignmentPicker(
            title: L10n.string("所属项目"),
            selection: draft.projectID,
            options: store.sortedProjects.map {
                .init(id: $0.id, title: $0.title, tag: store.tag(withID: $0.tagID))
            },
            noneTitle: L10n.string("无归类"),
            symbol: "folder",
            createTitle: L10n.string("新建大项目…"),
            select: { id in
                guard draft.projectID != id else { return }
                draft.projectID = id
                draft.projectSortOrder = nil
                if draft.tagID == nil {
                    draft.tagID = store.project(withID: id)?.tagID
                }
            },
            create: {
                newProjectDraft = TodoProject(title: "")
            },
            isPresented: $isShowingProjectPicker
        )
        .disabled(!store.canModify)
        .sheet(item: $newProjectDraft) { project in
            ProjectEditorView(project: project, isEditing: false) { savedProject in
                guard store.upsertProject(savedProject) else { return false }
                draft.projectID = savedProject.id
                draft.projectSortOrder = nil
                if draft.tagID == nil { draft.tagID = savedProject.tagID }
                return true
            }
        }
    }

    private var optionWidth: CGFloat {
        LocalizedControlSizing.popUpWidth(
            for: TodoItem.Priority.allCases.map { L10n.string($0.title) }
                + TodoItem.Urgency.allCases.map { L10n.string($0.title) }
        )
    }

    private var editorTitle: String {
        if draft.projectID != nil {
            return L10n.string(isEditing ? "编辑子任务" : "添加子任务")
        }
        return L10n.string(isEditing ? "编辑待办" : "添加待办")
    }
}

private extension TodoItem.Priority {
    var displayColor: NSColor {
        switch self {
        case .none: .secondaryLabelColor
        case .low: .systemGreen
        case .medium: .systemBlue
        case .high: .systemRed
        }
    }
}

private extension TodoItem.Urgency {
    var displayColor: NSColor {
        switch self {
        case .none: .secondaryLabelColor
        case .canWait: .systemGreen
        case .today: .systemBlue
        case .mustToday: .systemRed
        }
    }
}
