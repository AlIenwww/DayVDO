import SwiftUI

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoProject
    @State private var hasDueDate: Bool
    @State private var isShowingDatePicker = false
    @FocusState private var titleIsFocused: Bool

    let isEditing: Bool
    let onSave: (TodoProject) -> Void

    init(project: TodoProject, isEditing: Bool, onSave: @escaping (TodoProject) -> Void) {
        _draft = State(initialValue: project)
        _hasDueDate = State(initialValue: project.dueDate != nil)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(isEditing ? "编辑大项目" : "新建大项目"))
                    .font(.title2.weight(.semibold))
                Text(L10n.string("将相关待办归入同一个长期目标。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(
                        L10n.string("项目名称"),
                        text: $draft.title,
                        prompt: Text(L10n.string("添加项目名称"))
                    )
                    .font(.title2.weight(.medium))
                    .textFieldStyle(.plain)
                    .focused($titleIsFocused)

                    TextField(
                        L10n.string("备注"),
                        text: $draft.notes,
                        prompt: Text(L10n.string("添加项目说明")),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                }
                .padding(20)

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(L10n.string("标签"))
                    Spacer()
                    TaskTagPicker(selection: $draft.tagID)
                }
                .padding(.horizontal, 20)
                .frame(height: 48)

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(L10n.string("截止日期"))
                    Spacer()
                    Toggle(L10n.string("设置截止日期"), isOn: $hasDueDate)
                        .labelsHidden()

                    if hasDueDate {
                        Button {
                            isShowingDatePicker.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Text(
                                    (draft.dueDate ?? .now).formatted(
                                        .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
                                    )
                                )
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
                            .fixedSize()
                            .padding(10)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 48)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.normalizedTitle.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 438)
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
