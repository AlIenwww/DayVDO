import SwiftUI

struct SchedulePopoverView: View {
    @EnvironmentObject private var store: TodoStore
    let schedule: DaySchedule
    var editTodo: (TodoItem) -> Void
    var close: () -> Void
    @State private var isEditing: Bool

    init(schedule: DaySchedule, startsEditing: Bool, editTodo: @escaping (TodoItem) -> Void,
         close: @escaping () -> Void) {
        self.schedule = schedule
        self.editTodo = editTodo
        self.close = close
        _isEditing = State(initialValue: startsEditing)
    }

    var body: some View {
        Group {
            if isEditing {
                ScheduleEditorView(schedule: schedule, close: close) { todo in
                    close()
                    DispatchQueue.main.async { editTodo(todo) }
                }
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Button { close() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel(L10n.string("完成"))
                        .padding([.top, .trailing], 12)
                    ScheduleDetailsView(
                        schedule: schedule,
                        edit: { _ in isEditing = true },
                        editTodo: { todo in
                            close()
                            DispatchQueue.main.async { editTodo(todo) }
                        },
                        remove: {
                            if store.deleteSchedule(schedule.id) { close() }
                        }
                    )
                }
            }
        }
    }
}

struct ScheduleEditorView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DaySchedule
    @State private var title: String
    @State private var notes: String
    @State private var startMinute: Int
    @State private var endMinute: Int
    @State private var nextDay: Bool
    @State private var failed = false
    @State private var wasStored = false
    let isCreating: Bool
    var close: (() -> Void)?
    var editTodo: (TodoItem) -> Void

    init(schedule: DaySchedule, isCreating: Bool = false, close: (() -> Void)? = nil, editTodo: @escaping (TodoItem) -> Void) {
        self.isCreating = isCreating
        _draft = State(initialValue: schedule)
        if case .independent(let title, let notes) = schedule.content {
            _title = State(initialValue: title); _notes = State(initialValue: notes)
        } else {
            _title = State(initialValue: ""); _notes = State(initialValue: "")
        }
        _startMinute = State(initialValue: schedule.startMinute)
        _endMinute = State(initialValue: schedule.endMinute % 1440)
        _nextDay = State(initialValue: schedule.endMinute >= 1440)
        self.close = close
        self.editTodo = editTodo
    }

    private var linkedTodo: TodoItem? { store.items.first { $0.id == draft.todoID } }
    private var candidate: DaySchedule? {
        var value = draft
        value.startMinute = startMinute
        value.durationMinutes = durationMinutes
        if draft.todoID == nil { value.content = .independent(title: title, notes: notes) }
        return value.isValid ? value : nil
    }

    private var durationMinutes: Int { endMinute + (nextDay ? 1440 : 0) - startMinute }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if let todo = linkedTodo {
                    Text(todo.title).font(.title2.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if !todo.notes.isEmpty {
                        Text(todo.notes).foregroundStyle(.secondary).lineLimit(4)
                    }
                    Button(L10n.string("编辑原待办")) {
                        finishEditing()
                        if let latest = store.item(withID: todo.id) { editTodo(latest) }
                    }
                    .buttonStyle(.link)
                } else {
                    TextField(L10n.string("安排名称"), text: $title)
                        .font(.title2.weight(.medium))
                        .textFieldStyle(.plain)
                    TextField(L10n.string("备注"), text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)

            Divider()

            HStack(spacing: 20) {
                Text(L10n.string("开始日期"))
                Spacer(minLength: 0)
                DatePicker(L10n.string("开始日期"), selection: Binding(
                    get: { draft.startDay.date() }, set: { draft.startDay = LocalDay($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.vertical, 12)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.string("开始时间"))
                    ScheduleTimePicker(title: L10n.string("开始时间"), minute: $startMinute)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text(L10n.string("结束时间"))
                    HStack(spacing: 8) {
                        Picker(L10n.string("结束日期"), selection: $nextDay) {
                            Text(L10n.string("当天")).tag(false)
                            Text(L10n.string("次日")).tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                        ScheduleTimePicker(title: L10n.string("结束时间"), minute: $endMinute)
                    }
                }
            }
            .padding(.top, 12)

            if !(1...1440).contains(durationMinutes) || failed {
                Text(L10n.string("请检查名称及起止时间。"))
                    .font(.caption).foregroundStyle(.red)
                    .padding(.top, 10)
            }
            if isCreating {
                Divider().padding(.top, 14)
                HStack(spacing: 10) {
                    Spacer()
                    Button(L10n.string("取消"), role: .cancel, action: dismissEditor)
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.string("保存"), action: saveAndClose)
                        .keyboardShortcut(.defaultAction)
                        .disabled(candidate == nil || !store.canModify)
                }
                .padding(.top, 14)
            }
        }
        .controlSize(.regular)
        .padding(20)
        .frame(width: L10n.prefersCompactControls ? 340 : 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { wasStored = store.schedules.contains { $0.id == draft.id } }
        .onSubmit(saveAndClose)
        .editorReturnSubmission(submit: saveAndClose)
        .onReceive(NotificationCenter.default.publisher(for: .scheduleEditorSubmit)) { notification in
            if notification.object as? UUID == draft.id { saveAndClose() }
        }
        .editorEscapeDismissal(cancel: dismissEditor)
    }

    private func finishEditing() {
        dismissEditor()
    }

    private func dismissEditor() {
        if let close { close() }
        else { dismiss() }
    }

    private func saveAndClose() {
        guard saveIfValid() else { failed = true; return }
        dismissEditor()
    }

    private func saveIfValid() -> Bool {
        guard let value = candidate, store.canModify else { return false }
        // Closing after deletion or Undo must not recreate a removed schedule.
        guard !wasStored || store.schedules.contains(where: { $0.id == value.id }) else { return false }
        return store.schedules.contains(value) || store.upsertSchedule(value)
    }
}


struct ScheduleDetailsView: View {
    @EnvironmentObject private var store: TodoStore
    let schedule: DaySchedule
    var edit: (DaySchedule) -> Void
    var editTodo: (TodoItem) -> Void
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SchedulePresentation.title(schedule, store: store)).font(.headline)
            Text(SchedulePresentation.time(schedule)).foregroundStyle(.secondary)
            let notes = SchedulePresentation.notes(schedule, store: store)
            if !notes.isEmpty { Text(notes).textSelection(.enabled) }
            if let todo = store.items.first(where: { $0.id == schedule.todoID }) {
                Button {
                    _ = store.toggle(todo)
                } label: {
                    HStack(spacing: 6) {
                        TodoStatusIcon(status: todo.status)
                        Text(L10n.string(todo.status.title))
                    }
                }
                .contextMenu { TodoStatusMenuItems(item: todo) }
                Button(L10n.string("编辑原待办")) { editTodo(todo) }
            }
            HStack {
                Button(L10n.string("编辑安排")) { edit(schedule) }
                Button(L10n.string("移除安排"), role: .destructive, action: remove)
            }
        }.padding(20).frame(width: 300)
    }
}
