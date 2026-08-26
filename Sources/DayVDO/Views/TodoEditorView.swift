import SwiftUI

struct TodoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var hasDueDate: Bool
    @State private var isShowingDatePicker = false
    @FocusState private var titleIsFocused: Bool

    let isEditing: Bool
    let onSave: (TodoItem) -> Void

    init(item: TodoItem, isEditing: Bool, onSave: @escaping (TodoItem) -> Void) {
        _draft = State(initialValue: item)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEditing ? "编辑待办" : "添加待办")
                        .font(.title2.weight(.semibold))
                    Text("记录任务，并选择它应当完成的日期。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("待办名称", text: $draft.title, prompt: Text("添加待办事项"))
                        .font(.title2.weight(.medium))
                        .textFieldStyle(.plain)
                        .focused($titleIsFocused)

                    TextField("备注", text: $draft.notes, prompt: Text("添加备注"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                }
                .padding(20)

                Divider()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "flag")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("优先级")
                        Spacer()
                        Picker("优先级", selection: $draft.priority) {
                            ForEach(TodoItem.Priority.allCases) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("日期")
                        Spacer()
                        Toggle("设置日期", isOn: $hasDueDate)
                            .labelsHidden()

                        if hasDueDate {
                            Button {
                                isShowingDatePicker.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Text((draft.dueDate ?? .now).formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $isShowingDatePicker, arrowEdge: .bottom) {
                                BorderlessCalendarPicker(
                                    selection: Binding(
                                        get: { draft.dueDate ?? .now },
                                        set: { draft.dueDate = $0 }
                                    )
                                )
                                .frame(width: 230, height: 175)
                                .padding(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.normalizedTitle.isEmpty)
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 450)
        .task {
            await Task.yield()
            titleIsFocused = true
        }
        .onChange(of: hasDueDate) { _, enabled in
            draft.dueDate = enabled ? (draft.dueDate ?? .now) : nil
        }
    }

    private func save() {
        if !hasDueDate { draft.dueDate = nil }
        onSave(draft)
        dismiss()
    }
}
