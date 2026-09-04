import SwiftUI
import AppKit

struct TodoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @State private var draft: TodoItem
    @State private var hasDueDate: Bool
    @State private var isShowingDatePicker = false
    @FocusState private var titleIsFocused: Bool

    let isEditing: Bool
    let onSave: (TodoItem) -> Bool

    init(item: TodoItem, isEditing: Bool, onSave: @escaping (TodoItem) -> Bool) {
        _draft = State(initialValue: item)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(editorTitle)
                        .font(.title2.weight(.semibold))
                    Text(L10n.string("记录任务，并选择它应当完成的日期。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(L10n.string("待办名称"), text: $draft.title, prompt: Text(L10n.string("添加待办事项")))
                        .font(.title2.weight(.medium))
                        .textFieldStyle(.plain)
                        .focused($titleIsFocused)

                    TextField(L10n.string("备注"), text: $draft.notes, prompt: Text(L10n.string("添加备注")), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                }
                .padding(20)

                if showsProjectPicker {
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("所属项目"))
                        Spacer()
                        Menu {
                            Button {
                                draft.projectID = nil
                                draft.projectSortOrder = nil
                            } label: {
                                Label(
                                    L10n.string("无归类"),
                                    systemImage: draft.projectID == nil ? "checkmark" : "tray"
                                )
                            }
                            Divider()
                            ForEach(store.sortedProjects) { project in
                                Button {
                                    if draft.projectID != project.id {
                                        draft.projectID = project.id
                                        draft.projectSortOrder = nil
                                        if draft.tagID == nil {
                                            draft.tagID = project.tagID
                                        }
                                    }
                                } label: {
                                    Label(
                                        project.title,
                                        systemImage: draft.projectID == project.id ? "checkmark" : "folder"
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedProjectTitle)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: 190, alignment: .trailing)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(L10n.string("所属项目"))
                            .accessibilityValue(selectedProjectTitle)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                }

                Divider()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("标签"))
                        Spacer()
                        TaskTagPicker(selection: $draft.tagID)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 10) {
                        Image(systemName: "flag")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("重要度"))
                        Spacer()
                        FixedWidthPopUp(
                            label: L10n.string("重要度"),
                            selection: $draft.priority,
                            options: TodoItem.Priority.allCases,
                            title: { L10n.string($0.title) },
                            symbolName: { $0 == .none ? nil : $0.symbolName },
                            iconColor: { $0 == .none ? nil : $0.displayColor }
                        )
                        .frame(width: optionWidth, height: 26)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 10) {
                        Image(systemName: "bolt")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("紧急度"))
                        Spacer()
                        FixedWidthPopUp(
                            label: L10n.string("紧急度"),
                            selection: $draft.urgency,
                            options: TodoItem.Urgency.allCases,
                            title: { L10n.string($0.title) },
                            symbolName: { $0 == .none ? nil : $0.symbolName },
                            iconColor: { $0 == .none ? nil : $0.displayColor }
                        )
                        .frame(width: optionWidth, height: 26)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(L10n.string("日期"))
                        Spacer()
                        Toggle(L10n.string("设置日期"), isOn: $hasDueDate)
                            .labelsHidden()

                        if hasDueDate {
                            Button {
                                isShowingDatePicker.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(
                                        (draft.dueDate ?? .now).formatted(
                                            .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
                                        )
                                    )
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $isShowingDatePicker, arrowEdge: .bottom) {
                                BorderlessCalendarPicker(
                                    selection: Binding(
                                        get: { draft.dueDate ?? .now },
                                        set: { draft.dueDate = $0 }
                                    ),
                                    startsOnMonday: store.settings.startWeekOnMonday
                                )
                                .fixedSize()
                                .padding(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.normalizedTitle.isEmpty || !store.canModify)
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await Task.yield()
            titleIsFocused = true
        }
        .onChange(of: hasDueDate) { _, enabled in
            draft.dueDate = enabled ? (draft.dueDate ?? .now) : nil
        }
    }

    private func save() {
        if !hasDueDate { draft.dueDate = nil }
        if onSave(draft) {
            dismiss()
        }
    }

    private var optionWidth: CGFloat {
        LocalizedControlSizing.popUpWidth(
            for: TodoItem.Priority.allCases.map { L10n.string($0.title) }
                + TodoItem.Urgency.allCases.map { L10n.string($0.title) }
        )
    }

    private var editorTitle: String {
        if draft.projectID != nil {
            return L10n.string(isEditing ? "编辑子任务" : "添加子任务")
        }
        return L10n.string(isEditing ? "编辑待办" : "添加待办")
    }

    private var showsProjectPicker: Bool {
        !store.projects.isEmpty || draft.projectID != nil
    }

    private var selectedProjectTitle: String {
        store.project(withID: draft.projectID)?.title ?? L10n.string("无归类")
    }
}

private struct FixedWidthPopUp<Option: Hashable>: NSViewRepresentable {
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
        let titles = options.map(title)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        for (index, option) in options.enumerated() {
            guard let item = button.item(at: index) else { continue }
            if let name = symbolName(option), let color = iconColor(option) {
                let colorConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: color)
                let coloredConfiguration = configuration.applying(colorConfiguration)
                let image = NSImage(systemSymbolName: name, accessibilityDescription: title(option))
                item.image = image?.withSymbolConfiguration(coloredConfiguration)
                item.image?.isTemplate = false
            } else {
                item.image = nil
            }
        }
        if let index = options.firstIndex(of: selection) {
            button.selectItem(at: index)
            button.synchronizeTitleAndSelectedItem()
        }
    }

    final class Coordinator: NSObject {
        var parent: FixedWidthPopUp

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

private extension TodoItem.Priority {
    var displayColor: NSColor {
        switch self {
        case .none: .secondaryLabelColor
        case .low: .systemGreen
        case .medium: .systemBlue
        case .high: .systemRed
        }
    }
}

private extension TodoItem.Urgency {
    var displayColor: NSColor {
        switch self {
        case .none: .secondaryLabelColor
        case .canWait: .systemGreen
        case .today: .systemBlue
        case .mustToday: .systemRed
        }
    }
}
