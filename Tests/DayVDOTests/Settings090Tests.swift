import XCTest
import SwiftUI
@testable import DayVDO

@MainActor
final class Settings090Tests: XCTestCase {
    func testLegacySettingsKeepDefaultsAndNewPreferencesRoundTrip() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{\"showCompleted\":false,\"defaultPriority\":3}".utf8))
        XCTAssertFalse(old.showCompleted)
        XCTAssertEqual(old.defaultPriority, .high)
        XCTAssertEqual(old.startupPage, .today)
        XCTAssertEqual(old.defaultUrgency, .none)
        XCTAssertEqual(old.defaultScheduleMinutes, 30)
        var modified = old
        modified.startupPage = .all; modified.defaultUrgency = .mustToday; modified.defaultScheduleMinutes = 37
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(modified)), modified)
        let invalid = try JSONDecoder().decode(AppSettings.self, from: Data("{\"startupPage\":\"unknown\",\"defaultScheduleMinutes\":0,\"defaultUrgency\":99}".utf8))
        XCTAssertEqual(invalid.startupPage, .today)
        XCTAssertEqual(invalid.defaultUrgency, .none)
        XCTAssertEqual(invalid.defaultScheduleMinutes, 30)
    }

    func testNewTaskFactoryAppliesDefaultsToStandaloneAndProjectTasksOnly() {
        let store = TodoStore(practiceSnapshot: .init(items: [], projects: [], tags: [], settings: .init()))
        let original = store.newItem()
        store.settings.defaultPriority = .high
        store.settings.defaultUrgency = .mustToday
        let project = TodoProject(title: "Project", tagID: UUID())
        for item in [store.newItem(), store.newItem(dueDate: .now), store.newItem(in: project)] {
            XCTAssertEqual(item.priority, .high)
            XCTAssertEqual(item.urgency, .mustToday)
        }
        XCTAssertEqual(store.newItem(in: project).tagID, project.tagID)
        XCTAssertEqual(store.newItem(in: project).projectID, project.id)
        XCTAssertEqual(original.urgency, .none)
    }

    func testDurationValidationAndEstimatePrecedence() {
        for invalid in ["", "0", "1441", "-1", "1.5", "abc"] {
            XCTAssertNil(DefaultScheduleDurationPicker.validatedMinutes(invalid))
        }
        for valid in [1, 37, 1440] {
            XCTAssertEqual(DefaultScheduleDurationPicker.validatedMinutes(" \(valid) "), valid)
            XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: nil, scheduled: 0, fallback: valid), valid)
            XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: 20, scheduled: 20, fallback: valid), valid)
            XCTAssertEqual(DayPlanningPolicy.defaultDuration(estimated: 20, scheduled: 19, fallback: valid), 1)
        }
        XCTAssertEqual(TimelineCreationPolicy.defaultRange(anchoredAt: 540, duration: 37), 540..<577)
        XCTAssertEqual(TimelineCreationPolicy.defaultRange(anchoredAt: 1430, duration: 37), 1430..<1440)
        XCTAssertEqual(TimelineCreationPolicy.defaultRange(anchoredAt: 1440, duration: 37), 1403..<1440)
    }

    func testShortcutChangesRejectConflictsAndRoundTripWithAppearancePreferences() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertNil(settings.themeColor)
        XCTAssertTrue(settings.disabledAnimations.isEmpty)
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
        for command in AppCommand.allCases {
            XCTAssertTrue(command.defaultShortcut.isSupported)
            XCTAssertNil(settings.shortcutConflict(command.defaultShortcut, excluding: command))
        }

        let custom = CommandShortcut(key: "k", option: true)
        XCTAssertTrue(settings.assignShortcut(custom, to: .newTodo))
        XCTAssertEqual(settings.shortcutConflict(custom, excluding: .search), .newTodo)
        XCTAssertFalse(settings.assignShortcut(custom, to: .search))
        XCTAssertEqual(settings.shortcut(for: .search), AppCommand.search.defaultShortcut)
        XCTAssertFalse(settings.assignShortcut(.init(key: "q"), to: .settings))
        XCTAssertFalse(settings.assignShortcut(.init(key: "a"), to: .newTodo))
        XCTAssertFalse(settings.assignShortcut(.init(key: "k", command: false), to: .newTodo))
        XCTAssertTrue(settings.assignShortcut(.init(key: "up", control: true), to: .calendar))
        XCTAssertNotNil(settings.shortcut(for: .calendar).keyboardShortcut)
        XCTAssertEqual(settings.shortcut(for: .calendar).display, "⌃⌘↑")

        settings.themeColor = TagColor(red: 0.3, green: 0.5, blue: 0.7)
        settings.disabledAnimations = [.projectDisclosure, .timelineZoom]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
        XCTAssertFalse(restored.animates(.timelineZoom))
        XCTAssertTrue(restored.animates(.completion))
        XCTAssertNil(restored.animation(.linear, for: .timelineZoom, reduceMotion: false))
        XCTAssertNil(restored.animation(.linear, for: .completion, reduceMotion: true))
        XCTAssertNotNil(restored.animation(.linear, for: .completion, reduceMotion: false))
        XCTAssertTrue(settings.assignShortcut(AppCommand.newTodo.defaultShortcut, to: .newTodo))
        XCTAssertNil(settings.shortcutOverrides[AppCommand.newTodo.rawValue])
    }
}
