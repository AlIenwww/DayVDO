import XCTest
@testable import DayVDO

final class TodoPersistenceTests: XCTestCase {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-Persistence-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("todos.json")
    }

    func testUnchangedSaveDoesNotRewriteFileOrCreateBackup() async throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = TodoPersistence(fileURL: file)
        let snapshot = TodoSnapshot(items: [TodoItem(title: "Keep")], projects: [], tags: [], settings: AppSettings())
        try await writer.save(snapshot)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
        try await writer.save(snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, timestamp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("Backups").path))
        XCTAssertEqual(TodoPersistence.load(from: file).snapshot, snapshot)
    }

    func testDelayedOlderSaveCannotOverwriteNewerGeneration() async throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = TodoPersistence(fileURL: file)
        let older = TodoSnapshot(items: [TodoItem(title: "Older")], projects: [], tags: [], settings: AppSettings())
        let newer = TodoSnapshot(items: [TodoItem(title: "Newer")], projects: [], tags: [], settings: AppSettings())
        try await writer.save(newer, generation: 2)
        try await writer.save(older, generation: 1)
        XCTAssertEqual(TodoPersistence.load(from: file).snapshot, newer)
    }

    @MainActor
    func testOverlappingFlushesAndEditsPersistLatestSnapshot() async throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = TodoStore(fileURL: file)
        var item = TodoItem(title: "Initial")
        store.upsert(item)
        var flushes: [Task<Bool, Never>] = []
        for index in 0..<16 {
            flushes.append(Task { await store.flushPersistence() })
            await Task.yield()
            item.title = "Edit \(index)"
            store.upsert(item)
        }
        for task in flushes {
            let saved = await task.value
            XCTAssertTrue(saved)
        }
        let saved = await store.flushPersistence()
        XCTAssertTrue(saved)
        XCTAssertNil(store.persistenceIssue)
        XCTAssertEqual(TodoStore(fileURL: file).item(withID: item.id), item)
    }

    func testBackupRetentionAndRecoverySkipDamagedNewestBackup() async throws {
        let file = try file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = TodoPersistence(fileURL: file)
        var snapshot = TodoSnapshot(items: [], projects: [], tags: [], settings: AppSettings())
        for index in 0..<8 {
            snapshot.items = [TodoItem(title: "Revision \(index)")]
            try await writer.save(snapshot)
        }
        let directory = file.deletingLastPathComponent().appendingPathComponent("Backups")
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 5)
        let expected = try XCTUnwrap(backups.compactMap { url -> TodoSnapshot? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(TodoSnapshot.self, from: data)
        }.max { $0.items[0].title < $1.items[0].title })
        // Give the newest valid backup a distinct timestamp, independent of filesystem granularity.
        for url in backups {
            let data = try Data(contentsOf: url)
            let value = try JSONDecoder().decode(TodoSnapshot.self, from: data)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: value == expected ? 2_000_000_000 : 1_700_000_000)], ofItemAtPath: url.path)
        }
        let broken = directory.appendingPathComponent("damaged.json")
        try Data("invalid".utf8).write(to: broken)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_100_000_000)], ofItemAtPath: broken.path)
        try Data("invalid primary".utf8).write(to: file)
        let loaded = TodoPersistence.load(from: file)
        XCTAssertTrue(loaded.failedPrimary)
        XCTAssertNil(loaded.snapshot)
        XCTAssertEqual(loaded.recoverySnapshot, expected)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "invalid primary")
    }

    func testDuplicateProjectAndTagIDsAreRejectedBeforeBuildingIndexes() throws {
        let project = TodoProject(title: "Project")
        let tag = TaskTag(name: "Tag", color: TagColor(red: 1, green: 0, blue: 0))
        for snapshot in [
            TodoSnapshot(items: [], projects: [project, project], tags: [], settings: AppSettings()),
            TodoSnapshot(items: [], projects: [], tags: [tag, tag], settings: AppSettings())
        ] {
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertThrowsError(try JSONDecoder().decode(TodoSnapshot.self, from: data))
        }
    }
}
