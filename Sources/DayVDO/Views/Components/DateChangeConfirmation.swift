import SwiftUI

private struct DateChangeConfirmationModifier: ViewModifier {
    @EnvironmentObject private var store: TodoStore
    @Binding var request: TodoStore.DateChangeConfirmation?
    var saved: (TodoItem) -> Void
    @State private var failed = false

    func body(content: Content) -> some View {
        content.alert(L10n.string("修改日期将删除时间安排"), isPresented: Binding(
            get: { request != nil }, set: { if !$0 { request = nil } }
        ), presenting: request) { value in
            Button(L10n.string("取消"), role: .cancel) { request = nil }
            Button(L10n.string("删除安排并修改日期"), role: .destructive) {
                if store.confirmDateChange(value) { saved(value.candidate) }
                else { failed = true }
                request = nil
            }
        } message: { value in
            Text(L10n.format("原日期：%@\n新日期：%@\n将删除此待办的全部 %lld 段时间安排。",
                             range(value.original), range(value.candidate), value.schedules.count))
        }
        .alert(L10n.string("内容已变化，请重试。"), isPresented: $failed) {
            Button(L10n.string("完成"), role: .cancel) {}
        }
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
