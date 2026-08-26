import SwiftUI
import AppKit

/// AppKit's native graphical calendar without the exterior keyboard focus ring.
/// The selected day remains highlighted, so focus and selection are still visible.
struct BorderlessCalendarPicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerMode = .single
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = selection
        picker.isBordered = false
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.cell?.focusRingType = .none
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        if !Calendar.current.isDate(picker.dateValue, inSameDayAs: selection) {
            picker.dateValue = selection
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}
