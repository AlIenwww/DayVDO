import AppKit
import SwiftUI

/// Keep the native toolbar, but omit its display-mode customization menu.
struct IconOnlyWindowToolbar: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarView { ToolbarView() }
    func updateNSView(_ view: ToolbarView, context: Context) { view.configureToolbar() }
    static func dismantleNSView(_ view: ToolbarView, coordinator: ()) { view.stopObserving() }

    final class ToolbarView: NSView {
        private var windowObservation: NSKeyValueObservation?
        private var modeObservation: NSKeyValueObservation?
        private weak var configuredToolbar: NSToolbar?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            // SwiftUI can install or replace a toolbar after the content view
            // attaches to its window, including when changing pages.
            windowObservation = window?.observe(\.toolbar, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.configureToolbar() }
            }
        }

        func configureToolbar() {
            guard let toolbar = window?.toolbar else { return }
            if configuredToolbar !== toolbar {
                configuredToolbar = toolbar
                modeObservation = toolbar.observe(\.displayMode, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.configureToolbar() }
                }
            }
            toolbar.allowsDisplayModeCustomization = false
            toolbar.allowsUserCustomization = false
            if toolbar.displayMode != .iconOnly { toolbar.displayMode = .iconOnly }
        }

        func stopObserving() {
            windowObservation = nil
            modeObservation = nil
            configuredToolbar = nil
        }
    }
}
