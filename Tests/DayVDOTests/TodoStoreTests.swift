import XCTest
@testable import DayVDO

final class TodoStoreTests: XCTestCase {
    @MainActor
    func testDayIndexTracksInsertMoveAndDelete() {
        let calendar = Calendar.current
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 9))!
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDOTests-\(UUID().uuidString).json")
        let store = TodoStore(fileURL: fileURL)
        var item = TodoItem(title: "索引测试", dueDate: firstDay)

        store.upsert(item)
        XCTAssertEqual(store.items(on: firstDay).map(\.id), [item.id])

        item.dueDate = secondDay
        store.upsert(item)
        XCTAssertTrue(store.items(on: firstDay).isEmpty)
        XCTAssertEqual(store.items(on: secondDay).map(\.id), [item.id])

        store.delete(item)
        XCTAssertTrue(store.items(on: secondDay).isEmpty)
    }

    @MainActor
    func testLegacySnapshotLoadsItemsAsUnassigned() throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let legacyItem = TodoItem(title: "旧待办", dueDate: .now)
        let snapshot: [String: Any] = [
            "items": [
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyItem))
            ],
            "settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings()))
        ]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: fileURL)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(store.tags.isEmpty)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items[0].projectID)
        XCTAssertNil(store.items[0].projectSortOrder)
        XCTAssertNil(store.items[0].tagID)
    }

    @MainActor
    func testProjectAndChildRelationshipPersists() throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let project = TodoProject(title: "申请大学", notes: "长期准备")
        let child = TodoItem(title: "整理活动列表", projectID: project.id)
        let store = TodoStore(fileURL: fileURL)

        store.upsertProject(project)
        store.upsert(child)

        let reloaded = TodoStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.projects.map(\.id), [project.id])
        XCTAssertEqual(reloaded.items.map(\.projectID), [project.id])
        XCTAssertEqual(reloaded.items(in: reloaded.projects[0]).map(\.title), ["整理活动列表"])
    }

    @MainActor
    func testProjectCompletionTracksChildrenAndReopensAutomatically() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let project = TodoProject(title: "作品集")
        let first = TodoItem(title: "选题", projectID: project.id)
        let second = TodoItem(title: "制作", projectID: project.id)
        store.upsertProject(project)

        XCTAssertFalse(store.projectIsCompleted(project), "Empty projects stay active")

        store.upsert(first)
        store.upsert(second)
        store.toggle(first)
        XCTAssertEqual(store.projectProgress(project).completed, 1)
        XCTAssertFalse(store.projectIsCompleted(project))

        store.toggle(second)
        XCTAssertTrue(store.projectIsCompleted(project))

        store.toggle(first)
        XCTAssertFalse(store.projectIsCompleted(project))
    }

    @MainActor
    func testDeletingProjectCanKeepOrDeleteChildren() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let keptProject = TodoProject(title: "保留任务")
        let keptChild = TodoItem(title: "继续存在", projectID: keptProject.id)
        store.upsertProject(keptProject)
        store.upsert(keptChild)

        store.deleteProject(keptProject, strategy: .keepTasks)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items[0].projectID)
        XCTAssertNil(store.items[0].projectSortOrder)

        let deletedProject = TodoProject(title: "全部删除")
        store.upsertProject(deletedProject)
        store.upsert(TodoItem(title: "随项目删除", projectID: deletedProject.id))

        store.deleteProject(deletedProject, strategy: .deleteTasks)

        XCTAssertEqual(store.items.map(\.title), ["继续存在"])
    }

    @MainActor
    func testProjectItemsUseDateOrderUntilManuallyReordered() throws {
        let calendar = Calendar.current
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)))
        let store = TodoStore(fileURL: temporaryStoreURL())
        let project = TodoProject(title: "排序")
        let undated = TodoItem(title: "无日期", projectID: project.id)
        let later = TodoItem(title: "稍后", dueDate: secondDate, projectID: project.id)
        let sooner = TodoItem(title: "较早", dueDate: firstDate, projectID: project.id)
        store.upsertProject(project)
        store.upsert(undated)
        store.upsert(later)
        store.upsert(sooner)

        XCTAssertEqual(store.items(in: project).map(\.title), ["较早", "稍后", "无日期"])

        store.moveProjectItem(undated.id, before: sooner.id, in: project.id)
        let updatedProject = try XCTUnwrap(store.project(withID: project.id))

        XCTAssertTrue(updatedProject.usesManualTaskOrder)
        XCTAssertEqual(store.items(in: updatedProject).map(\.title), ["无日期", "较早", "稍后"])
    }

    @MainActor
    func testCompletingProjectItemKeepsItsPosition() throws {
        let calendar = Calendar.current
        let firstDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        let secondDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))
        )
        let store = TodoStore(fileURL: temporaryStoreURL())
        let project = TodoProject(title: "固定位置")
        let first = TodoItem(title: "第一项", dueDate: firstDate, projectID: project.id)
        let second = TodoItem(title: "第二项", dueDate: secondDate, projectID: project.id)
        store.upsertProject(project)
        store.upsert(first)
        store.upsert(second)

        store.toggle(first)
        XCTAssertEqual(store.items(in: project).map(\.title), ["第一项", "第二项"])

        store.toggle(first)
        store.moveProjectItem(second.id, before: first.id, in: project.id)
        let manuallyOrderedProject = try XCTUnwrap(store.project(withID: project.id))
        store.toggle(second)

        XCTAssertEqual(
            store.items(in: manuallyOrderedProject).map(\.title),
            ["第二项", "第一项"]
        )
    }

    @MainActor
    func testMovingExistingItemIntoProjectAssignsAProjectOrder() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let project = TodoProject(title: "重新归类")
        var item = TodoItem(title: "原有待办")
        store.upsertProject(project)
        store.upsert(item)

        item.projectID = project.id
        store.upsert(item)

        XCTAssertEqual(store.items[0].projectID, project.id)
        XCTAssertEqual(store.items[0].projectSortOrder, 0)
    }

    @MainActor
    func testProjectDeadlineDoesNotAppearAsCalendarItem() throws {
        let calendar = Calendar.current
        let deadline = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let store = TodoStore(fileURL: temporaryStoreURL())
        store.upsertProject(TodoProject(title: "截止日", dueDate: deadline))

        XCTAssertTrue(store.items(on: deadline).isEmpty)
    }

    @MainActor
    func testTagsPersistWithColorAndAssignments() throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let tag = TaskTag(
            name: "申请",
            color: TagColor(red: 0.18, green: 0.42, blue: 0.73)
        )
        let project = TodoProject(title: "大学申请", tagID: tag.id)
        let item = TodoItem(title: "整理材料", tagID: tag.id)
        let store = TodoStore(fileURL: fileURL)

        XCTAssertTrue(store.upsertTag(tag))
        store.upsertProject(project)
        store.upsert(item)

        let reloaded = TodoStore(fileURL: fileURL)
        let savedTag = try XCTUnwrap(reloaded.tags.first)
        XCTAssertEqual(savedTag.name, "申请")
        XCTAssertEqual(savedTag.color.red, 0.18, accuracy: 0.0001)
        XCTAssertEqual(savedTag.color.green, 0.42, accuracy: 0.0001)
        XCTAssertEqual(savedTag.color.blue, 0.73, accuracy: 0.0001)
        XCTAssertEqual(reloaded.projects.first?.tagID, tag.id)
        XCTAssertEqual(reloaded.items.first?.tagID, tag.id)
    }

    @MainActor
    func testTagNamesAreTrimmedAndCaseInsensitiveDuplicatesAreRejected() {
        let store = TodoStore(fileURL: temporaryStoreURL())

        XCTAssertTrue(store.upsertTag(TaskTag(name: "  Work  ")))
        XCTAssertEqual(store.tags.first?.name, "Work")
        XCTAssertFalse(store.upsertTag(TaskTag(name: "work")))
        XCTAssertFalse(store.upsertTag(TaskTag(name: "   ")))
        XCTAssertEqual(store.tags.count, 1)
    }

    @MainActor
    func testDeletingTagKeepsItemsAndProjectsButClearsAssignments() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let tag = TaskTag(name: "个人")
        XCTAssertTrue(store.upsertTag(tag))
        store.upsertProject(TodoProject(title: "项目", tagID: tag.id))
        store.upsert(TodoItem(title: "待办", tagID: tag.id))

        XCTAssertEqual(store.tagUsageCount(tag), 2)
        store.deleteTag(tag)

        XCTAssertTrue(store.tags.isEmpty)
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.projects[0].tagID)
        XCTAssertNil(store.items[0].tagID)
    }

    @MainActor
    func testTagsCanBeReordered() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let first = TaskTag(name: "第一")
        let second = TaskTag(name: "第二")
        let third = TaskTag(name: "第三")
        XCTAssertTrue(store.upsertTag(first))
        XCTAssertTrue(store.upsertTag(second))
        XCTAssertTrue(store.upsertTag(third))

        store.moveTag(third.id, to: first.id)

        XCTAssertEqual(store.sortedTags.map(\.name), ["第三", "第一", "第二"])

        store.moveTag(third.id, to: second.id)

        XCTAssertEqual(store.sortedTags.map(\.name), ["第一", "第二", "第三"])
    }

    @MainActor
    func testNewProjectItemInheritsTagWithoutLinkingFutureChanges() {
        let store = TodoStore(fileURL: temporaryStoreURL())
        let originalTag = TaskTag(name: "长期")
        let replacementTag = TaskTag(name: "其他")
        XCTAssertTrue(store.upsertTag(originalTag))
        XCTAssertTrue(store.upsertTag(replacementTag))
        var project = TodoProject(title: "大项目", tagID: originalTag.id)
        store.upsertProject(project)

        let child = store.newItem(in: project)
        XCTAssertEqual(child.tagID, originalTag.id)

        project.tagID = replacementTag.id
        store.upsertProject(project)
        XCTAssertEqual(child.tagID, originalTag.id)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DayVDOTests-\(UUID().uuidString).json")
    }
}
