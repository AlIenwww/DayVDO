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
                    Text(L10n.string("先选择语言和外观，之后也可以在设置中修改。"))
                        .foregroundStyle(.secondary)
                    Form { AppearancePreferencesView() }
                        .formStyle(.grouped)
                        .frame(height: 130)
                        .disabled(!store.canModify)
                } else {
                    GuideConceptsView()
                    Text(L10n.string("接下来在独立练习中，记录一件事，为它安排时间，再标记完成。"))
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
    @EnvironmentObject private var store: TodoStore
    @ObservedObject var guide: OnboardingSession
    let editSchedule: (DaySchedule) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 20) {
                instructions.frame(minWidth: 300)
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
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(L10n.string(guide.progress.step.title), systemImage: "book.closed")
                    .font(.headline)
                GuideStepNumber(step: guide.progress.step)
            }
            GuideSaveMessage(guide: guide)
            if guide.progress.step == .discover {
                Text(L10n.string("项目将相关待办归在一起，标签帮助你用颜色分类。"))
                Text(L10n.string("日历支持周／月视图；总待办可搜索，并按项目、标签和状态筛选。"))
            } else {
                Text(L10n.string(instruction))
                if guide.canAdvance {
                    Label(L10n.string("已完成，可以继续。"), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(L10n.string("上一步")) { guide.back() }
            scheduleAction
            Button(L10n.string(guide.progress.step == .discover ? "开始使用 DayVDO" : "下一步")) {
                if guide.progress.step == .discover { _ = guide.finish() }
                else { guide.advance() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!guide.canAdvance)
        }
    }

    @ViewBuilder
    private var scheduleAction: some View {
        if guide.progress.step == .schedule, guide.targetSchedule == nil, let todo = guide.targetTodo {
            Button(L10n.string("安排时间")) {
                let duration = DayPlanningPolicy.defaultDuration(
                    estimated: todo.estimatedMinutes, scheduled: store.scheduledMinutes(for: todo.id),
                    fallback: store.settings.defaultScheduleMinutes
                )
                editSchedule(DaySchedule(startDay: guide.progress.day, startMinute: 540,
                    durationMinutes: duration, content: .todo(todo.id)))
            }
        } else if guide.progress.step == .adjust, let schedule = guide.targetSchedule {
            Button(L10n.string("编辑安排")) { editSchedule(schedule) }
        }
    }

    private var instruction: String {
        switch guide.progress.step {
        case .create: "点击“新建待办”，修改示例名称并保存。"
        case .schedule: "将右侧的待办拖入时间线，或点击“安排时间”按钮。"
        case .adjust:
            if !guide.progress.moved { "拖动安排到另一个时间；也可以双击安排，编辑起止时间。" }
            else if !guide.progress.resized { "现在拖动安排的边缘调整时长，或双击后修改结束时间。" }
            else { "安排的位置和时长都已调整。" }
        case .complete: "点击待办或安排上的状态图标，将待办标记为已完成。"
        default: "练习内容不会加入正式数据。"
        }
    }
}

private struct GuideStepNumber: View {
    let step: GuideStep

    var body: some View {
        Text(L10n.format("第 %lld / %lld 步", step.rawValue + 1, GuideStep.allCases.count))
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
