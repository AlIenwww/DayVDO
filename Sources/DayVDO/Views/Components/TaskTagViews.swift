import SwiftUI

extension TodoItem.Priority {
    var swiftUIColor: Color {
        switch self {
        case .none: .secondary
        case .low: .green
        case .medium: .blue
        case .high: .red
        }
    }
}

struct TaskTagDot: View {
    let tag: TaskTag
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(tag.color.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct TaskTagLabel: View {
    let tag: TaskTag

    var body: some View {
        HStack(spacing: 5) {
            TaskTagDot(tag: tag)
            Text(tag.name)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("标签：%@", tag.name))
    }
}

struct TaskTagPicker: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var selection: UUID?
    @State private var newTagDraft: TaskTag?

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                Label(
                    L10n.string("无标签"),
                    systemImage: selection == nil ? "checkmark" : "minus"
                )
            }

            if !store.sortedTags.isEmpty {
                Divider()
                ForEach(store.sortedTags) { tag in
                    Button {
                        selection = tag.id
                    } label: {
                        HStack {
                            TaskTagDot(tag: tag, size: 9)
                            Text(tag.name)
                            if selection == tag.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()
            Button(L10n.string("新建标签…"), systemImage: "plus") {
                newTagDraft = TaskTag(name: "")
            }
        } label: {
            HStack(spacing: 6) {
                if let selectedTag {
                    TaskTagDot(tag: selectedTag)
                    Text(selectedTag.name)
                        .lineLimit(1)
                } else {
                    Text(L10n.string("无标签"))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: 190, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("标签"))
            .accessibilityValue(selectedTag?.name ?? L10n.string("无标签"))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(!store.canModify)
        .sheet(item: $newTagDraft) { tag in
            TaskTagEditorView(tag: tag, isEditing: false) { savedTag in
                selection = savedTag.id
            }
        }
    }

    private var selectedTag: TaskTag? {
        store.tag(withID: selection)
    }
}

struct TaskTagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @State private var draft: TaskTag
    @State private var selectedColor: Color
    @FocusState private var nameIsFocused: Bool

    let isEditing: Bool
    let onSave: (TaskTag) -> Void

    init(tag: TaskTag, isEditing: Bool, onSave: @escaping (TaskTag) -> Void = { _ in }) {
        _draft = State(initialValue: tag)
        _selectedColor = State(initialValue: tag.color.color)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(isEditing ? "编辑标签" : "新建标签"))
                    .font(.title2.weight(.semibold))
                Text(L10n.string("为标签设置容易辨认的名称和颜色。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            Form {
                TextField(L10n.string("标签名称"), text: $draft.name)
                    .focused($nameIsFocused)
                ColorPicker(L10n.string("标签颜色"), selection: $selectedColor, supportsOpacity: false)
            }
            .formStyle(.grouped)

            if isDuplicateName {
                Text(L10n.string("已经存在同名标签。"))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedName.isEmpty || isDuplicateName || !store.canModify)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 420, height: 310)
        .task {
            await Task.yield()
            nameIsFocused = true
        }
    }

    private var normalizedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        !normalizedName.isEmpty && !store.isTagNameAvailable(normalizedName, excluding: draft.id)
    }

    private func save() {
        draft.name = normalizedName
        draft.color = TagColor(color: selectedColor)
        guard store.upsertTag(draft) else { return }
        onSave(draft)
        dismiss()
    }
}

struct TaskTagManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @State private var editingTag: TaskTag?
    @State private var deletingTag: TaskTag?
    @State private var dropTargetTagID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("管理标签"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.string("创建分类，并为每个标签选择颜色。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingTag = TaskTag(name: "")
                } label: {
                    Label(L10n.string("新建标签"), systemImage: "plus")
                }
            }
            .padding(20)

            Divider()

            if store.sortedTags.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("还没有标签"), systemImage: "tag")
                } description: {
                    Text(L10n.string("创建标签后，可以用颜色整理待办和大项目。"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.sortedTags) { tag in
                    HStack(spacing: 10) {
                        TaskTagDot(tag: tag, size: 10)
                        Text(tag.name)
                            .lineLimit(1)
                        Spacer()
                        Text(L10n.format("%lld 项", store.tagUsageCount(tag)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            editingTag = tag
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.string("编辑标签"))
                        Button {
                            deletingTag = tag
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(L10n.string("删除标签"))
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .top) {
                        if dropTargetTagID == tag.id {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .padding(.horizontal, 4)
                        }
                    }
                    .draggable(tag.id.uuidString)
                    .dropDestination(for: String.self) { values, _ in
                        guard let rawID = values.first,
                              let draggedID = UUID(uuidString: rawID) else { return false }
                        store.moveTag(draggedID, to: tag.id)
                        return true
                    } isTargeted: { targeted in
                        dropTargetTagID = targeted ? tag.id : nil
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
        .sheet(item: $editingTag) { tag in
            TaskTagEditorView(
                tag: tag,
                isEditing: store.tags.contains { $0.id == tag.id }
            )
        }
        .confirmationDialog(
            L10n.format("删除标签“%@”？", deletingTag?.name ?? ""),
            isPresented: Binding(
                get: { deletingTag != nil },
                set: { if !$0 { deletingTag = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tag = deletingTag {
                Button(L10n.string("删除标签"), role: .destructive) {
                    store.deleteTag(tag)
                    deletingTag = nil
                }
            }
            Button(L10n.string("取消"), role: .cancel) { deletingTag = nil }
        } message: {
            if let tag = deletingTag {
                Text(
                    L10n.format(
                        "该标签正用于 %lld 个事项。删除后事项会保留并变为无标签。",
                        store.tagUsageCount(tag)
                    )
                )
            }
        }
    }
}
