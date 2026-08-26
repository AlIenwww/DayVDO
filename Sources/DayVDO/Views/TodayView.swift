import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?

    private var active: [TodoItem] { store.todayItems.filter { !$0.isCompleted } }
    private var completed: [TodoItem] { store.todayItems.filter(\.isCompleted) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.todayItems.isEmpty {
                EmptyStateView(
                    title: "今天暂无待办",
                    message: "给今天留下一件值得完成的小事。",
                    symbol: "sun.max"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("待完成 · \(active.count)") {
                        ForEach(active) { item in
                            TodoRow(item: item, showsDate: false) { editingItem = item }
                        }
                    }
                    if store.settings.showCompleted, !completed.isEmpty {
                        Section("已完成 · \(completed.count)") {
                            ForEach(completed) { item in
                                TodoRow(item: item, showsDate: false) { editingItem = item }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("今日待办")
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.month(.wide).day()))
                    .font(.title2.bold())
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.todayItems.isEmpty {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("完成 \(completed.count) / \(store.todayItems.count)")
                        .font(.callout.weight(.medium))
                    ProgressView(value: Double(completed.count), total: Double(store.todayItems.count))
                        .frame(width: 150)
                }
            }
        }
        .padding(24)
    }
}
