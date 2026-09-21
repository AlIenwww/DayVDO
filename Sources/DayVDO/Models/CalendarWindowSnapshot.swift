import Combine
import Foundation

struct CalendarWindowSnapshot: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        var revision: UInt64
        var firstDay: LocalDay
        var lastDay: LocalDay
        var timeZoneIdentifier: String
        var firstWeekday: Int
        var showCompleted: Bool
    }

    struct Item: Identifiable, Equatable, Sendable {
        var id: UUID
        var startDay: LocalDay
        var dueDay: LocalDay
        var title: String
        var status: TodoItem.Status
        var hasProject: Bool
        var tagColor: TagColor?

        var isCompleted: Bool { status == .completed }
    }

    var key: Key
    var rangedItems: [Item]
    var itemsByDay: [LocalDay: [Item]]
    var itemsByWeek: [LocalDay: [Item]] = [:]

    func items(on day: LocalDay) -> [Item] {
        itemsByDay[day] ?? []
    }

    func items(inWeek week: LocalDay) -> [Item] {
        itemsByWeek[week] ?? []
    }

    static func build(
        key: Key,
        items: [TodoItem],
        tags: [TaskTag]
    ) -> CalendarWindowSnapshot {
        let colorsByTag = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.color) })
        let sortedItems = items
            .filter { key.showCompleted || !$0.isCompleted }
            .sorted(by: areInIncreasingOrder)
        var result: [LocalDay: [Item]] = [:]
        var ranged: [Item] = []

        for item in sortedItems {
            guard let itemStart = item.startDay,
                  let itemEnd = item.dueDay,
                  itemStart <= itemEnd else { continue }
            let first = max(itemStart, key.firstDay)
            let last = min(itemEnd, key.lastDay)
            guard first <= last else { continue }

            let summary = Item(
                id: item.id,
                startDay: itemStart,
                dueDay: itemEnd,
                title: item.title,
                status: item.status,
                hasProject: item.projectID != nil,
                tagColor: item.tagID.flatMap { colorsByTag[$0] }
            )
            ranged.append(summary)
            var day = first
            while day <= last {
                result[day, default: []].append(summary)
                day = day.adding(days: 1)
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: key.timeZoneIdentifier) ?? .autoupdatingCurrent
        calendar.firstWeekday = key.firstWeekday
        var weeks: [LocalDay: [Item]] = [:]
        for item in ranged {
            let first = max(item.startDay, key.firstDay)
            let last = min(item.dueDay, key.lastDay)
            let date = first.date(timeZone: calendar.timeZone)
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            var week = LocalDay(start, timeZone: calendar.timeZone)
            while week <= last {
                weeks[week, default: []].append(item)
                week = week.adding(days: 7)
            }
        }
        return CalendarWindowSnapshot(key: key, rangedItems: ranged,
                                      itemsByDay: result, itemsByWeek: weeks)
    }

    private static func areInIncreasingOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.urgency != rhs.urgency { return lhs.urgency.rawValue > rhs.urgency.rawValue }
        switch (lhs.dueDay, rhs.dueDay) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

struct CalendarWindowRequest: Sendable {
    var key: CalendarWindowSnapshot.Key
    var items: [TodoItem]
    var tags: [TaskTag]
}

@MainActor
final class CalendarWindowCache: ObservableObject {
    @Published private(set) var snapshot: CalendarWindowSnapshot?

    private var requestedKey: CalendarWindowSnapshot.Key?
    private var buildTask: Task<Void, Never>?

    func prepare(_ request: CalendarWindowRequest) {
        if requestedKey == request.key { return }
        if snapshot?.key == request.key {
            buildTask?.cancel()
            buildTask = nil
            requestedKey = request.key
            return
        }
        requestedKey = request.key
        buildTask?.cancel()
        buildTask = Task(priority: .utility) { [weak self] in
            let result = await Task.detached(priority: .utility) {
                CalendarWindowSnapshot.build(
                    key: request.key,
                    items: request.items,
                    tags: request.tags
                )
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.requestedKey == request.key else { return }
            self.snapshot = result
            self.buildTask = nil
        }
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
        requestedKey = nil
    }
}

@MainActor
final class CalendarTimelineSession: ObservableObject {
    var topWeek: LocalDay?
}
