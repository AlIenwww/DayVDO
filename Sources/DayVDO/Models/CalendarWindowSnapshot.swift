import Combine
import Foundation

struct CalendarWindowSnapshot: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        var revision: UInt64
        var firstDay: LocalDay
        var lastDay: LocalDay
        var timeZoneIdentifier: String
        var firstWeekday: Int
        var visibility: TodoFilterContext

        func matchesContent(of other: Key) -> Bool {
            revision == other.revision && timeZoneIdentifier == other.timeZoneIdentifier
                && firstWeekday == other.firstWeekday && visibility == other.visibility
        }

        func covers(_ other: Key) -> Bool {
            matchesContent(of: other) && firstDay <= other.firstDay && lastDay >= other.lastDay
        }
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
    var dateLayoutsByWeek: [LocalDay: CalendarDateLayout] = [:]

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
            .filter {
                guard key.visibility.includes($0),
                      let start = $0.startDay, let end = $0.dueDay, start <= end else { return false }
                return start <= key.lastDay && end >= key.firstDay
            }
            .sorted(by: areInIncreasingOrder)
        var result: [LocalDay: [Item]] = [:]
        var ranged: [Item] = []

        for item in sortedItems {
            if Task.isCancelled { break }
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
                if Task.isCancelled { break }
                result[day, default: []].append(summary)
                day = day.adding(days: 1)
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: key.timeZoneIdentifier) ?? .autoupdatingCurrent
        calendar.firstWeekday = key.firstWeekday
        var weeks: [LocalDay: [Item]] = [:]
        for item in ranged {
            if Task.isCancelled { break }
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
        let dateLayouts = Dictionary(uniqueKeysWithValues: weeks.map { week, items in
            (week, CalendarDateLayout(segments: CalendarDatePolicy.segments(items, week: week)))
        })
        return CalendarWindowSnapshot(key: key, rangedItems: ranged,
                                      itemsByDay: result, itemsByWeek: weeks,
                                      dateLayoutsByWeek: dateLayouts)
    }

    static func areInIncreasingOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
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
    private var workerTask: Task<CalendarWindowSnapshot, Never>?
    private struct Waiter {
        let key: CalendarWindowSnapshot.Key
        let continuation: CheckedContinuation<Bool, Never>
        let timeout: Task<Void, Never>
    }
    private var waiters: [UUID: Waiter] = [:]

    func hasSnapshot(covering key: CalendarWindowSnapshot.Key) -> Bool {
        snapshot?.key.covers(key) == true
    }

    func snapshotForDisplay(matching key: CalendarWindowSnapshot.Key) -> CalendarWindowSnapshot? {
        guard var result = snapshot,
              result.key.timeZoneIdentifier == key.timeZoneIdentifier,
              result.key.firstWeekday == key.firstWeekday else { return nil }
        // Keep task identities on screen while the replacement builds. Rows
        // resolve current tasks and filters; stale layouts would bypass that.
        if !result.key.matchesContent(of: key) {
            result.dateLayoutsByWeek = [:]
        }
        return result
    }

    func prepare(_ request: CalendarWindowRequest, priority: TaskPriority = .utility) {
        if hasSnapshot(covering: request.key) {
            if buildTask != nil, requestedKey?.covers(request.key) != true {
                buildTask?.cancel()
                workerTask?.cancel()
                buildTask = nil
                workerTask = nil
            }
            return
        }
        if buildTask != nil, requestedKey?.covers(request.key) == true { return }
        requestedKey = request.key
        buildTask?.cancel()
        workerTask?.cancel()
        let worker = Task.detached(priority: priority) {
            CalendarWindowSnapshot.build(key: request.key, items: request.items, tags: request.tags)
        }
        workerTask = worker
        buildTask = Task(priority: priority) { [weak self] in
            let result = await worker.value
            guard !Task.isCancelled,
                  !worker.isCancelled,
                  let self,
                  self.requestedKey == request.key else { return }
            self.snapshot = result
            self.buildTask = nil
            self.workerTask = nil
            for (id, waiter) in self.waiters where result.key.covers(waiter.key) {
                self.finishWaiting(id, ready: true)
            }
        }
    }

    func waitForSnapshot(covering key: CalendarWindowSnapshot.Key,
                         until deadline: ContinuousClock.Instant) async -> Bool {
        if hasSnapshot(covering: key) { return true }
        guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(until: deadline, clock: .continuous) }
                    catch { return }
                    self?.finishWaiting(id, ready: false)
                }
                waiters[id] = Waiter(key: key, continuation: continuation, timeout: timeout)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishWaiting(id, ready: false) }
        }
    }

    private func finishWaiting(_ id: UUID, ready: Bool) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        waiter.continuation.resume(returning: ready)
    }

    func cancel() {
        buildTask?.cancel()
        workerTask?.cancel()
        buildTask = nil
        workerTask = nil
        requestedKey = nil
        for id in Array(waiters.keys) { finishWaiting(id, ready: false) }
    }
}

struct CalendarEntryPreparation: Sendable {
    let cache: CalendarWindowCache
    let key: CalendarWindowSnapshot.Key

    @MainActor func wait(until deadline: ContinuousClock.Instant) async -> Bool {
        await cache.waitForSnapshot(covering: key, until: deadline)
    }
}

@MainActor
final class CalendarTimelineSession: ObservableObject {
    var topWeek: LocalDay?
}
