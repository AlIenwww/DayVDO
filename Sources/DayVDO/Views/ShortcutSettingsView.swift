import SwiftUI
import AppKit

struct ShortcutSettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var editing: AppCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AppCommand.allCases) { command in
                let title = L10n.string(command.title)
                let shortcut = store.settings.shortcut(for: command).display
                if command != AppCommand.allCases.first { Divider() }
                LabeledContent(title) {
                    Button(shortcut) { editing = command }
                        .monospacedDigit()
                        .frame(minWidth: 78, alignment: .trailing)
                        .accessibilityLabel(title)
                        .accessibilityValue(shortcut)
                }
            }
            Divider()
            Button(L10n.string("恢复默认快捷键")) { store.settings.shortcutOverrides = [:] }
                .disabled(store.settings.shortcutOverrides.isEmpty)
                .padding(.top, 12)
        }
        .labeledContentStyle(SettingsRowStyle())
        .disabled(!store.canModify)
        .sheet(item: $editing) { command in
            ShortcutEditor(command: command)
        }
    }
}

private struct ShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    let command: AppCommand
    @State private var candidate: CommandShortcut?
    @State private var unsupported = false

    private var conflict: AppCommand? {
        guard let candidate, candidate.isSupported else { return nil }
        return store.settings.shortcutConflict(candidate, excluding: command)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string(command.title)).font(.headline)
            Text(L10n.string("按下新的组合键，需包含 Command 或 Control。"))
                .foregroundStyle(.secondary)
            Text((candidate ?? store.settings.shortcut(for: command)).display)
                .font(.title2.monospaced())
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if unsupported {
                Text(L10n.string("这个组合键不可用。")).foregroundStyle(.red)
            } else if let conflict {
                Text(L10n.format("这个快捷键已分配给“%@”。", L10n.string(conflict.title)))
                    .foregroundStyle(.red)
            }

            HStack {
                Button(L10n.string("恢复默认")) { setCandidate(command.defaultShortcut) }
                Spacer()
                Button(L10n.string("取消"), role: .cancel) { dismiss() }
                Button(L10n.string("保存")) {
                    guard let candidate, store.canModify,
                          store.settings.assignShortcut(candidate, to: command) else { return }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidate == nil || unsupported || conflict != nil || !store.canModify)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background {
            ShortcutRecorder { shortcut in
                if let shortcut { setCandidate(shortcut) }
                else { dismiss() }
            }
        }
    }

    private func setCandidate(_ shortcut: CommandShortcut) {
        candidate = shortcut
        unsupported = !shortcut.isSupported
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let record: (CommandShortcut?) -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }
    func updateNSView(_ view: RecorderView, context: Context) {
        view.record = record
        view.enabled = true
    }
    static func dismantleNSView(_ view: RecorderView, coordinator: ()) { view.stop() }

    final class RecorderView: WindowKeyMonitorView {
        var record: (CommandShortcut?) -> Void = { _ in }

        override func handleKeyDown(_ event: NSEvent, in window: NSWindow) -> Bool {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if flags.isEmpty && event.keyCode == 53 {
                performDeferred { [weak self] in self?.record(nil) }
                return true
            }
            // Let the sheet's native buttons retain Return, Tab, and Space.
            if !flags.contains(.command) && !flags.contains(.control) { return false }
            let shortcut = CommandShortcut.capture(event) ?? CommandShortcut(key: "")
            performDeferred { [weak self] in self?.record(shortcut) }
            return true
        }
    }
}
