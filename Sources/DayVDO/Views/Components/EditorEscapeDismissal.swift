import AppKit
import SwiftUI

/// Text fields can consume Escape before SwiftUI's cancel shortcut receives it.
/// Restrict cancellation to this editor's window; nested popovers and alert
/// sheets receive Escape themselves without also closing their parent editor.
private struct EditorEscapeDismissal: NSViewRepresentable {
    var enabled: Bool
    var cancel: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.enabled = enabled
        view.cancel = cancel
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var enabled = true
        var cancel: () -> Void = {}
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, event.keyCode == 53,
                      let window = self.window, event.window === window,
                      window.attachedSheet == nil else { return event }
                DispatchQueue.main.async { [weak self] in self?.cancel() }
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
    func editorEscapeDismissal(enabled: Bool = true, cancel: @escaping () -> Void) -> some View {
        background(EditorEscapeDismissal(enabled: enabled, cancel: cancel))
    }
}
