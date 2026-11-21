import SwiftUI

extension View {
    func sheetAllowingAppTermination<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().allowAppTerminationWhilePresented()
        }
    }

    func sheetAllowingAppTermination<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item).allowAppTerminationWhilePresented()
        }
    }

    @ViewBuilder
    private func allowAppTerminationWhilePresented() -> some View {
        if #available(macOS 15.4, *) {
            presentationPreventsAppTermination(false)
        } else {
            self
        }
    }

    @ViewBuilder
    func allowAppTerminationDuringDialog() -> some View {
        if #available(macOS 15.4, *) {
            dialogPreventsAppTermination(false)
        } else {
            self
        }
    }
}
