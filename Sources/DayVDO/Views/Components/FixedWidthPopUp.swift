import SwiftUI

struct FixedWidthPopUp<Option: Hashable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    let symbolName: (Option) -> String?
    let iconColor: (Option) -> NSColor?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.bezelStyle = .rounded
        button.alignment = .center
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.imagePosition = .imageLeading
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setAccessibilityLabel(label)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.setAccessibilityLabel(label)
        let appearance = button.effectiveAppearance.name
        let entries = options.map { MenuEntry(title: title($0), symbol: symbolName($0), color: iconColor($0)) }
        let titles = entries.map(\.title)
        let rebuild = button.itemTitles != titles
        if rebuild {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }

        if rebuild || context.coordinator.entries != entries || context.coordinator.appearance != appearance {
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            for (index, entry) in entries.enumerated() {
                guard let item = button.item(at: index) else { continue }
                if let name = entry.symbol, let color = entry.color {
                    let coloredConfiguration = configuration.applying(.init(hierarchicalColor: color))
                    let image = NSImage(systemSymbolName: name, accessibilityDescription: entry.title)
                    item.image = image?.withSymbolConfiguration(coloredConfiguration)
                    item.image?.isTemplate = false
                } else {
                    item.image = nil
                }
            }
            context.coordinator.entries = entries
            context.coordinator.appearance = appearance
        }
        if let index = options.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
            button.synchronizeTitleAndSelectedItem()
        }
    }

    struct MenuEntry: Equatable {
        let title: String
        let symbol: String?
        let color: NSColor?
    }

    final class Coordinator: NSObject {
        var parent: FixedWidthPopUp
        var entries: [MenuEntry] = []
        var appearance: NSAppearance.Name?

        init(_ parent: FixedWidthPopUp) {
            self.parent = parent
        }

        @MainActor
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard parent.options.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = parent.options[sender.indexOfSelectedItem]
        }
    }
}

