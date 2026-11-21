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
    @State private var formalBrowsing = WorkspaceBrowsingState()
    @ObservedObject var store: TodoStore
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var guide: OnboardingSession

    var body: some View {
        Group {
            if isPracticing, let practice = guide.practice {
                ContentView(initialDestination: guide.progress.step.destination, practiceGuide: guide)
                    .environment(\.lessonSession, guide)
                    .environmentObject(practice)
                    .environment(\.practiceDay, guide.progress.day)
                    .id(ObjectIdentifier(practice))
            } else {
                ContentView(initialDestination: navigation.currentDestination,
                            commandsEnabled: !guide.isPresented, browsingState: formalBrowsing)
                    .sheetAllowingAppTermination(isPresented: showingIntroduction) {
                        GuideIntroduction(guide: guide, store: store)
                    }
                    .overlay {
                        if navigation.isFindingTutorials {
                            TutorialDiscoveryHint(navigation: navigation)
                        }
                    }
                    .environmentObject(store)
            }
        }
        .environmentObject(navigation)
        .environment(\.guideLocations, isPracticing || navigation.isFindingTutorials ? guide.locations : nil)
        .onAppear { guide.presentAutomaticallyIfNeeded() }
        .onChange(of: store.isInitialLoading) { _, _ in guide.presentAutomaticallyIfNeeded() }
    }

    private var isPracticing: Bool {
        guide.isPresented && !guide.needsReset && guide.practice != nil
    }

    private var showingIntroduction: Binding<Bool> {
        Binding(get: { guide.isPresented && !isPracticing }, set: { visible in
            if !visible && guide.isPresented && !isPracticing { _ = guide.close() }
        })
    }
}

extension EnvironmentValues {
    @Entry var lessonSession: OnboardingSession? = nil
    @Entry var guideLocations: GuideLocations? = nil
}

private struct GuideIntroduction: View {
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject var guide: OnboardingSession
    @ObservedObject var store: TodoStore

    private static let icon = [Bundle.main, Bundle.module]
        .compactMap { $0.url(forResource: "DayVDO", withExtension: "icns") }
        .compactMap(NSImage.init(contentsOf:))
        .first

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let icon = Self.icon {
                Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
            Text(L10n.string(GuideCourse.tour.title)).font(.title.bold())
            if guide.needsReset {
                Text(guide.error ?? "")
                HStack {
                    Button(L10n.string("退出练习")) { guide.discardAndClose() }
                    Button(L10n.string("重新开始")) { guide.restart() }
                }
            } else {
                Text(L10n.string("欢迎使用DayVDO，本教程大约2-3分钟，帮你熟悉基础功能。"))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("语言与外观")).font(.headline)
                    VStack(spacing: 0) { AppearancePreferencesView() }
                        .labeledContentStyle(SettingsRowStyle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .id(store.settings.language)
                        .disabled(!store.canModify)
                }
                GuideSaveMessage(guide: guide)
                HStack {
                    Spacer()
                    Button(L10n.string("直接使用 DayVDO")) {
                        if guide.close(skipping: true) { navigation.navigate(to: .today) }
                    }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.string("开始练习")) { guide.startTour() }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 460).interactiveDismissDisabled()
    }
}

struct GuidePracticeMenu: View {
    @ObservedObject var guide: OnboardingSession
    @State private var confirmsRestart = false
    var body: some View {
        Menu {
            Text(L10n.string(guide.course.title))
            Text(guide.progress.day.date().formatted(date: .abbreviated, time: .omitted))
            #if DEBUG
            if guide.debugEnabled {
                Text(verbatim: "\(guide.course.rawValue) / \(guide.progress.step.rawValue)")
                Text(verbatim: guide.progress.todoID?.uuidString ?? "—")
                Toggle(L10n.string("模拟保存失败"), isOn: $guide.simulateSaveFailure)
            }
            #endif
            Button(L10n.string("显示当前目标")) { guide.revealRequest += 1 }
            Button(L10n.string("暂停并退出")) { _ = guide.close() }
            Button(L10n.string("重新开始")) { confirmsRestart = true }
        } label: { Text(L10n.string("练习")) }
        .confirmationDialog(L10n.string("重新开始练习？"), isPresented: $confirmsRestart) {
            Button(L10n.string("重新开始"), role: .destructive) { guide.restart() }
            Button(L10n.string("取消"), role: .cancel) {}
        }
        .allowAppTerminationDuringDialog()
    }
}

struct GuideSaveMessage: View {
    @ObservedObject var guide: OnboardingSession
    var body: some View {
        if let error = guide.error, !guide.needsReset {
            VStack(alignment: .leading) {
                Text(error)
                HStack {
                    Button(L10n.string("重试")) { guide.persist() }
                    Button(L10n.string("放弃未保存的练习并退出")) { guide.discardAndClose() }
                }
            }
        }
    }
}

struct PracticeHint: View {
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject var guide: OnboardingSession
    let page: SidebarDestination
    private var showsTutorialDirections: Bool {
        guide.progress.step == .done && guide.course == .tour
    }

    private var target: GuideTarget {
        let step = guide.progress.step
        if showsTutorialDirections { return .sidebar(.settings) }
        if step != .done && page != step.destination { return .sidebar(step.destination) }
        switch step {
        case .create: return .add
        case .timelineIntro: return .timeline
        case .schedule, .complete, .dateRange, .assign: return guide.progress.todoID.map(GuideTarget.row) ?? .pane
        case .calendarIntro, .inspectWeek, .seeDates: return .mode
        case .tagSearch, .filter, .calendarFilter, .clearFilter: return .filter
        case .locate, .move, .resize, .undoResize: return guide.targetSchedule.map { .block($0.id) } ?? .pane
        default: return .pane
        }
    }
    private var message: String {
        let step = guide.progress.step
        if step == .calendarIntro, page == .today, let block = guide.targetSchedule, let todo = guide.targetTodo {
            return L10n.format("已为“%@”留出 %@–%@。待办仍在清单里。去日历看看。", todo.title,
                               SchedulePresentation.clock(block.startMinute), SchedulePresentation.clock(block.endMinute))
        }
        if showsTutorialDirections { return L10n.string("点击左侧的「设置」，看看以后在哪里重看教程。") }
        if step != .done && page != step.destination {
            return L10n.format("点击左侧栏的「%@」继续。", L10n.string(step.destination.title))
        }
        if step == .calendarIntro && guide.week {
            return L10n.string("先点工具栏中的「月」，看看整个月的待办分布。")
        }
        if step == .complete && guide.targetTodo?.isCompleted == true {
            return L10n.string("这项待办已经完成。点圆圈恢复，再点一次完成。")
        }
        if step == .locate && page == .calendar { return L10n.string("上方是待办日期，下方是留出的时间。点开刚才的时间块。") }
        if step == .search, let title = guide.targetTodo?.title { return L10n.format("在总待办搜索“%@”。", title) }
        return L10n.string(step.title)
    }

    var body: some View {
        GuideCallout(
            focus: GuideFocus(
                target,
                alternate: guide.progress.step == .schedule && page == .today ? .panel : nil,
                secondary: guide.progress.step == .schedule && page == .today ? .timeline : nil
            ),
            title: L10n.string(guide.progress.step == .done ? "练习完成" : guide.course.title),
            message: message,
            isInteractive: hasActions
        ) {
            if guide.progress.step == .done && !showsTutorialDirections {
                Button(L10n.string("进入 DayVDO")) {
                    if guide.finish() { navigation.navigate(to: .today) }
                }
            } else if guide.progress.todoID != nil && guide.targetTodo == nil {
                Button(L10n.string("撤销删除")) { if guide.undoManager.canUndo { guide.undoManager.undo() } }
                Button(L10n.string("恢复练习示例")) { guide.restoreExample() }
            } else if guide.progress.step == .timelineIntro, page == .today {
                Button(L10n.string("继续")) { guide.acknowledgeTimeline() }
            }
            GuideSaveMessage(guide: guide)
        }
    }

    private var hasActions: Bool {
        (guide.progress.step == .done && !showsTutorialDirections)
            || (guide.progress.step == .timelineIntro && page == .today)
            || guide.error != nil || (guide.progress.todoID != nil && guide.targetTodo == nil)
    }
}

struct TutorialDiscoveryHint: View {
    @ObservedObject var navigation: AppNavigation

    var body: some View {
        let onHelp = navigation.settingsCategory == .help
        GuideCallout(
            focus: onHelp ? GuideFocus(.openTutorials) : GuideFocus(.helpCategory, alternate: .settingsCategories),
            title: L10n.string("使用教程"),
            message: L10n.string(onHelp
                ? "点击「使用教程」右边的「打开」，就能重看本教程或选择进阶教程。"
                : "在上方的设置分类中选择「帮助」。"),
            isInteractive: false
        ) { EmptyView() }
    }
}

#if DEBUG
struct GuideDiagnostics: View {
    @ObservedObject var guide: OnboardingSession
    @Environment(\.dismiss) private var dismiss
    @State private var course = GuideCourse.tour
    @State private var step = GuideStep.preferences
    @State private var day = Date.now
    @State private var narrow = false
    @State private var failSave = false

    var body: some View {
        Form {
            Picker(L10n.string("课程"), selection: $course) {
                ForEach(GuideCourse.allCases, id: \.self) { Text(L10n.string($0.title)).tag($0) }
            }
            Picker(L10n.string("步骤"), selection: $step) {
                ForEach(course.steps, id: \.self) { Text($0.rawValue).tag($0) }
            }
            DatePicker(L10n.string("练习日期"), selection: $day, displayedComponents: .date)
            Toggle("760 × 468", isOn: $narrow)
            Toggle(L10n.string("模拟保存失败"), isOn: $failSave)
            Button(L10n.string("打开练习")) {
                let window = NSApp.mainWindow?.sheetParent ?? NSApp.mainWindow
                dismiss()
                DispatchQueue.main.async {
                    window?.setContentSize(narrow ? NSSize(width: 760, height: 468) : NSSize(width: 1080, height: 720))
                    guide.preview(course, step: step, day: LocalDay(day), failSave: failSave)
                }
            }
        }
        .onChange(of: course) { _, value in step = value.steps[0] }
        .padding(20).frame(width: 400)
    }
}
#endif
