import SwiftUI

extension View {
    /// Keep page controls fixed while letting the system blend scrolling
    /// content behind them and the native window toolbar.
    @ViewBuilder
    func pageTopBar<Bar: View>(blendsNativeContent: Bool = false,
                              @ViewBuilder content: () -> Bar) -> some View {
        if blendsNativeContent {
            // The native viewport supplies a within-window material directly
            // above its scroll view; keep these SwiftUI controls transparent.
            safeAreaInset(edge: .top, spacing: 0, content: content)
        } else if #available(macOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                content().background(.bar)
            }
        }
    }
}
