import AppKit
import SwiftUI

private struct PracticeDayKey: EnvironmentKey {
    static let defaultValue: LocalDay? = nil
}
extension EnvironmentValues {
    var practiceDay: LocalDay? {
        get { self[PracticeDayKey.self] }
        set { self[PracticeDayKey.self] = newValue }
    }
}

struct AppRootView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var guide: OnboardingSession

    var body: some View {
        Group {
            if isPracticing, let practice = guide.practice {
                ContentView(practiceGuide: guide)
                    .environmentObject(practice)
                    .environment(\.practiceDay, guide.progress.day)
                    .id(ObjectIdentifier(practice))
            } else {
                ContentView(initialDestination: navigation.currentDestination,
                            commandsEnabled: !guide.isPresented)
                    .sheet(isPresented: showingIntroduction) {
                        GuideIntroduction(guide: guide)
                    }
                    .environmentObject(store)
            }
        }
        .environmentObject(navigation)
        .onAppear { guide.presentAutomaticallyIfNeeded() }
        .onChange(of: store.isInitialLoading) { _, _ in guide.presentAutomaticallyIfNeeded() }
    }

    private var isPracticing: Bool {
        guide.isPresented && !guide.needsReset && guide.progress.step.rawValue >= GuideStep.create.rawValue
    }

    private var showingIntroduction: Binding<Bool> {
        Binding(get: { guide.isPresented && !isPracticing }, set: { visible in
            if !visible && guide.isPresented && !isPracticing { _ = guide.close() }
        })
    }
}

private struct GuideIntroduction: View {
    @EnvironmentObject private var store: TodoStore
    @ObservedObject var guide: OnboardingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.string(guide.progress.step.title), systemImage: "book.closed")
                .font(.title2.bold())
            GuideSaveMessage(guide: guide)
            if guide.needsReset {
                HStack {
                    Button(L10n.string("退出练习"), role: .cancel) { _ = guide.close() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(L10n.string("重新开始")) { guide.restart() }
                }
            } else {
                if guide.progress.step == .preferences {
                    Label(L10n.string("新手教程仍在开发中"), systemImage: "hammer")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                    Text(L10n.string("先选择语言和外观，之后也可以在设置中修改。"))
                        .foregroundStyle(.secondary)
                    Form { AppearancePreferencesView() }
                        .formStyle(.grouped)
                        .pickerStyle(.menu)
                        .frame(height: 130)
                        .disabled(!store.canModify)
                } else {
                    Text(L10n.string("DayVDO 帮你规划每天要做的事。点击「开始练习」，试试基本操作。"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack {
                    if guide.progress.step == .concepts {
                        Button(L10n.string("上一步")) { guide.back() }
                    }
                    GuideStepNumber(step: guide.progress.step)
                    Spacer()
                    Button(L10n.string("暂时跳过"), role: .cancel) { _ = guide.close(skipping: true) }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.string(guide.progress.step == .concepts ? "开始练习" : "下一步")) {
                        guide.advance()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .interactiveDismissDisabled()
    }
}

struct GuidePracticeMenu: View {
    @ObservedObject var guide: OnboardingSession
    @State private var confirmsRestart = false

    var body: some View {
        Menu {
            Text(L10n.string("练习内容不会加入正式数据。"))
            Button(L10n.string("退出练习")) { _ = guide.close() }
            Button(L10n.string("重新开始")) { confirmsRestart = true }
        } label: {
            Label(L10n.string("新手指引"), systemImage: "book.closed")
        }
        .help(L10n.string("新手指引"))
        .confirmationDialog(L10n.string("重新开始练习？"), isPresented: $confirmsRestart) {
            Button(L10n.string("重新开始"), role: .destructive) { guide.restart() }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("将清除练习示例和进度，正式数据不受影响。"))
        }
    }
}

struct GuidePracticeBar: View {
    @ObservedObject var guide: OnboardingSession
    let isShowingToday: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                instructions.frame(minWidth: 250)
                actions.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                instructions
                actions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle().fill(.bar)
            Rectangle().fill(Color.accentColor.opacity(0.09))
        }
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("新手指引"))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text(L10n.string(guide.progress.step.title))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                } icon: {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
                GuideStepNumber(step: guide.progress.step)
            }
            GuideSaveMessage(guide: guide)
            if guide.progress.step == .discover {
                Text(L10n.string("可以点击左侧边栏的「日历」或「总待办」看看其他页面。"))
                Text(L10n.string("点击「开始使用 DayVDO」结束练习。"))
            } else if guide.canAdvance {
                Label(L10n.string("已完成。点击「下一步」继续。"), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else if !isShowingToday {
                Text(L10n.string("点击左侧边栏的「今日安排」，回到练习页面。"))
            } else {
                Text(instruction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(L10n.string("上一步")) { guide.back() }
            Button(L10n.string(guide.progress.step == .discover ? "开始使用 DayVDO" : "下一步")) {
                if guide.progress.step == .discover { _ = guide.finish() }
                else { guide.advance() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!guide.canAdvance)
        }
    }

    private var instruction: String {
        switch guide.progress.step {
        case .create: L10n.string("点击窗口右上角的「＋」，修改示例名称，再点击「保存」。")
        case .schedule: L10n.string("将右侧的待办拖入时间线，为它安排一段时间。")
        case .adjust:
            if guide.targetSchedule == nil { L10n.string("将右侧的待办拖入时间线，为它安排一段时间。") }
            else if !guide.progress.moved { L10n.string("拖动时间线上的安排块，把它移到另一个时间。") }
            else { L10n.string("拖动安排块的上边缘或下边缘，调整时长。") }
        case .complete: L10n.string("在右侧列表中，点击待办名称左边的圆形状态按钮，将它标记为完成。")
        default: ""
        }
    }
}

private struct GuideStepNumber: View {
    let title: String

    init(step: GuideStep) {
        title = L10n.format("第 %lld / %lld 步", step.rawValue + 1, GuideStep.allCases.count)
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct GuideSaveMessage: View {
    @ObservedObject var guide: OnboardingSession

    var body: some View {
        if let error = guide.error {
            HStack {
                Label(error, systemImage: "exclamationmark.triangle")
                Spacer(minLength: 4)
                if !guide.needsReset {
                    Button(L10n.string("重试")) { _ = guide.persist() }
                }
            }
            .font(.callout)
        }
    }
}
