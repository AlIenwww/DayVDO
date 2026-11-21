import AppKit
import AVFoundation
import XCTest
@testable import DayVDO

@MainActor
final class OnboardingTests: XCTestCase {
    private var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayVDO-Guide-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        L10n.configure(language: .system)
    }
    private func store() -> TodoStore { TodoStore(fileURL: directory.appendingPathComponent("todos.json")) }

    func testEveryTutorialHasAPlayableBundledRecording() async throws {
        for course in GuideCourse.allCases {
            let url = try XCTUnwrap(L10n.resources.url(forResource: "tutorial-\(course.rawValue)", withExtension: "mp4"))
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            XCTAssertTrue(playable)
            XCTAssertGreaterThan(duration.seconds, 1)
        }
    }

    func testFreshInstallationCanSkipAndDoesNotShowAgain() {
        let formal = store()
        let guide = OnboardingSession(formal: formal)
        guide.presentAutomaticallyIfNeeded()
        XCTAssertTrue(guide.isPresented)
        XCTAssertEqual(guide.progress.step, .preferences)
        XCTAssertTrue(guide.close(skipping: true))
        let reopened = OnboardingSession(formal: formal)
        reopened.presentAutomaticallyIfNeeded()
        XCTAssertFalse(reopened.isPresented)
        reopened.open()
        XCTAssertTrue(reopened.isPresented)
    }

    func testExistingEmptyAndCorruptFilesDoNotTriggerAutomaticGuide() throws {
        let path = directory.appendingPathComponent("todos.json")
        for data in [Data("{}".utf8), Data("broken".utf8)] {
            try data.write(to: path)
            let formal = store()
            XCTAssertFalse(formal.isNewInstallation)
            let guide = OnboardingSession(formal: formal)
            guide.presentAutomaticallyIfNeeded()
            XCTAssertFalse(guide.isPresented)
        }
    }

    func testRecoveryDirectoriesAreNotMistakenForNewInstallations() throws {
        for folder in ["Backups", "Corrupt"] {
            let path = directory.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            XCTAssertFalse(store().isNewInstallation)
            try FileManager.default.removeItem(at: path)
        }
        XCTAssertTrue(store().isNewInstallation)
    }

    func testPracticeProgressRoundTripsWithoutTouchingFormalDataOrLocale() async throws {
        let formal = store()
        formal.settings.language = .english
        formal.upsert(TodoItem(title: "Real task"))
        let saved = await formal.flushPersistence()
        XCTAssertTrue(saved)
        let dataURL = directory.appendingPathComponent("todos.json")
        let before = try Data(contentsOf: dataURL)
        let formalUndo = UndoManager()
        formal.undoManager = formalUndo
        let guide = OnboardingSession(formal: formal)
        guide.open(); guide.startTour()
        XCTAssertEqual(guide.progress.step, .create)
        let practice = try XCTUnwrap(guide.practice)
        practice.settings.language = .japanese
        XCTAssertEqual(L10n.string("设置"), "Settings")
        var item = practice.newItem(dueDate: guide.progress.day.date())
        item.title = "Practice"
        item.estimatedMinutes = 20
        guide.bindDraft(item.id)
        practice.upsert(TodoItem(title: item.title))
        XCTAssertEqual(guide.progress.step, .create)
        XCTAssertTrue(practice.upsert(item))
        XCTAssertEqual(guide.progress.step, .timelineIntro)
        guide.acknowledgeTimeline()
        XCTAssertEqual(guide.progress.step, .schedule)
        let schedule = DaySchedule(startDay: guide.progress.day, startMinute: 540, durationMinutes: 20, content: .todo(item.id))
        XCTAssertTrue(practice.upsertSchedule(schedule))
        XCTAssertEqual(guide.progress.step, .calendarIntro)
        guide.inspected(schedule.id)
        XCTAssertEqual(guide.progress.step, .calendarIntro)
        XCTAssertTrue(guide.close())
        let restored = OnboardingSession(formal: formal)
        restored.open()
        XCTAssertEqual(restored.progress.step, .calendarIntro)
        XCTAssertEqual(restored.progress.day, guide.progress.day)
        XCTAssertEqual(restored.practice?.items, practice.items)
        restored.displayed(.calendar, week: true)
        restored.inspected(schedule.id)
        XCTAssertEqual(restored.progress.step, .calendarIntro)
        restored.displayed(.calendar, week: false)
        XCTAssertEqual(restored.progress.step, .calendarIntro)
        restored.displayed(.calendar, week: true)
        restored.inspected(UUID())
        XCTAssertEqual(restored.progress.step, .locate)
        restored.inspected(schedule.id)
        XCTAssertEqual(restored.progress.step, .complete)
        restored.displayed(.all, week: true)
        XCTAssertTrue(try XCTUnwrap(restored.practice).toggle(item))
        XCTAssertEqual(restored.progress.step, .done)
        XCTAssertTrue(restored.finish())
        let finished = OnboardingSession(formal: formal)
        XCTAssertEqual(finished.progress.status, .completed)
        XCTAssertNil(finished.progress.snapshot)
        XCTAssertNil(restored.practice)
        XCTAssertFalse(restored.undoManager.canUndo)
        XCTAssertEqual(try Data(contentsOf: dataURL), before)
        XCTAssertEqual(formal.items.map(\.title), ["Real task"])
        XCTAssertFalse(formalUndo.canUndo)
        XCTAssertFalse(practice.hasPendingPersistence)
        finished.open()
        XCTAssertEqual(finished.progress.step, .preferences)
        XCTAssertNil(finished.practice)
    }

    func testPracticeUndoAndRestartAreIsolated() throws {
        let formal = store()
        let undo = UndoManager(); undo.groupsByEvent = false
        formal.undoManager = undo
        undo.beginUndoGrouping()
        formal.upsert(TodoItem(title: "Real"))
        undo.endUndoGrouping()
        let guide = OnboardingSession(formal: formal)
        guide.undoManager.groupsByEvent = false
        guide.open(); guide.startTour()
        let practice = try XCTUnwrap(guide.practice)
        guide.undoManager.beginUndoGrouping()
        practice.upsert(TodoItem(title: "Example", dueDate: guide.progress.day.date()))
        guide.undoManager.endUndoGrouping()
        guide.undoManager.undo()
        XCTAssertTrue(practice.items.isEmpty)
        XCTAssertEqual(formal.items.count, 1)
        XCTAssertTrue(undo.canUndo)
        guide.undoManager.redo()
        XCTAssertEqual(practice.items.count, 1)
        guide.restart()
        XCTAssertNil(guide.practice)
        XCTAssertFalse(guide.undoManager.canUndo)
        XCTAssertEqual(formal.items.count, 1)
    }

    func testPracticeCannotInvokeFormalRecovery() async throws {
        let formal = store()
        let guide = OnboardingSession(formal: formal)
        guide.open(); guide.startTour()
        let practice = try XCTUnwrap(guide.practice)
        practice.upsert(TodoItem(title: "Keep practice"))
        await practice.continueWithEmptyDataNow()
        await practice.restoreLatestBackupNow()
        XCTAssertEqual(practice.items.map(\.title), ["Keep practice"])
        XCTAssertNil(practice.persistenceIssue)
        XCTAssertNil(formal.persistenceIssue)
    }

    func testCorruptPracticeDataDoesNotChangeFormalRecoveryState() throws {
        let formal = store()
        let guideURL = directory.appendingPathComponent("invalid-guide.json")
        try Data("invalid".utf8).write(to: guideURL)
        let guide = OnboardingSession(formal: formal, stateURL: guideURL)
        guide.open()
        XCTAssertTrue(guide.needsReset)
        XCTAssertNil(guide.practice)
        XCTAssertNotNil(guide.error)
        XCTAssertNil(formal.persistenceIssue)
        XCTAssertTrue(formal.canModify)
        guide.restart()
        XCTAssertFalse(guide.needsReset)
        XCTAssertNil(guide.error)
    }

    func testSaveFailureBlocksExitAndLeavesFormalDataAlone() throws {
        let formal = store()
        let obstruction = directory.appendingPathComponent("file-not-folder")
        try Data().write(to: obstruction)
        let guide = OnboardingSession(formal: formal, stateURL: obstruction.appendingPathComponent("session.json"))
        guide.open()
        XCTAssertNotNil(guide.error)
        XCTAssertFalse(guide.close())
        XCTAssertTrue(guide.isPresented)
        XCTAssertNil(formal.persistenceIssue)
        try FileManager.default.removeItem(at: obstruction)
        XCTAssertTrue(guide.persist())
        XCTAssertTrue(guide.close())
    }

    func testTutorialsKeepIndependentProgressAndRestoreUndoAfterRelaunch() throws {
        let formal = store()
        let guide = OnboardingSession(formal: formal)
        guide.open(.timeline)
        let practice = try XCTUnwrap(guide.practice)
        var block = try XCTUnwrap(guide.targetSchedule)
        let originalDuration = block.durationMinutes
        block.startMinute += 55
        practice.upsertSchedule(block)
        XCTAssertEqual(guide.progress.step, .resize)
        block.durationMinutes += 10
        practice.upsertSchedule(block)
        XCTAssertEqual(guide.progress.step, .undoResize)
        XCTAssertTrue(guide.close())

        let resumed = OnboardingSession(formal: formal)
        resumed.open(.dates)
        var item = try XCTUnwrap(resumed.targetTodo)
        let day = resumed.progress.day
        item.startDay = day
        item.dueDay = day.adding(days: 2)
        item.estimatedMinutes = 30
        resumed.practice?.upsert(item)
        XCTAssertEqual(resumed.progress.step, .seeDates)
        resumed.displayed(.calendar, week: true)
        XCTAssertEqual(resumed.progress.step, .seeDates)
        resumed.displayed(.calendar, week: false)
        XCTAssertTrue(resumed.finish())
        resumed.open(.timeline)
        XCTAssertEqual(resumed.progress.step, .undoResize)
        XCTAssertTrue(resumed.undoManager.canUndo)
        resumed.undoManager.undo()
        XCTAssertEqual(resumed.targetSchedule?.durationMinutes, originalDuration)
        XCTAssertEqual(resumed.progress.step, .done)
        XCTAssertTrue(resumed.finish())
        XCTAssertEqual(resumed.status(.dates), .completed)
        XCTAssertEqual(resumed.status(.tour), .notStarted)
    }

    func testCalendarOrganizationAndSearchLessonsUseRealTargets() throws {
        let guide = OnboardingSession(formal: store())
        guide.open(.calendar)
        let practice = try XCTUnwrap(guide.practice)
        var item = try XCTUnwrap(guide.targetTodo)
        item.dueDate = guide.progress.day.adding(days: 1).date()
        let request = try XCTUnwrap(practice.dateChangeConfirmation(for: item))
        XCTAssertTrue(practice.confirmDateChange(request, scheduleAction: .keepAsIndependent))
        XCTAssertEqual(guide.progress.step, .inspectWeek)
        guide.displayed(.calendar, week: true)
        XCTAssertEqual(guide.progress.step, .undoDate)
        guide.undoManager.undo()
        XCTAssertEqual(guide.progress.step, .done)
        XCTAssertTrue(guide.finish())

        guide.open(.organize)
        var task = try XCTUnwrap(guide.targetTodo)
        task.projectID = guide.progress.projectID
        task.tagID = guide.progress.tagID
        guide.practice?.upsert(task)
        XCTAssertEqual(guide.progress.step, .tagSearch)
        var filter = TodoFilterState()
        filter.tagIDs = [try XCTUnwrap(task.tagID)]
        guide.filtered(query: "", filter: filter, at: .all)
        XCTAssertTrue(guide.finish())
        guide.open(.find)
        guide.filtered(query: "wrong", filter: .init(), at: .all)
        XCTAssertEqual(guide.progress.step, .search)
        guide.filtered(query: try XCTUnwrap(guide.targetTodo?.title), filter: .init(), at: .all)
        filter.tagIDs = [try XCTUnwrap(guide.progress.tagID)]
        guide.filtered(query: "", filter: filter, at: .all)
        guide.displayed(.calendar, week: false)
        guide.filtered(query: "", filter: filter, at: .calendar)
        XCTAssertEqual(guide.progress.step, .clearFilter)
        guide.filtered(query: "", filter: .init(), at: .calendar)
        XCTAssertTrue(guide.finish())
    }

    func testRecoveryRestoresOnlyTheDeletedExampleAndItsTimeBlock() throws {
        let guide = OnboardingSession(formal: store())
        guide.open()
        guide.startTour()
        let practice = try XCTUnwrap(guide.practice)
        let day = guide.progress.day
        let original = TodoItem(title: "Reading", dueDate: day.date())
        let other = TodoItem(title: original.title, dueDate: day.date())
        guide.bindDraft(original.id)
        practice.upsert(original)
        practice.upsert(other)
        let block = DaySchedule(startDay: day, startMinute: 675, durationMinutes: 25, content: .todo(original.id))
        practice.upsertSchedule(block)
        XCTAssertTrue(practice.delete(original))
        XCTAssertNil(guide.targetTodo)
        guide.restoreExample()
        XCTAssertEqual(guide.targetTodo, original)
        XCTAssertEqual(guide.targetSchedule, block)
        XCTAssertEqual(guide.progress.step, .calendarIntro)
        XCTAssertEqual(practice.item(withID: other.id), other)
    }

    func testFinishingAndSwitchingCoursesOutlivePendingAutosaves() async throws {
        let formal = store()
        let guide = OnboardingSession(formal: formal)
        guide.open(.organize)
        var item = try XCTUnwrap(guide.targetTodo)
        item.projectID = guide.progress.projectID
        item.tagID = guide.progress.tagID
        guide.practice?.upsert(item)
        var filter = TodoFilterState()
        filter.tagIDs = [try XCTUnwrap(item.tagID)]
        guide.filtered(query: "", filter: filter, at: .all)
        XCTAssertTrue(guide.finish())
        guide.open(.dates)
        let nextID = guide.progress.todoID
        try await Task.sleep(for: .milliseconds(200))
        let restored = OnboardingSession(formal: formal)
        XCTAssertEqual(restored.status(.organize), .completed)
        restored.open(.dates)
        XCTAssertEqual(restored.progress.todoID, nextID)
        XCTAssertEqual(restored.progress.step, .dateRange)
    }

    func testLegacyResumeRetainsTaskIdentityAndLeavesOriginalRecord() throws {
        let formal = store()
        let path = formal.fileURL.deletingLastPathComponent().appendingPathComponent("Onboarding/session-v1.json")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let day = LocalDay(.now)
        let task = TodoItem(title: "legacy task", dueDate: day.date())
        let block = DaySchedule(startDay: day, startMinute: 600, durationMinutes: 15, content: .todo(task.id))
        let snapshot = TodoSnapshot(items: [task], projects: [], tags: [], settings: formal.settings, schedules: [block])
        let encoder = JSONEncoder()
        let old: [String: Any] = ["version": 1, "step": 4, "status": "paused", "todoID": task.id.uuidString,
                                  "day": try JSONSerialization.jsonObject(with: encoder.encode(day), options: .fragmentsAllowed),
                                  "snapshot": try JSONSerialization.jsonObject(with: encoder.encode(snapshot))]
        let data = try JSONSerialization.data(withJSONObject: old)
        try data.write(to: path)
        let guide = OnboardingSession(formal: formal)
        guide.presentAutomaticallyIfNeeded()
        XCTAssertFalse(guide.isPresented)
        guide.open()
        XCTAssertEqual(guide.progress.step, .calendarIntro)
        XCTAssertEqual(guide.targetTodo?.id, task.id)
        XCTAssertTrue(guide.close())
        XCTAssertEqual(try Data(contentsOf: path), data)
    }

    func testCompletedTourCanPointToTutorialsInRealSettings() throws {
        let formal = store()
        let navigation = AppNavigation(store: formal)
        let guide = navigation.guide
        guide.open()
        guide.startTour()
        let practice = try XCTUnwrap(guide.practice)
        let day = guide.progress.day
        let todo = TodoItem(title: "Reading", dueDate: day.date())
        guide.bindDraft(todo.id)
        XCTAssertTrue(practice.upsert(todo))
        let schedule = DaySchedule(startDay: day, startMinute: 600, durationMinutes: 20, content: .todo(todo.id))
        XCTAssertTrue(practice.upsertSchedule(schedule))
        guide.displayed(.calendar, week: false)
        guide.displayed(.calendar, week: true)
        guide.inspected(schedule.id)
        guide.displayed(.all, week: false)
        XCTAssertTrue(practice.setStatus(.completed, for: todo))
        XCTAssertEqual(guide.progress.step, .done)

        navigation.settingsCategory = .help
        navigation.navigate(to: .settings)
        XCTAssertEqual(guide.status(.tour), .completed)
        XCTAssertNil(guide.practice)
        XCTAssertEqual(navigation.currentDestination, .settings)
        XCTAssertEqual(navigation.settingsCategory, .general)
        XCTAssertTrue(navigation.isFindingTutorials)
        navigation.settingsCategory = .help
        XCTAssertTrue(navigation.isFindingTutorials)
        navigation.completeTutorialDiscovery()
        XCTAssertFalse(navigation.isFindingTutorials)
        XCTAssertTrue(formal.items.isEmpty)
    }

    func testNavigationRestoresStartupAndCanLeavePracticeForSettings() {
        let formal = store()
        formal.settings.startupPage = .calendar
        let navigation = AppNavigation(store: formal)
        XCTAssertEqual(navigation.currentDestination, .calendar)
        navigation.settingsCategory = .planning
        navigation.guide.open()
        navigation.navigate(to: .settings)
        XCTAssertFalse(navigation.guide.isPresented)
        XCTAssertEqual(navigation.currentDestination, .settings)
        XCTAssertEqual(navigation.settingsCategory, .planning)
    }
}
