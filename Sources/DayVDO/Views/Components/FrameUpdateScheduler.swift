import AppKit
import QuartzCore
import SwiftUI

/// Coalesces preview work to the owning display, not a fixed polling interval.
/// Release explicitly flushes the latest pointer before committing to storage.
@MainActor
final class FrameUpdateScheduler: NSObject, ObservableObject {
    weak var view: NSView?
    private var link: CADisplayLink?
    private var pending: (() -> Void)?

    func submit(_ action: @escaping () -> Void) {
        pending = action
        guard let view, view.window != nil else { flush(); return }
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func tick(_ link: CADisplayLink) { flush() }
    func flush() {
        let action = pending
        cancel()
        action?()
    }
    func cancel() {
        link?.invalidate(); link = nil; pending = nil
    }
}

struct FrameUpdateAnchor: NSViewRepresentable {
    let scheduler: FrameUpdateScheduler
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor(); view.scheduler = scheduler; scheduler.view = view
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) { }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.scheduler?.cancel(); view.scheduler?.view = nil
    }
    final class Anchor: NSView {
        weak var scheduler: FrameUpdateScheduler?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { scheduler?.cancel() }
        }
    }
}
