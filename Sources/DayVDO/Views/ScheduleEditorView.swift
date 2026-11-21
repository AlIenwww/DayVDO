import SwiftUI

struct SchedulePopoverView: View {
    @EnvironmentObject private var store: TodoStore
    let schedule: DaySchedule
    private let showsCalendarStatus: Bool
    var editTodo: (TodoItem) -> Void
    var close: () -> Void
    @State private var isEditing: Bool

    init(schedule: DaySchedule, startsEditing: Bool, showsCalendarStatus: Bool = false,
         editTodo: @escaping (TodoItem) -> Void,
         close: @escaping () -> Void) {
        self.schedule = schedule
        self.showsCalendarStatus = showsCalendarStatus
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
                ScheduleDetailsView(
                    schedule: schedule,
                    showsCalendarStatus: showsCalendarStatus,
                    close: close,
                    edit: { isEditing = true },
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

struct ScheduleEditorView: View {
    @Environment(\.practiceDay) private var practiceDay
    @Environment(\.lessonSession) private var guide
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
    var close: (() -> Void)?
    var editTodo: (TodoItem) -> Void

    init(schedule: DaySchedule, close: (() -> Void)? = nil, editTodo: @escaping (TodoItem) -> Void) {
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
                .disabled(practiceDay != nil && guide?.course != .dates && guide?.course != .calendar)
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
        .controlSize(.regular)
        .padding(20)
        .frame(width: L10n.prefersCompactControls ? 340 : 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { wasStored = store.schedule(withID: draft.id) != nil }
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
        guard !wasStored || store.schedule(withID: value.id) != nil else { return false }
        return store.schedule(withID: value.id) == value || store.upsertSchedule(value)
    }
}


private struct ScheduleDetailsView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let schedule: DaySchedule
    let showsCalendarStatus: Bool
    let close: () -> Void
    let edit: () -> Void
    let editTodo: (TodoItem) -> Void
    let remove: () -> Void

    private var todo: TodoItem? { store.item(withID: schedule.todoID) }
    private var title: String { SchedulePresentation.title(schedule, store: store) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                let notes = SchedulePresentation.notes(schedule, store: store)
                if !notes.isEmpty {
                    ViewThatFits(in: .vertical) {
                        note(notes)
                        ScrollView { note(notes) }
                    }
                    .frame(maxHeight: 112, alignment: .topLeading)
                }
            }
            .padding(16)

            Divider()

            HStack(spacing: 10) {
                Menu {
                    if let todo {
                        Button(L10n.string("编辑原待办"), systemImage: "checklist") { editTodo(todo) }
                    }
                    Button(L10n.string("移除安排"), systemImage: "trash", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L10n.string("更多操作"))
                .help(L10n.string("更多操作"))

                Spacer()
                Button(L10n.string("编辑安排"), systemImage: "pencil", action: edit)
                    .buttonStyle(.bordered)
                    .disabled(!store.canModify)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 332)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .help(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L10n.string("完成"))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    time
                    Spacer(minLength: 6)
                    if let todo { status(todo) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    time
                    if let todo { status(todo) }
                }
            }
        }
    }

    private var time: some View {
        Label(SchedulePresentation.time(schedule), systemImage: "clock")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func note(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ todo: TodoItem) -> some View {
        Button {
            _ = store.toggle(todo)
        } label: {
            HStack(spacing: 5) {
                if showsCalendarStatus {
                    CalendarTaskStatusIcon(status: todo.status, animates: statusAnimation != nil)
                } else {
                    TodoStatusIcon(status: todo.status)
                }
                Text(L10n.string(todo.status.title)).contentTransition(.opacity)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.65), in: Capsule())
            .animation(statusAnimation, value: todo.status)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!store.canModify)
        .contextMenu { TodoStatusMenuItems(item: todo) }
    }

    private var statusAnimation: Animation? {
        showsCalendarStatus ? store.settings.calendarTaskStatusAnimation(reduceMotion: reduceMotion) : nil
    }
}
