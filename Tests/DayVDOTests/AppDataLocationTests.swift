import XCTest
@testable import DayVDO

final class AppDataLocationTests: XCTestCase {
    func testCompatibilityPackagesUseTheirOwnPortableDataDirectory() {
        let support = URL(fileURLWithPath: "/test/Library/Application Support", isDirectory: true)
        let identifier = "com.wuyuchen.DayVDO.CompatibilityTest.release"
        let url = AppDataLocation.isolatedTestingURL(bundleIdentifier: identifier, enabled: true, applicationSupport: support)
        XCTAssertEqual(url?.path, "/test/Library/Application Support/\(identifier)/todos.json")
        XCTAssertNil(AppDataLocation.isolatedTestingURL(bundleIdentifier: identifier, enabled: false, applicationSupport: support))
        XCTAssertNil(AppDataLocation.isolatedTestingURL(bundleIdentifier: "com.wuyuchen.DayVDO", enabled: true, applicationSupport: support))
        XCTAssertNil(AppDataLocation.isolatedTestingURL(bundleIdentifier: nil, enabled: true, applicationSupport: support))
        XCTAssertNil(AppDataLocation.isolatedTestingURL(bundleIdentifier: identifier + "/../../DayVDO", enabled: true, applicationSupport: support))
    }
}
