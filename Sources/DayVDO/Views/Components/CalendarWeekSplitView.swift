import AppKit
import SwiftUI

enum CalendarWeekSplitPolicy {
    static let defaultFraction = 0.6
    static func limits(availableHeight: CGFloat) -> ClosedRange<CGFloat> {
        let height = max(0, availableHeight)
        if height < 220 {
            let compressed = height * 120 / 220
            return compressed...compressed
        }
        return 120...(height - 100)
    }
    static func topHeight(fraction: Double, availableHeight: CGFloat) -> CGFloat {
        let range = limits(availableHeight: availableHeight)
        let value = fraction.isFinite ? min(1, max(0, fraction)) : defaultFraction
        return min(range.upperBound, max(range.lowerBound, availableHeight * value))
    }
}

/// Both panes stay in the page's SwiftUI hierarchy so their scroll content
/// participates in the native toolbar's scroll edge effect.
struct CalendarWeekSplitView<Top: View, Bottom: View>: View {
    @Binding var fraction: Double
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.height - 1)
            let topHeight = CalendarWeekSplitPolicy.topHeight(fraction: fraction, availableHeight: available)
            VStack(spacing: 0) {
                top().frame(height: topHeight)
                Divider().frame(height: 1)
                bottom().frame(height: max(0, available - topHeight)).clipped()
            }
            .overlay { CalendarWeekDivider(fraction: $fraction) }
        }
    }
}

/// Preserve AppKit's divider tracking without separate NSHostingViews that
/// isolate each pane from the window's safe-area and scroll-edge preferences.
struct CalendarWeekDivider: NSViewRepresentable {
    @Binding var fraction: Double

    func makeNSView(context: Context) -> SplitView {
        let split = SplitView()
        split.addSubview(NSView())
        split.addSubview(NSView())
        configure(split)
        return split
    }
    func updateNSView(_ split: SplitView, context: Context) { configure(split) }
    private func configure(_ split: SplitView) {
        split.preferredFraction = fraction
        split.onUserResize = { fraction = $0 }
        split.setAccessibilityLabel(L10n.string("调整待办与时间线分区"))
        split.applyFraction()
    }

    final class SplitView: NSSplitView, NSSplitViewDelegate {
        var preferredFraction = CalendarWeekSplitPolicy.defaultFraction
        var onUserResize: (Double) -> Void = { _ in }
        private var draggingDivider = false
        private var layingOut = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            isVertical = false; dividerStyle = .thin; delegate = self
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard bounds.contains(local), subviews.count == 2,
                  abs(local.y - subviews[0].frame.maxY) <= 5 else { return nil }
            return self
        }
        override func drawDivider(in rect: NSRect) { }
        override var isFlipped: Bool { true }
        override func resizeSubviews(withOldSize oldSize: NSSize) { applyFraction() }
        func applyFraction() {
            guard !draggingDivider, !layingOut, subviews.count == 2 else { return }
            layingOut = true
            let available = max(0, bounds.height - dividerThickness)
            let height = CalendarWeekSplitPolicy.topHeight(fraction: preferredFraction, availableHeight: available)
            subviews[0].frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            subviews[1].frame = CGRect(x: 0, y: height + dividerThickness,
                width: bounds.width, height: max(0, available - height))
            layingOut = false
        }
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard subviews.count == 2, abs(point.y - subviews[0].frame.maxY) <= 5 else {
                super.mouseDown(with: event); return
            }
            draggingDivider = true
            super.mouseDown(with: event)
            draggingDivider = false
            let available = bounds.height - dividerThickness
            if available >= 220 { onUserResize(subviews[0].frame.height / available) }
        }
        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
        nonisolated func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView,
                       forDoubleClickOnDividerAt dividerIndex: Int) -> Bool { false }
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            CalendarWeekSplitPolicy.limits(availableHeight: bounds.height - dividerThickness).lowerBound
        }
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            CalendarWeekSplitPolicy.limits(availableHeight: bounds.height - dividerThickness).upperBound
        }
        func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                       forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
            drawnRect.insetBy(dx: 0, dy: -4)
        }
    }
}
