import AppKit
import SwiftUI

/// Handle selection keys even when a native mouse click hasn't transferred
/// SwiftUI focus. Never intercept typing or keys in an editor's window.
struct TimelineSelectionKeyMonitor: NSViewRepresentable {
    var enabled: Bool
    var delete: () -> Void
    var clear: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.enabled = enabled; view.delete = delete; view.clear = clear
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var enabled = false
        var delete: () -> Void = {}
        var clear: () -> Void = {}
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, let window = self.window,
                      event.window === window, window.attachedSheet == nil,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      !(window.firstResponder is NSTextView),
                      !(window.firstResponder is NSTextField),
                      !(window.firstResponder is NSDatePicker) else { return event }
                switch event.keyCode {
                case 51, 117: self.delete(); return nil
                case 53: self.clear(); return nil
                default: return event
                }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
