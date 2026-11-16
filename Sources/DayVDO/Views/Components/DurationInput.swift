import SwiftUI

/// Empty fields clear the estimate. The editor also keeps its unsaved draft in sync while typing.
struct DurationInput: View {
    var minutes: Int?
    var unit: EstimatedDurationUnit
    var updatesDraft = false
    var onValidityChange: (Bool) -> Void = { _ in }
    var onCommit: (Int?) -> Void
    @State private var input = EstimatedDurationUnit.Input()
    @State private var invalid = false
    @State private var hasUncommittedInput = false
    private enum Field: Hashable { case hours, minutes }
    @FocusState private var focused: Field?

    var body: some View {
        HStack(spacing: 4) {
            if unit != .minutes {
                TextField("0", text: field(\.hours))
                    .frame(width: unit == .mixed ? 60 : 90)
                    .accessibilityLabel(L10n.string("小时"))
                    .focused($focused, equals: .hours)
                Text(L10n.string("小时"))
            }
            if unit != .hours {
                TextField("0", text: field(\.minutes))
                    .frame(width: unit == .mixed ? 60 : 90)
                    .accessibilityLabel(L10n.string("分钟"))
                    .focused($focused, equals: .minutes)
                Text(L10n.string("分钟"))
            }
            if minutes != nil || !input.hours.isEmpty || !input.minutes.isEmpty {
                Button {
                    reload(nil)
                    onCommit(nil)
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help(L10n.string("清除预计时长"))
            }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .onSubmit { commit() }
        .onChange(of: focused) { _, value in
            if value == nil { commit() }
        }
        .onAppear { reload(minutes) }
        .onChange(of: unit) { _, _ in reload(minutes) }
        .onChange(of: minutes) { _, value in if focused == nil { reload(value) } }
        .overlay(alignment: .bottom) {
            if invalid {
                Text(L10n.string("请输入有效时长"))
                    .font(.caption2).foregroundStyle(.red).offset(y: 15)
            }
        }
    }

    private func field(_ keyPath: WritableKeyPath<EstimatedDurationUnit.Input, String>) -> Binding<String> {
        Binding(get: { input[keyPath: keyPath] }, set: { value in
            guard input[keyPath: keyPath] != value else { return }
            input[keyPath: keyPath] = value
            hasUncommittedInput = true
            if updatesDraft { commit(normalize: false) }
        })
    }

    private func reload(_ minutes: Int?) {
        input = .init(minutes: minutes, unit: unit, locale: L10n.locale)
        hasUncommittedInput = false
        invalid = false
        onValidityChange(true)
    }

    private func commit(normalize: Bool = true) {
        guard hasUncommittedInput else { return }
        let value: Int?
        switch input.value(in: unit, locale: L10n.locale) {
        case .empty: value = nil
        case let .minutes(total): value = total
        case .invalid:
            invalid = true
            onValidityChange(false)
            return
        }
        invalid = false
        onValidityChange(true)
        if value != minutes { onCommit(value) }
        if normalize { reload(value) }
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
