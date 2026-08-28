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
            .accessibilityLabel(L10n.string(item.isCompleted ? "标记为未完成" : "标记为已完成"))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    if showsDate, let dueDate = item.dueDate {
                        Label(
                            dueDate.formatted(
                                .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
                            ),
                            systemImage: "calendar"
                        )
                    }
                    if !item.notes.isEmpty {
                        Label(L10n.string("有备注"), systemImage: "text.alignleft")
                    }
                    if item.priority != .none {
                        Label(L10n.string(item.priority.title), systemImage: item.priority.symbolName)
                    }
                    if item.urgency != .none {
                        Label(L10n.string(item.urgency.title), systemImage: item.urgency.symbolName)
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
            .help(L10n.string("编辑待办"))
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.string("编辑"), systemImage: "pencil", action: onEdit)
            Button(L10n.string(item.isCompleted ? "标记为未完成" : "标记为已完成"), systemImage: "checkmark.circle") {
                store.toggle(item)
            }
            Divider()
            Button(L10n.string("删除"), systemImage: "trash", role: .destructive) {
                requestDeletion()
            }
        }
        .confirmationDialog(
            L10n.format("删除“%@”？", item.title),
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(L10n.string("删除"), role: .destructive) { store.delete(item) }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("此操作无法撤销。"))
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
