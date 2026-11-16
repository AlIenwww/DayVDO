import SwiftUI

struct TaskAssignmentPicker: View {
    struct Option: Identifiable {
        let id: UUID
        let title: String
        let tag: TaskTag?
    }

    let title: String
    let selection: UUID?
    let options: [Option]
    let noneTitle: String
    let symbol: String
    let createTitle: String
    let select: (UUID?) -> Void
    let create: () -> Void
    @Binding var isPresented: Bool

    var body: some View {
        let selected = options.first { $0.id == selection }
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                if let tag = selected?.tag {
                    TaskTagDot(tag: tag)
                }
                Text(selected?.title ?? noneTitle).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: 190, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected?.title ?? noneTitle)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                row(noneTitle, icon: "minus", selected: selected == nil) { choose(nil) }
                if !options.isEmpty {
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(options) { option in
                                row(option.title, icon: symbol, tag: option.tag, selected: option.id == selection) {
                                    choose(option.id)
                                }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(options.count) * 31 - 3, 245))
                }
                Divider()
                row(createTitle, icon: "plus") {
                    isPresented = false
                    create()
                }
            }
            .padding(8)
            .frame(width: 250)
            .editorEscapeDismissal { isPresented = false }
        }
    }

    private func choose(_ id: UUID?) {
        select(id)
        isPresented = false
    }

    private func row(_ title: String, icon: String, tag: TaskTag? = nil, selected: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let tag {
                        TaskTagDot(tag: tag, size: 10)
                    } else {
                        Image(systemName: icon).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 16)
                .accessibilityHidden(true)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
