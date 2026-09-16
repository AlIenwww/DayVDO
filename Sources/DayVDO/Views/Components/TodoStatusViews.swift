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
