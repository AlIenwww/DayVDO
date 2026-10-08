import SwiftUI

private struct DateChangeConfirmationModifier: ViewModifier {
    @EnvironmentObject private var store: TodoStore
    @Binding var request: TodoStore.DateChangeConfirmation?
    var saved: (TodoItem) -> Void
    @State private var failed = false

    func body(content: Content) -> some View {
        content.alert(L10n.string("如何处理原时间安排？"), isPresented: Binding(
            get: { request != nil }, set: { if !$0 { request = nil } }
        ), presenting: request) { value in
            Button(L10n.string("保留为普通安排")) {
                resolve(value, action: .keepAsIndependent)
            }
            Button(L10n.string("删除安排"), role: .destructive) {
                resolve(value, action: .delete)
            }
            Button(L10n.string("取消"), role: .cancel) { request = nil }
        } message: { value in
            Text(L10n.format("原日期：%@\n新日期：%@\n需要处理 %lld 段安排。\n\n仅处理新日期范围之外的安排，范围内的安排继续关联此待办。部分超出范围的跨日安排将整段处理。",
                             range(value.original), range(value.candidate), value.affectedSchedules.count))
        }
        .alert(L10n.string("内容已变化，请重试。"), isPresented: $failed) {
            Button(L10n.string("完成"), role: .cancel) {}
        }
    }

    private func resolve(_ value: TodoStore.DateChangeConfirmation, action: TodoStore.DateChangeScheduleAction) {
        if store.confirmDateChange(value, scheduleAction: action) { saved(value.candidate) }
        else { failed = true }
        request = nil
    }

    private func range(_ item: TodoItem) -> String {
        guard let start = item.startDay, let end = item.dueDay else { return L10n.string("无日期") }
        func format(_ day: LocalDay) -> String {
            day.date().formatted(.dateTime.year().month().day().locale(L10n.locale))
        }
        return start == end ? format(start) : "\(format(start)) – \(format(end))"
    }
}

extension View {
    func dateChangeConfirmation(_ request: Binding<TodoStore.DateChangeConfirmation?>,
                                saved: @escaping (TodoItem) -> Void) -> some View {
        modifier(DateChangeConfirmationModifier(request: request, saved: saved))
    }
}
