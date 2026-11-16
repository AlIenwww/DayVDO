import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var isManagingTags = false
    @State private var isManagingProjects = false

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            Divider()
            ScrollView {
                pane
                    .frame(maxWidth: 440, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
            }
            .id(navigation.settingsCategory)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(L10n.string("设置"))
        .sheet(isPresented: $isManagingTags) { TaskTagManagementView() }
        .sheet(isPresented: $isManagingProjects) { ProjectManagementView() }
    }

    private var categoryBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(SettingsCategory.allCases) { category in
                    categoryButton(category)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.string("设置分类"))
            Picker(L10n.string("设置分类"), selection: $navigation.settingsCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(L10n.string(category.title), systemImage: category.symbol).tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 54)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .id(store.settings.language)
    }

    private func categoryButton(_ category: SettingsCategory) -> some View {
        let selected = navigation.settingsCategory == category
        let title = L10n.string(category.title)

        return Button {
            navigation.settingsCategory = category
        } label: {
            VStack(spacing: 4) {
                Image(systemName: category.symbol)
                    .font(.system(size: 22))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .frame(minWidth: 60, minHeight: 54)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.settingsCategory {
        case .general:
            preferences
        case .animation:
            AnimationSettingsPreview().disabled(!store.canModify)
        case .planning:
            planning
        case .calendar:
            settingsToggle("每周从星期一开始", isOn: $store.settings.startWeekOnMonday)
                .labeledContentStyle(SettingsRowStyle())
                .disabled(!store.canModify)
        case .shortcuts:
            ShortcutSettingsView()
        case .help:
            SettingsHelpView(guide: navigation.guide)
        case .about:
            SettingsAboutView()
        }
    }

    private var preferences: some View {
        VStack(spacing: 0) {
            LabeledContent(L10n.string("语言")) { LanguagePicker().labelsHidden() }
            Divider()
            LabeledContent(L10n.string("启动页面")) {
                Picker(L10n.string("启动页面"), selection: $store.settings.startupPage) {
                    ForEach(StartupPage.allCases) { page in Text(L10n.string(page.title)).tag(page) }
                }
                .labelsHidden()
            }
            Divider()
            LabeledContent(L10n.string("外观")) { AppearanceModePicker().labelsHidden() }
            Divider()
            LabeledContent(L10n.string("主题色")) {
                HStack(spacing: 8) {
                    ColorPicker(L10n.string("主题色"), selection: Binding(
                        get: { store.settings.themeColor?.color ?? Color(nsColor: .controlAccentColor) },
                        set: { store.settings.themeColor = TagColor(color: $0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Button(L10n.string("系统默认")) { store.settings.themeColor = nil }
                        .disabled(store.settings.themeColor == nil)
                }
            }
        }
        .labeledContentStyle(SettingsRowStyle())
        .pickerStyle(.menu)
        .disabled(!store.canModify)
    }

    private var planning: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                settingsToggle("显示已完成的待办", isOn: $store.settings.showCompleted)
                Divider()
                settingsToggle("删除前询问", isOn: $store.settings.confirmBeforeDeleting)
                Divider()
                LabeledContent(L10n.string("预计时长单位")) {
                    Picker(L10n.string("预计时长单位"), selection: $store.settings.estimatedDurationUnit) {
                        ForEach(EstimatedDurationUnit.allCases) { unit in Text(unit.label).tag(unit) }
                    }
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.string("新建待办"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 6)
                LabeledContent(L10n.string("项目")) {
                    Button(L10n.string("管理")) { isManagingProjects = true }
                        .accessibilityLabel(L10n.string("管理项目…"))
                }
                Divider()
                LabeledContent(L10n.string("标签")) {
                    Button(L10n.string("管理")) { isManagingTags = true }
                        .accessibilityLabel(L10n.string("管理标签…"))
                }
                Divider()
                DefaultScheduleDurationPicker(minutes: $store.settings.defaultScheduleMinutes)
                Divider()
                LabeledContent(L10n.string("默认重要度")) {
                    Picker(L10n.string("默认重要度"), selection: $store.settings.defaultPriority) {
                        ForEach(TodoItem.Priority.allCases) { value in Text(L10n.string(value.title)).tag(value) }
                    }
                    .labelsHidden()
                }
                Divider()
                LabeledContent(L10n.string("默认紧急度")) {
                    Picker(L10n.string("默认紧急度"), selection: $store.settings.defaultUrgency) {
                        ForEach(TodoItem.Urgency.allCases) { value in Text(L10n.string(value.title)).tag(value) }
                    }
                    .labelsHidden()
                }
            }
        }
        .labeledContentStyle(SettingsRowStyle())
        .pickerStyle(.menu)
        .disabled(!store.canModify)
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        LabeledContent(L10n.string(title)) {
            Toggle(L10n.string(title), isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct AppearancePreferencesView: View {
    var body: some View {
        LabeledContent {
            LanguagePicker().labelsHidden()
        } label: {
            Label(L10n.string("语言"), systemImage: "globe")
        }
        LabeledContent {
            AppearanceModePicker().labelsHidden()
        } label: {
            Label(L10n.string("外观"), systemImage: "circle.lefthalf.filled")
        }
    }
}

private struct LanguagePicker: View {
    @EnvironmentObject private var store: TodoStore
    var body: some View {
        Picker(L10n.string("语言"), selection: $store.settings.language) {
            ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
        }
    }
}

private struct AppearanceModePicker: View {
    @EnvironmentObject private var store: TodoStore
    var body: some View {
        Picker(L10n.string("外观"), selection: $store.settings.appearance) {
            ForEach(AppearanceMode.allCases) { appearance in Text(appearance.title).tag(appearance) }
        }
        .id(store.settings.language)
    }
}

struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            configuration.content
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 34)
        .padding(.vertical, 4)
    }
}

struct DefaultScheduleDurationPicker: View {
    @Binding var minutes: Int
    @State private var isCustom = false
    @State private var input = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    static let presets = [15, 30, 45, 60, 90, 120]

    static func validatedMinutes(_ input: String) -> Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1440).contains(value) else { return nil }
        return value
    }

    var body: some View {
        Group {
            LabeledContent(L10n.string("默认安排时长")) {
                Picker(L10n.string("默认安排时长"), selection: Binding(
                    get: { isCustom || !Self.presets.contains(minutes) ? 0 : minutes },
                    set: { value in
                        isCustom = value == 0
                        invalid = false
                        if value != 0 { minutes = value }
                        input = String(minutes)
                    }
                )) {
                    ForEach(Self.presets, id: \.self) { value in Text(L10n.format("%lld 分钟", value)).tag(value) }
                    Text(L10n.string("自定义")).tag(0)
                }
                .labelsHidden()
            }
            if isCustom || !Self.presets.contains(minutes) {
                LabeledContent(L10n.string("分钟")) {
                    TextField("1–1440", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .focused($focused)
                        .accessibilityLabel(L10n.string("默认安排时长"))
                        .onSubmit(commit)
                        .onChange(of: focused) { _, value in if !value { commit() } }
                }
                if invalid {
                    Text(L10n.string("请输入 1–1440 的整数分钟。"))
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onAppear { input = String(minutes) }
        .onChange(of: minutes) { _, value in if !focused { input = String(value) } }
        .onDisappear { if focused { commit() } }
    }

    private func commit() {
        guard let value = Self.validatedMinutes(input) else { invalid = true; return }
        invalid = false
        minutes = value
    }
}

private struct SettingsHelpView: View {
    @ObservedObject var guide: OnboardingSession
    @State private var showsGlossary = false

    var body: some View {
        VStack(spacing: 0) {
            LabeledContent(L10n.string("新手指引")) {
                Button(L10n.string(guide.progress.status == .paused ? "继续练习" : "开始练习")) { guide.open() }
            }
            Divider()
            LabeledContent(L10n.string("词典")) {
                Button(L10n.string("打开")) { showsGlossary = true }
                    .accessibilityLabel(L10n.string("词典"))
            }
        }
        .labeledContentStyle(SettingsRowStyle())
        .sheet(isPresented: $showsGlossary) { GlossarySheet() }
    }
}

private struct GlossarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @State private var selection: GlossaryTerm? = .todo

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.string("词典"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            Divider()
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(GlossaryTerm.allCases) { term in
                        Text(L10n.string(term.title))
                            .fixedSize(horizontal: false, vertical: true)
                            .tag(term)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 158)
                Divider()
                detail(selection ?? .todo)
            }
            .frame(height: 320)
            Divider()
            HStack {
                Spacer()
                Button(L10n.string("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 520)
        .editorEscapeDismissal(cancel: { dismiss() })
    }

    private func detail(_ term: GlossaryTerm) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SettingsIllustration(scene: .concept(term),
                    tint: store.settings.themeColor?.color ?? .accentColor)
                    .frame(maxWidth: 244)
                    .frame(maxWidth: .infinity)
                Text(L10n.string(term.title))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.string(term.definition))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("DayVDO")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(appVersion)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("版本"))
                    .accessibilityValue(appVersion)
            }

            Divider()

            HStack(spacing: 12) {
                Image("GitHubMark", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("GitHub 项目页面"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.string("求求点个免费的星吧🙏>_<"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Link(destination: URL(string: "https://github.com/AlIenwww/DayVDO")!) {
                    Label(L10n.string("前往页面"), systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            // `swift run` launches a bare executable without an Info.plist. The
            // shipped app always takes the version from its bundle above.
            ?? "0.9.1"
    }
}
