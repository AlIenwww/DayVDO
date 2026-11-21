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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingDeletion = false
    let item: TodoItem
    var showsDate = true
    var showsProject = true
    var showsOverdue = false
    var presentation: TodoRowPresentation = .standard
    var animatesCalendarStatus = false
    let onEdit: () -> Void

    var body: some View {
        let calendarAnimation = animatesCalendarStatus
            ? store.settings.calendarTaskStatusAnimation(reduceMotion: reduceMotion) : nil
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
                if animatesCalendarStatus {
                    _ = store.toggle(item)
                } else {
                    withAnimation(store.settings.animation(.snappy(duration: 0.18), for: .completion, reduceMotion: reduceMotion)) {
                        _ = store.toggle(item)
                    }
                }
            } label: {
                Group {
                    if animatesCalendarStatus {
                        CalendarTaskStatusIcon(status: item.status, animates: calendarAnimation != nil)
                            .animation(calendarAnimation, value: item.status)
                    } else {
                        TodoStatusIcon(status: item.status)
                    }
                }
                    .font(.title3)
                    .frame(
                        width: TopLevelTodoRowMetrics.statusWidth,
                        height: TopLevelTodoRowMetrics.statusWidth
                    )
            }
            .buttonStyle(.plain)
            .disabled(!store.canModify)
            .accessibilityLabel(L10n.string(item.isCompleted ? "标记为未完成" : "标记为已完成"))
            .contextMenu { TodoStatusMenuItems(item: item) }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Group {
                        if animatesCalendarStatus {
                            CalendarTaskStatusTitle(title: item.title, isCompleted: item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .animation(calendarAnimation, value: item.status)
                        } else {
                            Text(item.title).strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        }
                    }
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                    if isOverdue {
                        OverdueBadge()
                    }
                }

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
        .disabled(!store.canModify)
        .contextMenu {
            Button(L10n.string("编辑"), systemImage: "pencil", action: onEdit)
            Divider()
            TodoStatusMenuItems(item: item)
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
            Button(L10n.string("删除"), role: .destructive) { _ = store.delete(item) }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("删除后可以从“编辑”菜单撤销。"))
        }
        .allowAppTerminationDuringDialog()
        .accessibilityElement(children: .contain)
        .guideTarget(.row(item.id))
        .accessibilityLabel(item.title)
        .accessibilityValue(L10n.string(item.status.title))
        .accessibilityAction(named: L10n.string("编辑"), onEdit)
        .accessibilityAction(
            named: L10n.string(item.isCompleted ? "标记为未完成" : "标记为已完成")
        ) {
            _ = store.toggle(item)
        }
        .accessibilityAction(named: L10n.string("标记为未开始")) {
            _ = store.setStatus(.notStarted, for: item)
        }
        .accessibilityAction(named: L10n.string("标记为进行中")) {
            _ = store.setStatus(.inProgress, for: item)
        }
        .accessibilityAction(named: L10n.string("标记为已完成")) {
            _ = store.setStatus(.completed, for: item)
        }
    }

    private func requestDeletion() {
        if store.settings.confirmBeforeDeleting {
            isConfirmingDeletion = true
        } else {
            _ = store.delete(item)
        }
    }

    private var isOverdue: Bool {
        guard showsOverdue else { return false }
        let today = LocalDay(.now)
        return TaskDateRangePolicy.isOverdue(item, on: today, today: today)
    }

    private var hasTopLevelMetadata: Bool {
        store.tag(withID: item.tagID) != nil
            || (showsDate && item.startDay != nil)
            || item.priority != .none
            || item.urgency != .none
            || !item.notes.isEmpty
    }

    private var hasStandardMetadata: Bool {
        store.tag(withID: item.tagID) != nil
            || (showsProject && store.project(withID: item.projectID) != nil)
            || (showsDate && item.startDay != nil)
            || !item.notes.isEmpty
            || item.priority != .none
            || item.urgency != .none
    }

    private var topLevelMetadata: some View {
        HStack(spacing: 8) {
            tagMetadata

            if showsDate, item.startDay != nil {
                dateRangeMetadata
            }
            if item.priority != .none {
                statusMetadata(
                    item.priority.title,
                    systemImage: item.priority.symbolName,
                    iconColor: item.priority.swiftUIColor
                )
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
            if showsDate, item.startDay != nil {
                dateRangeMetadata
            }
            if !item.notes.isEmpty {
                Label(L10n.string("有备注"), systemImage: "text.alignleft")
                    .lineLimit(1)
            }
            if item.priority != .none {
                statusMetadata(
                    item.priority.title,
                    systemImage: item.priority.symbolName,
                    iconColor: item.priority.swiftUIColor
                )
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

    private var dateRangeMetadata: some View {
        let start = item.startDay?.date()
        let deadline = item.dueDay?.date()
        let text: String
        if let start, let deadline, item.startDay != item.dueDay {
            let startText = start.formatted(
                .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
            )
            let endText = deadline.formatted(
                .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
            )
            text = "\(startText) – \(endText)"
        } else if let date = start ?? deadline {
            text = date.formatted(
                .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
            )
        } else {
            text = ""
        }
        return Label(
            text,
            systemImage: "calendar"
        )
        .lineLimit(1)
    }

    private func statusMetadata(
        _ title: String,
        systemImage: String,
        iconColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
            Text(L10n.string(title))
        }
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
