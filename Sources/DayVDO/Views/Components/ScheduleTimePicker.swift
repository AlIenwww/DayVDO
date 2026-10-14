import SwiftUI

/// A native time field editing wall-clock minutes, independent of the chosen
/// day and its daylight-saving transitions, just like DaySchedule itself.
struct ScheduleTimePicker: View {
    @Environment(\.locale) private var locale
    let title: String
    @Binding var minute: Int

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var clockLocale: Locale {
        var components = Locale.Components(locale: locale)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60)) },
            set: { date in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .datePickerStyle(.stepperField)
        .labelsHidden()
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .environment(\.locale, clockLocale)
        .fixedSize()
    }
}
