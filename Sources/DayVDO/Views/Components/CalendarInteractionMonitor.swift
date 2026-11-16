import AppKit
import SwiftUI

/// The viewport owns the mouse press even as its schedule moves to another day.
struct CalendarInteractionMonitor: NSViewRepresentable {
    var active: Bool
    var cancel: () -> Void
    var release: () -> Void
    var trackDrag: (CGPoint, CGPoint) -> Void
    var finishDrag: (CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.active = active; view.cancel = cancel; view.release = release
        view.trackDrag = trackDrag; view.finishDrag = finishDrag
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var active = false
        var cancel: () -> Void = {}
        var release: () -> Void = {}
        var trackDrag: (CGPoint, CGPoint) -> Void = { _, _ in }
        var finishDrag: (CGPoint) -> Void = { _ in }
        private var press: CGPoint?
        private var dragging = false
        private var eventMonitor: Any?
        private var observer: NSObjectProtocol?
        private var activationObserver: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                if event.window !== self.window {
                    if event.type == .leftMouseUp, self.press != nil {
                        self.press = nil; self.dragging = false
                        self.release()
                    }
                    return event
                }
                if event.type == .keyDown, event.keyCode == 53, self.active || self.dragging {
                    self.cancel(); return nil
                }
                let point = self.convert(event.locationInWindow, from: nil)
                switch event.type {
                case .leftMouseDown:
                    self.press = self.visibleRect.contains(point) ? point : nil
                    self.dragging = false
                case .leftMouseDragged:
                    if let start = self.press, self.dragging || hypot(point.x - start.x, point.y - start.y) >= 4 {
                        self.dragging = true
                        self.trackDrag(start, point)
                    }
                case .leftMouseUp:
                    if self.dragging { self.finishDrag(point) }
                    self.press = nil; self.dragging = false
                    DispatchQueue.main.async { [weak self] in self?.release() }
                default: break
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
            press = nil; dragging = false
        }
    }
}
