import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published var settings = AppSettings() {
        didSet { save() }
    }

    private struct Snapshot: Codable {
        var items: [TodoItem]
        var settings: AppSettings
    }

    private let fileURL: URL
    private var isLoading = false

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        if fileURL == nil {
            Self.migrateLegacyDataIfNeeded(to: resolvedURL)
        }
        self.fileURL = resolvedURL
        load()
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DayVDO", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    private static func migrateLegacyDataIfNeeded(to destination: URL) {
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let legacyURL = destination.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Daymark", isDirectory: true)
            .appendingPathComponent("todos.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL) else { return }

        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: destination, options: .atomic)
    }

    var todayItems: [TodoItem] {
        items.filter { $0.isDue(on: .now) }.sorted(by: TodoStore.areInIncreasingOrder)
    }

    var visibleItems: [TodoItem] {
        items.filter { settings.showCompleted || !$0.isCompleted }.sorted(by: TodoStore.areInIncreasingOrder)
    }

    func items(on date: Date) -> [TodoItem] {
        items.filter { $0.isDue(on: date) && (settings.showCompleted || !$0.isCompleted) }
            .sorted(by: TodoStore.areInIncreasingOrder)
    }

    func upsert(_ item: TodoItem) {
        var copy = item
        copy.title = copy.normalizedTitle
        guard !copy.title.isEmpty else { return }

        if let index = items.firstIndex(where: { $0.id == copy.id }) {
            items[index] = copy
        } else {
            items.append(copy)
        }
        save()
        objectWillChange.send()
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
        items[index].completedAt = items[index].isCompleted ? .now : nil
        save()
        objectWillChange.send()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
        objectWillChange.send()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        items = snapshot.items
        settings = snapshot.settings
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = Snapshot(items: items, settings: settings)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save DayVDO data: \(error)")
        }
    }

    private static func areInIncreasingOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?): return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.createdAt < rhs.createdAt
        }
    }
}
