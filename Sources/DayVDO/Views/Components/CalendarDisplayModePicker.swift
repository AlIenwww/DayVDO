import SwiftUI

struct CalendarDisplayModePicker: View {
    @Binding var selection: String

    private let modes: [CalendarDisplayMode] = [.week, .month]

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                picker.buttonSizing(.flexible)
            } else {
                picker
            }
        }
        .frame(minWidth: LocalizedControlSizing.segmentedWidth(for: modes.map { title(for: $0) }))
    }

    private var picker: some View {
        Picker(L10n.string("日历视图"), selection: $selection) {
            ForEach(modes, id: \.rawValue) { mode in
                Text(title(for: mode)).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
    }

    private func title(for mode: CalendarDisplayMode) -> String {
        L10n.string(mode == .week ? "周" : "月")
    }
}
