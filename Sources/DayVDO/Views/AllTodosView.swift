import SwiftUI

struct AllTodosView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "待完成"
        case completed = "已完成"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @State private var query = ""
    @State private var filter: Filter = .all

    private var filteredItems: [TodoItem] {
        store.visibleItems.filter { item in
            let matchesQuery = query.isEmpty || item.title.localizedStandardContains(query) || item.notes.localizedStandardContains(query)
            let matchesFilter = switch filter {
            case .all: true
            case .active: !item.isCompleted
            case .completed: item.isCompleted
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                EmptyStateView(
                    title: query.isEmpty ? "还没有待办" : "没有找到结果",
                    message: query.isEmpty ? "添加待办，开始规划接下来的事情。" : "请尝试其他关键词或筛选条件。",
                    symbol: query.isEmpty ? "checklist" : "magnifyingglass"
                )
            } else {
                List(filteredItems) { item in
                    TodoRow(item: item) { editingItem = item }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("总待办")
        .searchable(text: $query, placement: .toolbar, prompt: "搜索待办")
        .toolbar {
            ToolbarItem {
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }
}
