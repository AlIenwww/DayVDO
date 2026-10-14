import AppKit
import SwiftUI
import XCTest
@testable import DayVDO

@MainActor
final class CalendarWeekDividerWindowTests: XCTestCase {
    func testBothPanesFollowThePointerBeforeMouseUp() async throws {
        _ = NSApplication.shared
        let probe = DividerProbe()
        let host = NSHostingView(rootView: DividerHarness(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 501),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        let divider = try XCTUnwrap(findDivider(in: host))
        let available = divider.bounds.height - divider.dividerThickness
        let original = divider.subviews[0].frame.height
        // Grab within the expanded hit area without jumping to its center.
        divider.mouseDown(with: event(.leftMouseDown, y: original + 3, in: divider, window: window))
        for height: CGFloat in [360, 200, -50, 900, 310] {
            divider.mouseDragged(with: event(.leftMouseDragged, y: height + 3, in: divider, window: window))
            try await settle(host)
            let limits = CalendarWeekSplitPolicy.limits(availableHeight: available)
            let expected = min(limits.upperBound, max(limits.lowerBound, height))
            XCTAssertEqual(probe.topHeight, expected, accuracy: 1,
                           "The visible SwiftUI pane must update while the mouse is still held")
            XCTAssertEqual(divider.subviews[0].frame.height, expected, accuracy: 0.01)
            XCTAssertEqual(probe.fraction, Double(expected / available), accuracy: 0.001)
        }
        divider.mouseUp(with: event(.leftMouseUp, y: 313, in: divider, window: window))
        try await settle(host)
        XCTAssertEqual(probe.topHeight, 310, accuracy: 1)
    }

    private func event(_ type: NSEvent.EventType, y: CGFloat,
                       in divider: NSView, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: divider.convert(CGPoint(x: 350, y: y), to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    private func findDivider(in view: NSView) -> CalendarWeekDivider.SplitView? {
        (view as? CalendarWeekDivider.SplitView) ?? view.subviews.lazy.compactMap { self.findDivider(in: $0) }.first
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            host.window?.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(15))
        }
    }
}

@MainActor
private final class DividerProbe: ObservableObject {
    @Published var fraction = 0.6
    weak var topView: NSView?
    var topHeight: CGFloat { topView?.frame.height ?? 0 }
}

private struct DividerPaneProbe: NSViewRepresentable {
    let probe: DividerProbe
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        probe.topView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

private struct DividerHarness: View {
    @ObservedObject var probe: DividerProbe
    var body: some View {
        CalendarWeekSplitView(fraction: $probe.fraction) {
            DividerPaneProbe(probe: probe)
        } bottom: { Color.clear }
    }
}
