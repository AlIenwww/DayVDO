import Foundation

enum TaskDateRangePolicy {
    static func visibleRange(
        for item: TodoItem,
        includeCompleted: Bool,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> ClosedRange<LocalDay>? {
        guard let start = item.startDay, let deadline = item.dueDay, start <= deadline else {
            return nil
        }
        guard item.isCompleted else { return start...deadline }
        guard includeCompleted else { return nil }

        let completionDay = item.completedAt.map { LocalDay($0, timeZone: timeZone) }
        let end = min(deadline, completionDay ?? deadline)
        return start <= end ? start...end : nil
    }

    static func isOverdue(_ item: TodoItem, on day: LocalDay, today: LocalDay) -> Bool {
        guard day == today, !item.isCompleted, let deadline = item.dueDay else { return false }
        return deadline < today
    }

    static func isVisible(
        _ item: TodoItem,
        on day: LocalDay,
        today: LocalDay,
        includeCompleted: Bool,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Bool {
        if isOverdue(item, on: day, today: today) { return true }
        return visibleRange(
            for: item,
            includeCompleted: includeCompleted,
            timeZone: timeZone
        )?.contains(day) == true
    }

    /// The calendar shows only the dates the user assigned. Unlike the Today
    /// panel, it does not add an overdue task to the actual-today cell. A
    /// completed task remains on its original dates when completed tasks are
    /// visible, even if it was checked off before the deadline.
    static func isVisibleInCalendar(
        _ item: TodoItem,
        on day: LocalDay,
        today: LocalDay,
        includeCompleted: Bool,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Bool {
        guard (!item.isCompleted || includeCompleted),
              let start = item.startDay,
              let deadline = item.dueDay,
              start <= deadline else { return false }
        return (start...deadline).contains(day)
    }
}
