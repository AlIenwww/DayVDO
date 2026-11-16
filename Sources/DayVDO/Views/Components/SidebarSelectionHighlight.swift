import AppKit
import SwiftUI

/// Keeps selection and keyboard navigation in the native list while the app
/// supplies the selection fill for custom themes.
struct SidebarSelectionHighlight: NSViewRepresentable {
    let usesTheme: Bool

    func makeNSView(context: Context) -> SelectionView { SelectionView() }

    func updateNSView(_ view: SelectionView, context: Context) {
        view.usesTheme = usesTheme
        view.scheduleUpdate()
    }

    static func dismantleNSView(_ view: SelectionView, coordinator: ()) {
        view.usesTheme = false
        view.scheduleUpdate()
    }

    final class SelectionView: NSView {
        var usesTheme = false
        private weak var table: NSTableView?
        private var originalStyle: NSTableView.SelectionHighlightStyle?
        private var updateQueued = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdate()
        }

        func scheduleUpdate() {
            guard !updateQueued else { return }
            updateQueued = true
            // AppKit reloads the rows when this property changes. Wait until
            // SwiftUI finishes attaching the sidebar's native view hierarchy.
            DispatchQueue.main.async {
                self.updateQueued = false
                self.updateHighlight()
            }
        }

        private func updateHighlight() {
            guard usesTheme, window != nil, let list = sidebarTable() else {
                restoreHighlight()
                return
            }
            if table !== list {
                restoreHighlight()
                table = list
                originalStyle = list.selectionHighlightStyle
            }
            if list.selectionHighlightStyle != .none {
                list.selectionHighlightStyle = .none
            }
        }

        private func sidebarTable() -> NSTableView? {
            var candidate = superview
            while let view = candidate, !(view is NSSplitView), view !== window?.contentView {
                if let table = sourceList(in: view) { return table }
                candidate = view.superview
            }
            return nil
        }

        private func sourceList(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.effectiveStyle == .sourceList {
                return table
            }
            for child in view.subviews {
                if let table = sourceList(in: child) { return table }
            }
            return nil
        }

        private func restoreHighlight() {
            if let originalStyle { table?.selectionHighlightStyle = originalStyle }
            table = nil
            originalStyle = nil
        }
    }
}
