import AppKit
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
        guide.open(); guide.advance(); guide.advance()
        XCTAssertEqual(guide.progress.step, .create)
        let practice = try XCTUnwrap(guide.practice)
        XCTAssertFalse(guide.canAdvance)
        practice.settings.language = .japanese
        XCTAssertEqual(L10n.string("设置"), "Settings", "Practice must not reconfigure the process locale")
        var item = practice.newItem(dueDate: guide.progress.day.date())
        item.title = "Practice"
        item.estimatedMinutes = 20
        XCTAssertTrue(practice.upsert(item))
        XCTAssertTrue(guide.canAdvance)
        guide.advance()
        XCTAssertEqual(guide.progress.step, .schedule)
        var schedule = DaySchedule(startDay: guide.progress.day, startMinute: 540, durationMinutes: 20, content: .todo(item.id))
        XCTAssertTrue(practice.upsertSchedule(schedule))
        XCTAssertTrue(guide.canAdvance)
        guide.advance()
        XCTAssertEqual(guide.progress.step, .adjust)
        XCTAssertFalse(guide.canAdvance)
        schedule.startMinute = 600
        XCTAssertTrue(practice.upsertSchedule(schedule))
        XCTAssertTrue(guide.progress.moved)
        XCTAssertFalse(guide.canAdvance)
        schedule.durationMinutes = 30
        XCTAssertTrue(practice.upsertSchedule(schedule))
        XCTAssertTrue(guide.canAdvance)
        XCTAssertTrue(guide.close())

        let restored = OnboardingSession(formal: formal)
        restored.open()
        XCTAssertEqual(restored.progress.step, .adjust)
        XCTAssertEqual(restored.progress.day, guide.progress.day)
        XCTAssertEqual(restored.practice?.items, practice.items)
        XCTAssertEqual(restored.practice?.schedules, practice.schedules)
        XCTAssertTrue(restored.canAdvance)
        restored.advance()
        XCTAssertEqual(restored.progress.step, .complete)
        XCTAssertFalse(restored.canAdvance)
        XCTAssertTrue(try XCTUnwrap(restored.practice).toggle(item))
        XCTAssertTrue(restored.canAdvance)
        restored.advance()
        XCTAssertEqual(restored.progress.step, .discover)
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
        guide.open(); guide.advance(); guide.advance()
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
        guide.open(); guide.advance(); guide.advance()
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
