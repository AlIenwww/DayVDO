import SwiftUI

struct TodoRow: View {
    @EnvironmentObject private var store: TodoStore
    @State private var isConfirmingDeletion = false
    let item: TodoItem
    var showsDate = true
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.toggle(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "标记为未完成" : "标记为已完成")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    if showsDate, let dueDate = item.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if !item.notes.isEmpty {
                        Label("有备注", systemImage: "text.alignleft")
                    }
                    if item.priority != .none {
                        Label(item.priority.title, systemImage: item.priority.symbolName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("编辑待办")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button(item.isCompleted ? "标记为未完成" : "标记为已完成", systemImage: "checkmark.circle") {
                store.toggle(item)
            }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) {
                requestDeletion()
            }
        }
        .confirmationDialog(
            "删除“\(item.title)”？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { store.delete(item) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private func requestDeletion() {
        if store.settings.confirmBeforeDeleting {
            isConfirmingDeletion = true
        } else {
            store.delete(item)
        }
    }
}
