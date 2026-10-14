import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

final class CalendarNativeScrollAnimatorTests: XCTestCase {
    @MainActor
    func testSnapMovesClipViewThroughIntermediatePositionsBeforeCompletion() async throws {
        for curve in [nil, UnitCurve.easeInOut] {
            let scroll = makeScrollView()
            let animator = CalendarNativeScrollAnimator()
            defer { animator.cancel() }
            var positions: [CGFloat] = []
            var completed = false
            animator.start(from: .zero, to: NSPoint(x: 0, y: 600), framesPerSecond: 60, curve: curve) { point in
                scroll.contentView.scroll(to: point)
                positions.append(scroll.contentView.bounds.minY)
            } completion: {
                completed = true
            }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(completed)
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
            XCTAssertLessThan(scroll.contentView.bounds.minY, 600)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(completed)
            XCTAssertEqual(scroll.contentView.bounds.minY, 600, accuracy: 0.01)
            XCTAssertGreaterThan(positions.count, 2)
            XCTAssertTrue(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @MainActor
    func testInterruptedSnapCannotMoveOrCompleteAfterNewScroll() async throws {
        let scroll = makeScrollView()
        let animator = CalendarNativeScrollAnimator()
        defer { animator.cancel() }
        var oldCompletion = false
        animator.start(from: .zero, to: NSPoint(x: 0, y: 600), framesPerSecond: 60) { point in
            scroll.contentView.scroll(to: point)
        } completion: {
            oldCompletion = true
        }
        try await Task.sleep(for: .milliseconds(70))
        animator.cancel()
        // Simulate fresh wheel input after cancelling the in-flight snap.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(scroll.contentView.bounds.minY, 180, accuracy: 0.01)
        XCTAssertFalse(oldCompletion)

        var newCompletion = false
        animator.start(from: scroll.contentView.bounds.origin, to: NSPoint(x: 0, y: 300),
                       framesPerSecond: 60) { point in
            scroll.contentView.scroll(to: point)
        } completion: {
            newCompletion = true
        }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(newCompletion)
        XCTAssertFalse(oldCompletion)
        XCTAssertEqual(scroll.contentView.bounds.minY, 300, accuracy: 0.01)
    }

    @MainActor
    private func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 2400))
        scroll.contentView.scroll(to: .zero)
        return scroll
    }
}
