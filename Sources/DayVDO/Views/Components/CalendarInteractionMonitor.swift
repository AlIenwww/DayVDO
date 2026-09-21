import AppKit
import SwiftUI

/// Escape and window deactivation cancel a drag even when the grid lacks keyboard focus.
struct CalendarInteractionMonitor: NSViewRepresentable {
    var active: Bool
    var cancel: () -> Void
    var release: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.active = active; view.cancel = cancel; view.release = release
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var active = false
        var cancel: () -> Void = {}
        var release: () -> Void = {}
        private var eventMonitor: Any?
        private var observer: NSObjectProtocol?
        private var activationObserver: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown, event.keyCode == 53, event.window === self.window, self.active {
                    self.cancel(); return nil
                }
                if event.type == .leftMouseUp {
                    DispatchQueue.main.async { [weak self] in self?.release() }
                }
                return event
            }
            activationObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if NSEvent.pressedMouseButtons & 1 == 0 { self?.release() }
                    }
                }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if self?.active == true { self?.cancel() } }
                }
        }
        func stop() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
            eventMonitor = nil; observer = nil; activationObserver = nil
        }
    }
}
