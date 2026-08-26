import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var showCompleted = true
    var startWeekOnMonday = true
    var defaultPriority = TodoItem.Priority.none
    var confirmBeforeDeleting = true
}
