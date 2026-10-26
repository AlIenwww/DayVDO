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
        view.delete = delete; view.clear = clear; view.enabled = enabled
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: WindowKeyMonitorView {
        var delete: () -> Void = {}
        var clear: () -> Void = {}

        override func handleKeyDown(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSTextField),
                  !(window.firstResponder is NSDatePicker) else { return false }
            switch event.keyCode {
            case 51, 117: delete(); return true
            case 53: clear(); return true
            default: return false
            }
        }
    }
}
