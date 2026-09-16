import Foundation

/// Local editor state for progressively choosing a task date and an end date.
/// A single-day task still persists the same day in both existing endpoints.
struct TaskDateInput: Equatable {
    private struct PausedSelection: Equatable {
        var startDay: LocalDay
        var deadline: LocalDay
        var showsEndDate: Bool
        var endDateWasEdited: Bool
    }

    private(set) var hasDate: Bool
    private(set) var showsEndDate: Bool
    private(set) var startDay: LocalDay?
    private(set) var deadline: LocalDay?
    private(set) var endDateWasEdited: Bool
    private var pausedSelection: PausedSelection?

    init(item: TodoItem) {
        hasDate = item.startDay != nil && item.dueDay != nil
        startDay = item.startDay
        deadline = item.dueDay
        // A date supplied by Today, Calendar, or an existing task is already
        // selected. An undated item gets only a provisional date when enabled.
        showsEndDate = hasDate
        endDateWasEdited = hasDate && item.startDay != item.dueDay
        pausedSelection = nil
    }

    var isValid: Bool {
        guard hasDate else { return true }
        guard let startDay, let deadline else { return false }
        return startDay <= deadline
    }

    mutating func setHasDate(_ enabled: Bool, defaultDay: LocalDay) {
        guard enabled != hasDate else { return }
        hasDate = enabled
        if enabled {
            if let pausedSelection {
                startDay = pausedSelection.startDay
                deadline = pausedSelection.deadline
                showsEndDate = pausedSelection.showsEndDate
                endDateWasEdited = pausedSelection.endDateWasEdited
                self.pausedSelection = nil
            } else {
                startDay = defaultDay
                deadline = defaultDay
                showsEndDate = false
                endDateWasEdited = false
            }
        } else {
            if let startDay, let deadline {
                pausedSelection = PausedSelection(
                    startDay: startDay,
                    deadline: deadline,
                    showsEndDate: showsEndDate,
                    endDateWasEdited: endDateWasEdited
                )
            }
            startDay = nil
            deadline = nil
            showsEndDate = false
            endDateWasEdited = false
        }
    }

    mutating func confirmTaskDay() {
        guard hasDate else { return }
        showsEndDate = true
    }

    mutating func chooseTaskDay(_ day: LocalDay) {
        guard hasDate else { return }
        startDay = day
        if !endDateWasEdited { deadline = day }
        showsEndDate = true
    }

    mutating func chooseEndDay(_ day: LocalDay) {
        guard hasDate, showsEndDate else { return }
        deadline = day
        endDateWasEdited = true
    }

    func applying(to item: TodoItem) -> TodoItem {
        var copy = item
        copy.startDay = hasDate ? startDay : nil
        copy.dueDay = hasDate ? deadline : nil
        return copy
    }
}
