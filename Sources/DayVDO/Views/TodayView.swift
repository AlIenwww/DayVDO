import AppKit
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @State private var now = Date.now

    private var active: [TodoItem] { store.todayItems.filter { !$0.isCompleted } }
    private var completed: [TodoItem] { store.todayItems.filter(\.isCompleted) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleTodayItems.isEmpty {
                EmptyStateView(
                    title: L10n.string(
                        store.todayItems.isEmpty ? "今天暂无待办" : "今天的待办已完成"
                    ),
                    message: L10n.string(
                        store.todayItems.isEmpty
                            ? "给今天留下一件值得完成的小事。"
                            : "已完成事项当前已隐藏。"
                    ),
                    symbol: "sun.max"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(L10n.format("待完成 · %lld", active.count)) {
                        ForEach(active) { item in
                            TodoRow(item: item, showsDate: false) { editingItem = item }
                        }
                    }
                    if store.settings.showCompleted, !completed.isEmpty {
                        Section(L10n.format("已完成 · %lld", completed.count)) {
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
        .navigationTitle(L10n.string("今日待办"))
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            now = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            now = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            now = .now
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(now.formatted(.dateTime.month(.wide).day().locale(L10n.locale)))
                    .font(.title2.bold())
                Text(now.formatted(.dateTime.weekday(.wide).locale(L10n.locale)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.todayItems.isEmpty {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(L10n.format("完成 %lld / %lld", completed.count, store.todayItems.count))
                        .font(.callout.weight(.medium))
                    ProgressView(value: Double(completed.count), total: Double(store.todayItems.count))
                        .frame(width: 150)
                }
            }
        }
        .padding(24)
    }

    private var visibleTodayItems: [TodoItem] {
        store.settings.showCompleted ? store.todayItems : active
    }
}
