import AppKit
import Combine

@MainActor
final class CalendarTodoSelection: ObservableObject {
    @Published var selectedID: UUID?
    @Published var draft: TodoItem?
    @Published var pendingDelete: TodoItem?
    var day = LocalDay(.now)
    static let pasteboardType = NSPasteboard.PasteboardType("com.dayvdo.calendar.todo")

    func copy(_ store: TodoStore, to pasteboard: NSPasteboard = .general) {
        guard let item = store.item(withID: selectedID), let data = try? JSONEncoder().encode(item) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.pasteboardType)
        pasteboard.setString(item.title, forType: .string)
    }

    func paste(_ store: TodoStore, from pasteboard: NSPasteboard = .general) {
        guard store.canModify, let data = pasteboard.data(forType: Self.pasteboardType),
              let source = try? JSONDecoder().decode(TodoItem.self, from: data) else { return }
        let target = store.item(withID: selectedID)?.startDay ?? day
        let item = Self.duplicate(source, on: target)
        if store.upsert(item) { selectedID = item.id }
    }

    static func duplicate(_ source: TodoItem, on day: LocalDay) -> TodoItem {
        var copy = source
        copy.id = UUID(); copy.createdAt = .now; copy.projectSortOrder = nil
        let span = max(0, (source.startDay ?? day).distance(to: source.dueDay ?? source.startDay ?? day))
        copy.startDay = day; copy.dueDay = day.adding(days: span)
        copy.status = .notStarted; copy.previousIncompleteStatus = .notStarted; copy.completedAt = nil
        return copy
    }

    func requestDelete(_ store: TodoStore) {
        guard store.canModify, let item = store.item(withID: selectedID) else { return }
        if store.settings.confirmBeforeDeleting { pendingDelete = item }
        else { _ = store.delete(item); selectedID = nil }
    }
}
