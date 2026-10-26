import Foundation

actor TodoPersistence {
    private let fileURL: URL
    private let fileManager = FileManager.default
    private var latestGeneration: UInt64 = 0
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func load(from fileURL: URL) -> TodoLoadResult {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return TodoLoadResult() }
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(TodoSnapshot.self, from: data) {
            return TodoLoadResult(snapshot: snapshot)
        }

        let backupDirectory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        let candidates = backupFiles(in: backupDirectory, manager: manager)
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate.url),
                  let recovery = try? JSONDecoder().decode(TodoSnapshot.self, from: data) else {
                continue
            }
            return TodoLoadResult(
                recoverySnapshot: recovery,
                recoveryDate: candidate.modified,
                failedPrimary: true
            )
        }
        return TodoLoadResult(failedPrimary: true)
    }

    func save(_ snapshot: TodoSnapshot, generation: UInt64 = 0) throws {
        // Actor jobs may be prioritized out of enqueue order. A delayed older
        // save must never overwrite a newer snapshot that reached the writer.
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let newData = try encoder.encode(snapshot)

        if let oldData = try? Data(contentsOf: fileURL) {
            guard oldData != newData else { return }
            if (try? JSONDecoder().decode(TodoSnapshot.self, from: oldData)) != nil {
                try createBackup(from: oldData)
            }
        }
        try newData.write(to: fileURL, options: .atomic)
    }

    func replaceCorruptPrimary(with snapshot: TodoSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: fileURL.path) {
            let corruptDirectory = directory.appendingPathComponent("Corrupt", isDirectory: true)
            try fileManager.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
            let destination = corruptDirectory.appendingPathComponent(
                "todos-corrupt-\(Self.timestamp()).json"
            )
            try fileManager.moveItem(at: fileURL, to: destination)
        }
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private func createBackup(from data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("todos-\(Self.timestamp()).json")
        try data.write(to: destination, options: .atomic)

        for backup in Self.backupFiles(in: directory, manager: fileManager).dropFirst(5) {
            try? fileManager.removeItem(at: backup.url)
        }
    }

    private static func backupFiles(in directory: URL, manager: FileManager) -> [(url: URL, modified: Date?)] {
        let urls = (try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.map { url in
            (url: url, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
        }.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    nonisolated private static func timestamp() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString)"
    }
}
