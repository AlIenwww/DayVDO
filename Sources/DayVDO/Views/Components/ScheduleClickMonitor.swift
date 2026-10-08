import AppKit
import SwiftUI

/// Use the native click count for the entire block, so text, background and
/// resize overlays share one click route without competing tap recognizers.
struct ScheduleClickMonitor: NSViewRepresentable {
    var acceptsClick: (CGPoint) -> Bool
    var click: (CGPoint, Int) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.acceptsClick = acceptsClick
        view.click = click
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var acceptsClick: (CGPoint) -> Bool = { _ in true }
        var click: (CGPoint, Int) -> Void = { _, _ in }
        private var monitor: Any?
        private var press: CGPoint?
        private var dragged = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                switch event.type {
                case .leftMouseDown:
                    self.press = self.visibleRect.contains(point) && self.acceptsClick(point) ? point : nil
                    self.dragged = false
                case .leftMouseDragged:
                    if let press = self.press, hypot(point.x - press.x, point.y - press.y) >= 4 {
                        self.dragged = true
                    }
                case .leftMouseUp:
                    defer { self.press = nil; self.dragged = false }
                    if let press = self.press, !self.dragged,
                       hypot(point.x - press.x, point.y - press.y) < 4,
                       self.visibleRect.contains(point), self.acceptsClick(point) {
                        let count = event.clickCount
                        DispatchQueue.main.async { [weak self] in self?.click(point, count) }
                    }
                default: break
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            press = nil
            dragged = false
        }
    }
}
