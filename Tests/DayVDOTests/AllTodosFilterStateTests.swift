import XCTest
@testable import DayVDO

final class TodoFilterStateTests: XCTestCase {
    func testActiveCategoryCountCountsCategoriesAndClearResetsEverything() {
        var filter = TodoFilterState()
        let projectID = UUID()
        let tagID = UUID()

        filter.statuses = [.notStarted, .inProgress]
        filter.projectIDs = [projectID]
        filter.includesUnassignedProject = true
        filter.tagIDs = [tagID]
        filter.includesUntagged = true
        filter.priorities = [.medium, .high]
        filter.urgencies = [.today]
        filter.overdueOnly = true

        XCTAssertEqual(filter.activeCategoryCount, 6)
        XCTAssertTrue(filter.isActive)

        filter.clear()
        XCTAssertEqual(filter, TodoFilterState())
        XCTAssertFalse(filter.isActive)
    }

    func testSelectionsUseOrWithinCategoryAndAndBetweenCategories() {
        let projectID = UUID()
        let tagID = UUID()
        let matching = TodoItem(
            title: "匹配",
            priority: .high,
            urgency: .today,
            status: .inProgress,
            projectID: projectID,
            tagID: tagID
        )
        var filter = TodoFilterState()
        filter.statuses = [.notStarted, .inProgress]
        filter.projectIDs = [projectID]
        filter.tagIDs = [tagID]
        filter.priorities = [.medium, .high]
        filter.urgencies = [.today, .mustToday]

        XCTAssertTrue(filter.includes(matching, showCompletedPreference: false))

        var wrongUrgency = matching
        wrongUrgency.urgency = .canWait
        XCTAssertFalse(filter.includes(wrongUrgency, showCompletedPreference: true))

        var wrongProject = matching
        wrongProject.projectID = UUID()
        XCTAssertFalse(filter.includes(wrongProject, showCompletedPreference: true))
    }

    func testUnassignedAndUntaggedAreExplicitMultiSelectOptions() {
        let projectID = UUID()
        let tagID = UUID()
        let unassigned = TodoItem(title: "无归类", priority: .none, urgency: .none)
        let assigned = TodoItem(title: "已归类", projectID: projectID, tagID: tagID)
        var filter = TodoFilterState()
        filter.includesUnassignedProject = true
        filter.includesUntagged = true
        filter.priorities = [.none]
        filter.urgencies = [.none]

        XCTAssertTrue(filter.includes(unassigned, showCompletedPreference: false))
        XCTAssertFalse(filter.includes(assigned, showCompletedPreference: false))

        filter.projectIDs.insert(projectID)
        filter.tagIDs.insert(tagID)
        XCTAssertTrue(filter.includes(assigned, showCompletedPreference: false))
    }

    func testDefaultAndExplicitStatusSelectionHandleCompletedPreference() {
        let active = TodoItem(title: "进行中", status: .inProgress)
        let completed = TodoItem(title: "已完成", status: .completed)
        var filter = TodoFilterState()

        XCTAssertTrue(filter.includes(active, showCompletedPreference: false))
        XCTAssertFalse(filter.includes(completed, showCompletedPreference: false))
        XCTAssertTrue(filter.includes(completed, showCompletedPreference: true))

        filter.statuses = [.completed]
        XCTAssertFalse(filter.includes(active, showCompletedPreference: true))
        XCTAssertTrue(filter.includes(completed, showCompletedPreference: false))
    }

    func testSearchMustMatchAlongsideEveryFilterCategory() {
        var filter = TodoFilterState()
        filter.statuses = [.inProgress]
        let item = TodoItem(title: "目标", status: .inProgress)

        XCTAssertTrue(
            filter.includes(item, showCompletedPreference: false, matchesSearch: true)
        )
        XCTAssertFalse(
            filter.includes(item, showCompletedPreference: false, matchesSearch: false)
        )
    }

    func testProjectChildrenCanBeReducedToOnlyMatchingItems() {
        let projectID = UUID()
        let matching = TodoItem(title: "保留", priority: .high, projectID: projectID)
        let rejected = TodoItem(title: "隐藏", priority: .low, projectID: projectID)
        var filter = TodoFilterState()
        filter.projectIDs = [projectID]
        filter.priorities = [.high]

        let visible = [matching, rejected].filter {
            filter.includes($0, showCompletedPreference: false)
        }

        XCTAssertEqual(visible.map(\.id), [matching.id])
    }

    func testDeletedProjectsAndTagsAreRemovedFromFilter() {
        let retainedProjectID = UUID()
        let deletedProjectID = UUID()
        let retainedTagID = UUID()
        let deletedTagID = UUID()
        var filter = TodoFilterState()
        filter.projectIDs = [retainedProjectID, deletedProjectID]
        filter.tagIDs = [retainedTagID, deletedTagID]

        filter.sanitize(projectIDs: [retainedProjectID], tagIDs: [retainedTagID])

        XCTAssertEqual(filter.projectIDs, [retainedProjectID])
        XCTAssertEqual(filter.tagIDs, [retainedTagID])
    }

    func testOverdueFilterUsesTodayAndCombinesWithOtherCategories() {
        let today = LocalDay(year: 2026, month: 9, day: 18)
        let overdue = TodoItem(
            title: "逾期且进行中",
            dueDate: today.adding(days: -1).date(),
            status: .inProgress
        )
        let future = TodoItem(
            title: "尚未到期",
            dueDate: today.adding(days: 1).date(),
            status: .inProgress
        )
        var filter = TodoFilterState()
        filter.statuses = [.inProgress]
        filter.overdueOnly = true

        XCTAssertEqual(filter.activeCategoryCount, 2)
        XCTAssertTrue(filter.includes(overdue, showCompletedPreference: false, today: today))
        XCTAssertFalse(filter.includes(future, showCompletedPreference: false, today: today))

        var completed = overdue
        completed.status = .completed
        XCTAssertFalse(filter.includes(completed, showCompletedPreference: true, today: today))
    }
}
