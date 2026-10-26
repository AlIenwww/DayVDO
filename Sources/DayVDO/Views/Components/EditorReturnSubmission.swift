import AppKit
import SwiftUI

/// Native date/time field editors can consume Return before SwiftUI receives
/// onSubmit. Commit the active field first, then submit the complete draft.
private struct EditorReturnSubmission: NSViewRepresentable {
    var enabled: Bool
    var submit: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.submit = submit; view.enabled = enabled }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: WindowKeyMonitorView {
        var submit: () -> Void = {}

        override func handleKeyDown(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard event.keyCode == 36 || event.keyCode == 76,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
            // Return must confirm an active input method before saving.
            if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
            guard window.makeFirstResponder(nil) else { return false }
            performDeferred { [weak self] in self?.submit() }
            return true
        }
    }
}

extension View {
    func editorReturnSubmission(enabled: Bool = true, submit: @escaping () -> Void) -> some View {
        background(EditorReturnSubmission(enabled: enabled, submit: submit))
    }
}

extension Notification.Name {
    static let scheduleEditorSubmit = Notification.Name("DayVDO.ScheduleEditorSubmit")
}
