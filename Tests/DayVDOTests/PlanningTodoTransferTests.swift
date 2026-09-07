import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import DayVDO

final class PlanningTodoTransferTests: XCTestCase {
    func testSystemProviderRoundTripWithoutCustomTypeRegistration() async {
        let id = UUID()
        let provider = PlanningTodoTransfer.provider(for: id)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
        XCTAssertTrue(provider.canLoadObject(ofClass: NSURL.self))
        let decoded = await withCheckedContinuation { continuation in
            PlanningTodoTransfer.loadID(from: provider) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(decoded, id)
    }

    func testRejectsUnrelatedAndMalformedURLs() {
        let id = UUID()
        XCTAssertEqual(PlanningTodoTransfer.id(from: PlanningTodoTransfer.url(for: id)), id)
        for raw in [
            "https://todo/\(id)", "dayvdo-planning://other/\(id)",
            "dayvdo-planning://todo/not-a-uuid", "dayvdo-planning://todo/extra/\(id)",
            "dayvdo-planning://todo/\(id)?action=delete", "dayvdo-planning://todo/\(id)#fragment",
            "dayvdo-planning://user@todo/\(id)", "dayvdo-planning://todo:42/\(id)"
        ] {
            XCTAssertNil(PlanningTodoTransfer.id(from: URL(string: raw)!))
        }
    }
}
