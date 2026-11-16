import SwiftUI

extension TodoItem.Status {
    var color: Color {
        switch self {
        case .notStarted: .secondary
        case .inProgress: .orange
        case .completed: .accentColor
        }
    }
}

struct TodoStatusIcon: View {
    let status: TodoItem.Status

    var body: some View {
        Image(systemName: status.symbolName)
            .foregroundStyle(status.color)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(L10n.string(status.title))
    }
}

struct CalendarTaskStatusIcon: View {
    let status: TodoItem.Status
    let animates: Bool

    var body: some View {
        TodoStatusIcon(status: status)
            .symbolEffect(.bounce, options: .speed(1.8), value: status)
            .symbolEffectsRemoved(!animates)
    }
}

struct CalendarTaskStatusTitle: View {
    let title: String
    let isCompleted: Bool

    var body: some View {
        Text(title)
            .opacity(isCompleted ? 0 : 1)
            .overlay(alignment: .leading) {
                Text(title)
                    .strikethrough()
                    .opacity(isCompleted ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(title)
    }
}

struct TodoStatusMenuItems: View {
    @EnvironmentObject private var store: TodoStore
    let item: TodoItem

    var body: some View {
        ForEach(TodoItem.Status.allCases) { status in
            Button {
                _ = store.setStatus(status, for: item)
            } label: {
                Label(
                    L10n.string(status.title),
                    systemImage: item.status == status ? "checkmark" : status.symbolName
                )
            }
            .disabled(item.status == status || !store.canModify)
        }
    }
}
