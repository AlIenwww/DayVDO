import Foundation
import XCTest
@testable import DayVDO

final class EstimatedDurationUnitTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testMixedMinutesCarryIntoHours() {
        var input = EstimatedDurationUnit.Input()
        input.minutes = "90"
        XCTAssertEqual(input.value(in: .mixed, locale: english), .minutes(90))
        let normalized = EstimatedDurationUnit.Input(minutes: 90, unit: .mixed, locale: english)
        XCTAssertEqual(normalized.hours, "1")
        XCTAssertEqual(normalized.minutes, "30")

        input.hours = "2"
        input.minutes = "185"
        XCTAssertEqual(input.value(in: .mixed, locale: english), .minutes(305))
    }

    func testMixedAndMinutesAcceptLargeValuesWithoutOverflow() {
        var input = EstimatedDurationUnit.Input()
        input.minutes = String(Int.max)
        XCTAssertEqual(input.value(in: .minutes, locale: english), .minutes(Int.max))
        XCTAssertEqual(input.value(in: .mixed, locale: english), .minutes(Int.max))
        input.hours = "1"
        XCTAssertEqual(input.value(in: .mixed, locale: english), .invalid)
        input = .init()
        XCTAssertEqual(input.value(in: .mixed, locale: english), .empty)
        input.minutes = "-1"
        XCTAssertEqual(input.value(in: .mixed, locale: english), .invalid)
    }

    func testHourInputRespectsLocaleAndPreservesMinutePrecision() {
        let french = Locale(identifier: "fr_FR")
        var input = EstimatedDurationUnit.Input(minutes: 95, unit: .hours, locale: french)
        XCTAssertEqual(input.hours, "1,58")
        XCTAssertEqual(input.value(in: .hours, locale: french), .minutes(95))
        input.hours = "1,25"
        XCTAssertEqual(input.value(in: .hours, locale: french), .minutes(75))
        input.hours = "1,25abc"
        XCTAssertEqual(input.value(in: .hours, locale: french), .invalid)
    }

    @MainActor
    func testEstimateDisplayFollowsTheSelectedUnit() {
        L10n.configure(language: .simplifiedChinese)
        defer { L10n.configure(language: .system) }
        XCTAssertEqual(EstimatedDurationUnit.mixed.formatted(90), "1 小时 30 分钟")
        XCTAssertEqual(EstimatedDurationUnit.mixed.formatted(60), "1 小时")
        XCTAssertEqual(EstimatedDurationUnit.minutes.formatted(90), "90 分钟")
        XCTAssertEqual(EstimatedDurationUnit.hours.formatted(90), "1.5 小时")
    }

    func testUnitPersistsAndDefaultsToMixedForExistingSettings() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data("{}".utf8)).estimatedDurationUnit, .mixed)
        var settings = AppSettings()
        for unit in EstimatedDurationUnit.allCases {
            settings.estimatedDurationUnit = unit
            let saved = try JSONEncoder().encode(settings)
            XCTAssertEqual(try decoder.decode(AppSettings.self, from: saved).estimatedDurationUnit, unit)
        }
    }
}
