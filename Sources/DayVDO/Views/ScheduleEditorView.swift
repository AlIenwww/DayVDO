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
                ScheduleEditorView(schedule: schedule) { todo in
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
    @State private var startText: String
    @State private var endText: String
    @State private var nextDay: Bool
    @State private var failed = false
    var editTodo: (TodoItem) -> Void

    init(schedule: DaySchedule, editTodo: @escaping (TodoItem) -> Void) {
        _draft = State(initialValue: schedule)
        if case .independent(let title, let notes) = schedule.content {
            _title = State(initialValue: title); _notes = State(initialValue: notes)
        } else {
            _title = State(initialValue: ""); _notes = State(initialValue: "")
        }
        _startText = State(initialValue: SchedulePresentation.clock(schedule.startMinute))
        _endText = State(initialValue: SchedulePresentation.clock(schedule.endMinute))
        _nextDay = State(initialValue: schedule.endMinute >= 1440)
        self.editTodo = editTodo
    }

    private var linkedTodo: TodoItem? { store.items.first { $0.id == draft.todoID } }
    private var candidate: DaySchedule? {
        guard let start = Self.parse(startText), let end = Self.parse(endText) else { return nil }
        var value = draft
        value.startMinute = start
        value.durationMinutes = end + (nextDay ? 1440 : 0) - start
        if draft.todoID == nil { value.content = .independent(title: title, notes: notes) }
        return value.isValid ? value : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("安排时间")).font(.title2.bold())
            if let todo = linkedTodo {
                Text(todo.title).font(.headline)
                if !todo.notes.isEmpty { Text(todo.notes).foregroundStyle(.secondary).lineLimit(4) }
                Button(L10n.string("编辑原待办")) { dismiss(); editTodo(todo) }
            } else {
                TextField(L10n.string("安排名称"), text: $title).font(.title3)
                TextField(L10n.string("备注"), text: $notes, axis: .vertical).lineLimit(2...5)
            }
            Divider()
            DatePicker(L10n.string("开始日期"), selection: Binding(
                get: { draft.startDay.date() }, set: { draft.startDay = LocalDay($0) }
            ), displayedComponents: .date)
            HStack {
                Text(L10n.string("开始时间"))
                Spacer()
                TextField("09:00", text: $startText).frame(width: 75)
                    .accessibilityLabel(L10n.string("开始时间"))
            }
            HStack {
                Text(L10n.string("结束时间"))
                Spacer()
                Picker(L10n.string("结束日期"), selection: $nextDay) {
                    Text(L10n.string("当天")).tag(false)
                    Text(L10n.string("次日")).tag(true)
                }.labelsHidden().frame(width: 105)
                TextField("09:30", text: $endText).frame(width: 75)
                    .accessibilityLabel(L10n.string("结束时间"))
            }
            Text(L10n.string("使用 24 小时制，单段最长 24 小时。"))
                .font(.caption).foregroundStyle(.secondary)
            if candidate == nil || failed {
                Text(L10n.string("请检查名称及起止时间。"))
                    .font(.caption).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.string("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.string("保存")) {
                    if let value = candidate, store.canModify,
                       store.schedules.contains(value) || store.upsertSchedule(value) { dismiss() }
                    else { failed = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidate == nil || !store.canModify)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 440)
    }

    private static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
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
