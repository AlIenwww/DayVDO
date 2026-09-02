import XCTest
@testable import DayVDO

final class AppSettingsTests: XCTestCase {
    func testLegacySettingsUseSystemLanguageAndAutomaticAppearance() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(settings.appearance, .automatic)
        XCTAssertTrue(settings.showCompleted)
        XCTAssertTrue(settings.startWeekOnMonday)
    }

    func testLanguageAndAppearanceRoundTrip() throws {
        var settings = AppSettings()
        settings.language = .english
        settings.appearance = .dark

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.language, .english)
        XCTAssertEqual(decoded.appearance, .dark)
    }

    @MainActor
    func testEnglishLanguageOverrideUsesEnglishResources() {
        L10n.configure(language: .english)
        defer { L10n.configure(language: .system) }

        XCTAssertEqual(L10n.string("今日待办"), "Today")
        XCTAssertEqual(L10n.string("系统默认"), "System Default")
        XCTAssertEqual(L10n.string("新建大项目"), "New Project")
        XCTAssertEqual(L10n.string("无归类"), "No Category")
    }
}
