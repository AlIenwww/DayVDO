import SwiftUI

enum TodoRowPresentation {
    case standard
    case topLevel
}

enum TopLevelTodoRowMetrics {
    static let disclosureWidth: CGFloat = 14
    static let statusWidth: CGFloat = 20
    static let columnSpacing: CGFloat = 12
    static let verticalPadding: CGFloat = 7
    static let listHorizontalInset: CGFloat = 16
    static let separatorLeading: CGFloat = disclosureWidth
        + columnSpacing
        + statusWidth
        + columnSpacing
}

struct TodoRow: View {
    @EnvironmentObject private var store: TodoStore
    @State private var isConfirmingDeletion = false
    let item: TodoItem
    var showsDate = true
    var showsProject = true
    var presentation: TodoRowPresentation = .standard
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: TopLevelTodoRowMetrics.columnSpacing) {
            if presentation == .topLevel {
                Color.clear
                    .frame(
                        width: TopLevelTodoRowMetrics.disclosureWidth,
                        height: 18
                    )
                    .accessibilityHidden(true)
            }

            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .frame(
                        width: TopLevelTodoRowMetrics.statusWidth,
                        height: TopLevelTodoRowMetrics.statusWidth
                    )
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if presentation == .topLevel {
                    if hasTopLevelMetadata {
                        topLevelMetadata
                    } else {
                        Text(" ")
                            .font(.caption)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                } else if hasStandardMetadata {
                    standardMetadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onEdit)
        }
        .padding(
            .vertical,
            presentation == .topLevel ? TopLevelTodoRowMetrics.verticalPadding : 5
        )
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

    private var hasTopLevelMetadata: Bool {
        store.tag(withID: item.tagID) != nil
            || (showsDate && item.dueDate != nil)
            || item.priority != .none
            || item.urgency != .none
            || !item.notes.isEmpty
    }

    private var hasStandardMetadata: Bool {
        store.tag(withID: item.tagID) != nil
            || (showsProject && store.project(withID: item.projectID) != nil)
            || (showsDate && item.dueDate != nil)
            || !item.notes.isEmpty
            || item.priority != .none
            || item.urgency != .none
    }

    private var topLevelMetadata: some View {
        HStack(spacing: 8) {
            tagMetadata

            if showsDate, let dueDate = item.dueDate {
                dateMetadata(dueDate)
            }
            if item.priority != .none {
                statusMetadata(item.priority.title, systemImage: item.priority.symbolName)
            }
            if item.urgency != .none {
                statusMetadata(item.urgency.title, systemImage: item.urgency.symbolName)
            }
            if !item.notes.isEmpty {
                Image(systemName: "text.alignleft")
                    .help(L10n.string("有备注"))
                    .accessibilityLabel(L10n.string("有备注"))
            }
        }
        .metadataRowStyle()
    }

    private var standardMetadata: some View {
        HStack(spacing: 8) {
            tagMetadata

            if showsProject, let project = store.project(withID: item.projectID) {
                Label(project.title, systemImage: "folder")
                    .lineLimit(1)
            }
            if showsDate, let dueDate = item.dueDate {
                dateMetadata(dueDate)
            }
            if !item.notes.isEmpty {
                Label(L10n.string("有备注"), systemImage: "text.alignleft")
                    .lineLimit(1)
            }
            if item.priority != .none {
                statusMetadata(item.priority.title, systemImage: item.priority.symbolName)
            }
            if item.urgency != .none {
                statusMetadata(item.urgency.title, systemImage: item.urgency.symbolName)
            }
        }
        .metadataRowStyle()
    }

    @ViewBuilder
    private var tagMetadata: some View {
        if let tag = store.tag(withID: item.tagID) {
            TaskTagLabel(tag: tag)
                .frame(maxWidth: 120, alignment: .leading)
        }
    }

    private func dateMetadata(_ date: Date) -> some View {
        Label(
            date.formatted(
                .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
            ),
            systemImage: "calendar"
        )
        .lineLimit(1)
    }

    private func statusMetadata(_ title: String, systemImage: String) -> some View {
        Label(L10n.string(title), systemImage: systemImage)
            .lineLimit(1)
    }
}

private extension View {
    func metadataRowStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}
