import XCTest
@testable import DayVDO

final class LocalizedControlSizingTests: XCTestCase {
    func testPopUpWidthGrowsForLongerLocalizedTitlesAndRemainsBounded() {
        let chinese = LocalizedControlSizing.popUpWidth(for: ["无", "随意", "尽快", "立刻"])
        let french = LocalizedControlSizing.popUpWidth(
            for: ["Facultative", "Essentielle", "À tout moment", "Immédiatement"]
        )

        XCTAssertLessThan(chinese, french)
        XCTAssertGreaterThanOrEqual(chinese, 92)
        XCTAssertLessThanOrEqual(french, 176)
    }

    func testSegmentedWidthAccountsForLongestTitleInEverySegment() {
        let german = LocalizedControlSizing.segmentedWidth(for: ["Alle", "Offen", "Erledigt"])
        let spanish = LocalizedControlSizing.segmentedWidth(
            for: ["Todas", "Pendientes", "Completadas"]
        )

        XCTAssertLessThan(german, spanish)
        XCTAssertGreaterThanOrEqual(german, 210)
        XCTAssertLessThanOrEqual(spanish, 336)
    }

    func testMenuLabelWidthRemainsUsableForShortAndLongTitles() {
        XCTAssertEqual(LocalizedControlSizing.menuLabelWidth(for: ["全部标签"]), 88)
        XCTAssertLessThanOrEqual(
            LocalizedControlSizing.menuLabelWidth(for: [String(repeating: "W", count: 40)]),
            184
        )
    }
}
