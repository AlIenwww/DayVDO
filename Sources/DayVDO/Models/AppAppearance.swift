import AppKit

@MainActor
enum AppAppearance {
    static func apply(_ mode: AppearanceMode) {
        // Use one AppKit appearance for windows, SwiftUI content, and native
        // controls. Clearing a SwiftUI preferredColorScheme can leave the host
        // in its previous scheme while the toolbar returns to the system scheme.
        switch mode {
        case .automatic: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
