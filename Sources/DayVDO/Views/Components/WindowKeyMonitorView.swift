import AppKit

/// Shared lifecycle for window-scoped key handling. Disabled and detached
/// views do not add work to the application's native event dispatch.
class WindowKeyMonitorView: NSView {
    var enabled = false {
        didSet { updateMonitoring() }
    }
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        updateMonitoring()
    }

    func handleKeyDown(_ event: NSEvent, in window: NSWindow) -> Bool { false }

    func performDeferred(_ action: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard self?.window != nil else { return }
            action()
        }
    }

    private func updateMonitoring() {
        guard enabled, window != nil else { stop(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.enabled, let window = self.window,
                  event.window === window, window.attachedSheet == nil else { return event }
            return self.handleKeyDown(event, in: window) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
