import SwiftUI

/// Empty fields mean no estimate. Values are committed as one edit, not per keystroke.
struct DurationInput: View {
    var minutes: Int?
    var updatesDraft = false
    var onValidityChange: (Bool) -> Void = { _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onCommit: (Int?) -> Void
    @State private var hours = ""
    @State private var remainder = ""
    @State private var invalid = false
    private enum Field: Hashable { case hours, minutes }
    @FocusState private var focused: Field?

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $hours)
                .frame(width: 42)
                .accessibilityLabel(L10n.string("小时"))
                .focused($focused, equals: .hours)
            Text(L10n.string("小时"))
            TextField("0", text: $remainder)
                .frame(width: 36)
                .accessibilityLabel(L10n.string("分钟"))
                .focused($focused, equals: .minutes)
            Text(L10n.string("分钟"))
            if minutes != nil || !hours.isEmpty || !remainder.isEmpty {
                Button {
                    hours = ""; remainder = ""; invalid = false; onValidityChange(true)
                    onCommit(nil)
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help(L10n.string("清除预计时长"))
            }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .onChange(of: hours) { _, _ in if updatesDraft { commit() } }
        .onChange(of: remainder) { _, _ in if updatesDraft { commit() } }
        .onSubmit(commit)
        .onChange(of: focused) { _, value in
            onEditingChanged(value != nil)
            if value == nil { commit() }
        }
        .onDisappear { if focused != nil { onEditingChanged(false) } }
        .onAppear(perform: reload)
        .onChange(of: minutes) { _, _ in if focused == nil { reload() } }
        .overlay(alignment: .bottom) {
            if invalid {
                Text(L10n.string("请输入有效时长"))
                    .font(.caption2).foregroundStyle(.red).offset(y: 15)
            }
        }
    }

    private func reload() {
        hours = minutes.map { String($0 / 60) } ?? ""
        remainder = minutes.map { String($0 % 60) } ?? ""
    }
    private func commit() {
        if hours.isEmpty && remainder.isEmpty { invalid = false; onValidityChange(true); onCommit(nil); return }
        guard let h = Int(hours.isEmpty ? "0" : hours),
              let m = Int(remainder.isEmpty ? "0" : remainder),
              (0...100_000).contains(h), (0...59).contains(m), h * 60 + m > 0 else {
            invalid = true; onValidityChange(false); return
        }
        invalid = false
        onValidityChange(true)
        onCommit(h * 60 + m)
    }
}

@MainActor
enum SchedulePresentation {
    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", (minute / 60) % 24, minute % 60)
    }
    static func time(_ schedule: DaySchedule) -> String {
        let end = schedule.endMinute == 1440 ? "24:00" : clock(schedule.endMinute)
        let suffix = schedule.endMinute > 1440 ? " " + L10n.string("次日") : ""
        return "\(clock(schedule.startMinute))–\(end)\(suffix)"
    }
    static func title(_ schedule: DaySchedule, store: TodoStore) -> String {
        switch schedule.content {
        case .todo(let id): store.items.first { $0.id == id }?.title ?? ""
        case .independent(let title, _): title
        }
    }
    static func notes(_ schedule: DaySchedule, store: TodoStore) -> String {
        switch schedule.content {
        case .todo(let id): store.items.first { $0.id == id }?.notes ?? ""
        case .independent(_, let notes): notes
        }
    }
}
