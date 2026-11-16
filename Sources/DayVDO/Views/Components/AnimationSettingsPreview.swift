import SwiftUI

struct AnimationSettingsPreview: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedEffect = AppAnimationEffect.completion
    @State private var previewID = 0

    private var enabled: Bool { store.settings.animates(selectedEffect) }
    private var playing: Bool { enabled && !reduceMotion && scenePhase == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("动画效果"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            AnimationIllustrationPlayer(effect: selectedEffect, playing: playing, showStill: !enabled || reduceMotion,
                tint: store.settings.themeColor?.color ?? .accentColor)
                .id(previewID)
            if reduceMotion {
                Text(L10n.string("系统已开启减少动态效果。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(AppAnimationEffect.allCases) { effect in
                    if effect != AppAnimationEffect.allCases.first {
                        Divider()
                    }
                    effectRow(effect)
                }
            }
        }
    }

    private func effectRow(_ effect: AppAnimationEffect) -> some View {
        let selected = selectedEffect == effect
        return HStack(spacing: 12) {
            Button {
                select(effect)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "play.circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(L10n.string(effect.title))
                        .fontWeight(selected ? .semibold : .regular)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(L10n.string("选择一项查看演示。"))
            Toggle(L10n.string(effect.title), isOn: Binding(
                get: { store.settings.animates(effect) },
                set: { value in
                    select(effect)
                    if value { store.settings.disabledAnimations.remove(effect) }
                    else { store.settings.disabledAnimations.insert(effect) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(selected ? Color.primary.opacity(0.08) : .clear)
    }

    private func select(_ effect: AppAnimationEffect) {
        selectedEffect = effect
        previewID += 1
    }
}

/// Only this small canvas ticks; settings controls and the store do not update per frame.
private struct AnimationIllustrationPlayer: View {
    let effect: AppAnimationEffect
    let playing: Bool
    let showStill: Bool
    let tint: Color
    @State private var origin = Date.now
    @State private var elapsed: TimeInterval = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { timeline in
            SettingsIllustration(scene: .animation(effect),
                progress: showStill ? 1 : AnimationPreviewTiming.progress(
                    elapsed: elapsed + (playing ? timeline.date.timeIntervalSince(origin) : 0)),
                tint: tint)
        }
        .onChange(of: playing) { _, value in
            if value { origin = .now }
            else { elapsed += Date.now.timeIntervalSince(origin) }
        }
    }
}

enum AnimationPreviewTiming {
    /// Hold the before and after states, then reverse smoothly without a loop-boundary jump.
    static func progress(elapsed: TimeInterval) -> CGFloat {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: 4.2)
        switch phase {
        case ..<0.2: return 0
        case ..<1.0: return smooth((phase - 0.2) / 0.8)
        case ..<3.2: return 1
        case ..<4.0: return 1 - smooth((phase - 3.2) / 0.8)
        default: return 0
        }
    }

    private static func smooth(_ value: Double) -> CGFloat { value * value * (3 - 2 * value) }
}
