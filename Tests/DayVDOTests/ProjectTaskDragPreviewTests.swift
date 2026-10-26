import XCTest
@testable import DayVDO

final class ProjectTaskDragPreviewTests: XCTestCase {
    func testHoverMovesDownAndUpAndIgnoresRepeatedTarget() {
        let ids = (0..<4).map { _ in UUID() }
        var drag = ProjectTaskDragPreview(itemID: ids[0], projectID: UUID(), orderedIDs: ids)
        drag.move(over: ids[1])
        XCTAssertEqual(drag.orderedIDs, [ids[1], ids[0], ids[2], ids[3]])
        drag.move(over: ids[1])
        XCTAssertEqual(drag.followingID, ids[2])
        drag.move(over: ids[3])
        XCTAssertEqual(drag.orderedIDs, [ids[1], ids[2], ids[3], ids[0]])
        XCTAssertNil(drag.followingID)
        drag.move(over: ids[2])
        XCTAssertEqual(drag.orderedIDs, [ids[1], ids[0], ids[2], ids[3]])
        drag.move(over: nil)
        XCTAssertEqual(drag.orderedIDs.last, ids[0])
    }

    func testUnknownAndSelfTargetsLeaveOrderUnchanged() {
        let ids = (0..<3).map { _ in UUID() }
        var drag = ProjectTaskDragPreview(itemID: ids[1], projectID: UUID(), orderedIDs: ids)
        drag.move(over: ids[1])
        drag.move(over: UUID())
        XCTAssertEqual(drag.orderedIDs, ids)
    }

    func testPointerCanReverseAcrossTheSameNeighbor() {
        let ids = (0..<3).map { _ in UUID() }
        var drag = ProjectTaskDragPreview(itemID: ids[0], projectID: UUID(), orderedIDs: ids)
        drag.move(over: ids[1])
        drag.move(over: ids[0])
        drag.move(over: ids[1])
        XCTAssertEqual(drag.orderedIDs, ids)
    }
}
