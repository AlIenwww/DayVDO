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
        view.cancel = cancel
        view.enabled = enabled
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: WindowKeyMonitorView {
        var cancel: () -> Void = {}

        override func handleKeyDown(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard event.keyCode == 53 else { return false }
            performDeferred { [weak self] in self?.cancel() }
            return true
        }
    }
}

extension View {
    func editorEscapeDismissal(enabled: Bool = true, cancel: @escaping () -> Void) -> some View {
        background(EditorEscapeDismissal(enabled: enabled, cancel: cancel))
    }
}
