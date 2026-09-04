import Foundation
import XCTest
@testable import DayVDO

final class CoreExperienceTests: XCTestCase {
    func testLocalDayRoundTripsAndStaysTheSameAcrossTimeZones() throws {
        let day = LocalDay(year: 2026, month: 9, day: 2)
        let encoded = try JSONEncoder().encode(day)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"2026-09-02\"")
        XCTAssertEqual(try JSONDecoder().decode(LocalDay.self, from: encoded), day)

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))

        let item = TodoItem(title: "跨时区", dueDate: day.date(timeZone: losAngeles.timeZone))
        var stableItem = item
        stableItem.dueDay = day
        XCTAssertTrue(stableItem.isDue(on: day.date(timeZone: losAngeles.timeZone), calendar: losAngeles))
        XCTAssertTrue(stableItem.isDue(on: day.date(timeZone: tokyo.timeZone), calendar: tokyo))
    }

    func testLegacyAbsoluteDateMigratesToLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let legacyDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9))
        )
        let source = TodoItem(title: "旧日期", dueDate: nil)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any]
        )
        object["dueDate"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacyDate),
            options: [.fragmentsAllowed]
        )

        let migrated = try JSONDecoder().decode(
            TodoItem.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(migrated.dueDay, LocalDay(legacyDate))
    }

    @MainActor
    func testDebouncedStoreWritesVersionedDateOnlySnapshot() async throws {
        let location = try temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = TodoStore(fileURL: location.file)
        store.upsert(TodoItem(title: "日期", dueDate: Date()))

        let didSave = await store.flushPersistence()
        XCTAssertTrue(didSave)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: location.file)) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 2)
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertNotNil(items.first?["dueDate"] as? String)
    }

    @MainActor
    func testStoreKeepsOnlyFiveValidBackups() async throws {
        let location = try temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = TodoStore(fileURL: location.file)
        var item = TodoItem(title: "版本 0")

        for revision in 0..<8 {
            item.title = "版本 \(revision)"
            store.upsert(item)
            let didSave = await store.flushPersistence()
            XCTAssertTrue(didSave)
        }

        let backups = try FileManager.default.contentsOfDirectory(
            at: location.directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backups.count, 5)
        for backup in backups {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: backup)))
        }
    }

    @MainActor
    func testCorruptPrimaryOffersBackupAndRestoresWithoutDeletingCorruptFile() async throws {
        let location = try temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = TodoStore(fileURL: location.file)
        var item = TodoItem(title: "可恢复版本")
        store.upsert(item)
        var didSave = await store.flushPersistence()
        XCTAssertTrue(didSave)
        item.title = "当前版本"
        store.upsert(item)
        didSave = await store.flushPersistence()
        XCTAssertTrue(didSave)
        try Data("not-json".utf8).write(to: location.file, options: .atomic)

        let recovered = TodoStore(fileURL: location.file)
        XCTAssertTrue(recovered.isReadOnly)
        guard case .recoveryRequired(hasBackup: true, backupDate: _) = recovered.persistenceIssue else {
            return XCTFail("Expected a recoverable backup")
        }
        XCTAssertEqual(recovered.items.first?.title, "可恢复版本")

        await recovered.restoreLatestBackupNow()
        XCTAssertFalse(recovered.isReadOnly)
        XCTAssertNil(recovered.persistenceIssue)
        XCTAssertEqual(recovered.items.first?.title, "可恢复版本")
        let corruptFiles = try FileManager.default.contentsOfDirectory(
            at: location.directory.appendingPathComponent("Corrupt"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(corruptFiles.count, 1)
    }

    @MainActor
    func testFailedBackupRecoveryCanRetryTheSameRecoveryAction() async throws {
        let location = try temporaryStoreLocation()
        defer {
            try? FileManager.default.removeItem(at: location.directory)
            try? FileManager.default.removeItem(at: location.directory.deletingLastPathComponent()
                .appendingPathComponent(location.directory.lastPathComponent + "-blocker"))
        }
        let writer = TodoStore(fileURL: location.file)
        var item = TodoItem(title: "备份版本")
        XCTAssertTrue(writer.upsert(item))
        var didSave = await writer.flushPersistence()
        XCTAssertTrue(didSave)
        item.title = "损坏前版本"
        XCTAssertTrue(writer.upsert(item))
        didSave = await writer.flushPersistence()
        XCTAssertTrue(didSave)
        try Data("not-json".utf8).write(to: location.file, options: .atomic)

        let recovered = TodoStore(fileURL: location.file)
        guard case .recoveryRequired(hasBackup: true, backupDate: _) = recovered.persistenceIssue else {
            return XCTFail("Expected a recoverable backup")
        }

        let blocker = location.directory.deletingLastPathComponent()
            .appendingPathComponent(location.directory.lastPathComponent + "-blocker")
        try FileManager.default.moveItem(at: location.directory, to: blocker)
        try Data("blocks the data directory".utf8).write(to: location.directory)

        await recovered.restoreLatestBackupNow()
        guard case .recoveryFailed(action: .restoreBackup, message: _) = recovered.persistenceIssue else {
            return XCTFail("Expected the failed restore action to remain retryable")
        }
        XCTAssertTrue(recovered.isReadOnly)

        try FileManager.default.removeItem(at: location.directory)
        try FileManager.default.moveItem(at: blocker, to: location.directory)
        recovered.retryPersistence()
        let didRecover = await recovered.prepareForTermination()
        XCTAssertTrue(didRecover)

        XCTAssertFalse(recovered.isReadOnly)
        XCTAssertNil(recovered.persistenceIssue)
        XCTAssertEqual(recovered.items.first?.title, "备份版本")
    }

    @MainActor
    func testSaveFailureRemainsVisibleAndCanBeRetried() async throws {
        let location = try temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let blocker = location.directory.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocker)
        let store = TodoStore(fileURL: blocker.appendingPathComponent("todos.json"))
        store.upsert(TodoItem(title: "无法保存"))

        let didSave = await store.flushPersistence()
        XCTAssertFalse(didSave)
        guard case .saveFailed = store.persistenceIssue else {
            return XCTFail("Expected a persistent save error")
        }

        try FileManager.default.removeItem(at: blocker)
        let retried = await store.flushPersistence()
        XCTAssertTrue(retried)
        XCTAssertNil(store.persistenceIssue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blocker.appendingPathComponent("todos.json").path))
    }

    @MainActor
    func testCorruptPrimaryWithoutBackupCanContinueEmptyAndKeepsOriginal() async throws {
        let location = try temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try Data("broken".utf8).write(to: location.file)
        let store = TodoStore(fileURL: location.file)

        XCTAssertEqual(
            store.persistenceIssue,
            .recoveryRequired(hasBackup: false, backupDate: nil)
        )
        XCTAssertTrue(store.isReadOnly)
        XCTAssertFalse(store.upsert(TodoItem(title: "只读时不应写入")))
        XCTAssertTrue(store.items.isEmpty)

        await store.continueWithEmptyDataNow()
        XCTAssertFalse(store.isReadOnly)
        XCTAssertNil(store.persistenceIssue)
        XCTAssertTrue(store.items.isEmpty)
        let corruptFiles = try FileManager.default.contentsOfDirectory(
            at: location.directory.appendingPathComponent("Corrupt"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(corruptFiles.count, 1)
    }

    @MainActor
    func testAppCalendarAppliesWeekPreferenceAfterLocale() {
        let monday = AppCalendar.make(
            locale: Locale(identifier: "zh-Hans"),
            startsOnMonday: true
        )
        let sunday = AppCalendar.make(
            locale: Locale(identifier: "de"),
            startsOnMonday: false
        )
        XCTAssertEqual(monday.firstWeekday, 2)
        XCTAssertEqual(sunday.firstWeekday, 1)
    }

    @MainActor
    func testProjectExpansionPersistsAndNewProjectsStartCollapsed() {
        let suiteName = "DayVDOTests.Expansion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let activeID = UUID()
        let completedID = UUID()

        var state = ProjectExpansionState(defaults: defaults)
        state.synchronize(
            projectIDs: [activeID, completedID],
            completedIDs: [completedID]
        )
        XCTAssertFalse(state.isExpanded(activeID))
        XCTAssertFalse(state.isExpanded(completedID))

        state.setExpanded(true, for: activeID)
        state = ProjectExpansionState(defaults: defaults)
        XCTAssertTrue(state.isExpanded(activeID))
    }

    @MainActor
    func testLegacyAutomaticProjectExpansionIsResetOnce() {
        let suiteName = "DayVDOTests.ExpansionMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let projectID = UUID()
        defaults.set([projectID.uuidString], forKey: "DayVDO.expandedProjectIDs")
        defaults.set([projectID.uuidString], forKey: "DayVDO.knownProjectIDs")

        var state = ProjectExpansionState(defaults: defaults)
        XCTAssertFalse(state.isExpanded(projectID))

        state.setExpanded(true, for: projectID)
        state = ProjectExpansionState(defaults: defaults)
        XCTAssertTrue(state.isExpanded(projectID))
    }

    func testExplicitCompletedFilterOverridesGlobalHiddenPreference() {
        XCTAssertTrue(
            AllTodosFilter.completed.includes(
                isCompleted: true,
                showCompletedPreference: false
            )
        )
        XCTAssertFalse(
            AllTodosFilter.all.includes(
                isCompleted: true,
                showCompletedPreference: false
            )
        )
    }

    @MainActor
    func testUndoRedoPreservesPreferencesAndRestoresContent() {
        let store = TodoStore(fileURL: URL(fileURLWithPath: "/tmp/DayVDO-undo-\(UUID()).json"))
        let manager = UndoManager()
        store.undoManager = manager
        let item = TodoItem(title: "可以撤销")

        store.upsert(item)
        store.settings.showCompleted = false
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.settings.showCompleted)

        manager.redo()
        XCTAssertEqual(store.items.map(\.title), ["可以撤销"])
        XCTAssertFalse(store.settings.showCompleted)

        store.toggle(item)
        XCTAssertTrue(store.items[0].isCompleted)
        manager.undo()
        XCTAssertFalse(store.items[0].isCompleted)

        store.delete(item)
        XCTAssertTrue(store.items.isEmpty)
        manager.undo()
        XCTAssertEqual(store.items.map(\.id), [item.id])
    }

    @MainActor
    func testUndoRestoresProjectMovesOrderingAndTagDeletion() throws {
        let store = TodoStore(fileURL: URL(fileURLWithPath: "/tmp/DayVDO-undo-\(UUID()).json"))
        let manager = UndoManager()
        store.undoManager = manager
        let tag = TaskTag(name: "可恢复标签")
        let project = TodoProject(title: "可恢复项目", tagID: tag.id)
        var first = TodoItem(title: "第一项", tagID: tag.id)
        let second = TodoItem(title: "第二项", projectID: project.id, tagID: tag.id)
        XCTAssertTrue(store.upsertTag(tag))
        store.upsertProject(project)
        store.upsert(first)
        store.upsert(second)

        manager.removeAllActions()
        first.projectID = project.id
        store.upsert(first)
        XCTAssertEqual(store.items.filter { $0.projectID == project.id }.count, 2)
        manager.undo()
        XCTAssertNil(store.items.first(where: { $0.id == first.id })?.projectID)
        manager.redo()
        XCTAssertEqual(store.items.first(where: { $0.id == first.id })?.projectID, project.id)

        manager.removeAllActions()
        store.moveProjectItem(second.id, before: first.id, in: project.id)
        var storedProject = try XCTUnwrap(store.project(withID: project.id))
        XCTAssertEqual(store.items(in: storedProject).map(\.id), [second.id, first.id])
        manager.undo()
        storedProject = try XCTUnwrap(store.project(withID: project.id))
        XCTAssertEqual(store.items(in: storedProject).map(\.id), [first.id, second.id])

        manager.removeAllActions()
        store.deleteTag(tag)
        XCTAssertTrue(store.tags.isEmpty)
        manager.undo()
        XCTAssertEqual(store.tags.map(\.id), [tag.id])
        XCTAssertEqual(store.project(withID: project.id)?.tagID, tag.id)
        XCTAssertTrue(store.items.allSatisfy { $0.tagID == tag.id })
    }

    @MainActor
    func testBothProjectDeletionStrategiesCanBeUndone() {
        for strategy in [
            TodoStore.ProjectDeletionStrategy.keepTasks,
            TodoStore.ProjectDeletionStrategy.deleteTasks
        ] {
            let store = TodoStore(fileURL: URL(fileURLWithPath: "/tmp/DayVDO-undo-\(UUID()).json"))
            let manager = UndoManager()
            store.undoManager = manager
            let project = TodoProject(title: "删除项目")
            let child = TodoItem(title: "子任务", projectID: project.id)
            store.upsertProject(project)
            store.upsert(child)
            manager.removeAllActions()

            store.deleteProject(project, strategy: strategy)
            XCTAssertTrue(store.projects.isEmpty)
            manager.undo()

            XCTAssertEqual(store.projects.map(\.id), [project.id])
            XCTAssertEqual(store.items.map(\.id), [child.id])
            XCTAssertEqual(store.items.first?.projectID, project.id)
        }
    }

    @MainActor
    func testCreatingAndEditingProjectsAndTagsCanBeUndone() {
        let store = TodoStore(fileURL: URL(fileURLWithPath: "/tmp/DayVDO-undo-\(UUID()).json"))
        let manager = UndoManager()
        store.undoManager = manager
        var project = TodoProject(title: "初始项目")

        store.upsertProject(project)
        manager.undo()
        XCTAssertTrue(store.projects.isEmpty)
        manager.redo()
        XCTAssertEqual(store.projects.first?.title, "初始项目")

        manager.removeAllActions()
        project.title = "修改后项目"
        store.upsertProject(project)
        XCTAssertEqual(store.projects.first?.title, "修改后项目")
        manager.undo()
        XCTAssertEqual(store.projects.first?.title, "初始项目")

        manager.removeAllActions()
        let tag = TaskTag(name: "新标签")
        XCTAssertTrue(store.upsertTag(tag))
        manager.undo()
        XCTAssertTrue(store.tags.isEmpty)
        manager.redo()
        XCTAssertEqual(store.tags.first?.id, tag.id)
    }

    @MainActor
    func testLargeDatasetUsesIndexesForProjectProgressAndCompletion() throws {
        let location = try temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let projects = (0..<100).map { TodoProject(title: "项目 \($0)") }
        let items = (0..<1_000).map { index in
            TodoItem(
                title: "待办 \(index)",
                isCompleted: index.isMultiple(of: 3),
                projectID: projects[index % projects.count].id
            )
        }
        let snapshot = PerformanceSnapshot(
            version: 2,
            items: items,
            projects: projects,
            tags: [],
            settings: AppSettings()
        )
        try JSONEncoder().encode(snapshot).write(to: location.file)
        let store = TodoStore(fileURL: location.file)

        let startedAt = CFAbsoluteTimeGetCurrent()
        for project in projects {
            XCTAssertEqual(store.projectProgress(project).total, 10)
        }
        store.toggle(items[999])
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertLessThan(elapsed, 0.25)
        XCTAssertEqual(store.items.count, 1_000)
    }

    private func temporaryStoreLocation() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDOTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("todos.json"))
    }
}

private struct PerformanceSnapshot: Encodable {
    var version: Int
    var items: [TodoItem]
    var projects: [TodoProject]
    var tags: [TaskTag]
    var settings: AppSettings
}
