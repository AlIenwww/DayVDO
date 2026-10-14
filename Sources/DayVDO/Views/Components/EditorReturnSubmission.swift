import AppKit
import SwiftUI

/// Native date/time field editors can consume Return before SwiftUI receives
/// onSubmit. Commit the active field first, then submit the complete draft.
private struct EditorReturnSubmission: NSViewRepresentable {
    var enabled: Bool
    var submit: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.enabled = enabled; view.submit = submit }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var submit: () -> Void = {}
        var enabled = true
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, let window = self.window, event.window === window,
                      window.attachedSheet == nil, event.keyCode == 36 || event.keyCode == 76,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                // Return must confirm an active input method before saving.
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                guard window.makeFirstResponder(nil) else { return event }
                DispatchQueue.main.async { [weak self] in self?.submit() }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
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
