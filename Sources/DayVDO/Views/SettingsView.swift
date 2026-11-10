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
        case .appearance:
            AppearanceSettingsView()
        case .planning:
            planning
        case .calendar:
            Toggle(L10n.string("每周从星期一开始"), isOn: $store.settings.startWeekOnMonday)
                .toggleStyle(.checkbox)
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
        Form {
            LanguagePicker()
            Picker(L10n.string("启动页面"), selection: $store.settings.startupPage) {
                ForEach(StartupPage.allCases) { page in Text(L10n.string(page.title)).tag(page) }
            }
        }
        .formStyle(.columns)
        .pickerStyle(.menu)
        .disabled(!store.canModify)
    }

    private var planning: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Toggle(L10n.string("显示已完成的待办"), isOn: $store.settings.showCompleted)
                Toggle(L10n.string("删除前询问"), isOn: $store.settings.confirmBeforeDeleting)
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("新建待办"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Form {
                    Picker(L10n.string("默认重要度"), selection: $store.settings.defaultPriority) {
                        ForEach(TodoItem.Priority.allCases) { value in Text(L10n.string(value.title)).tag(value) }
                    }
                    Picker(L10n.string("默认紧急度"), selection: $store.settings.defaultUrgency) {
                        ForEach(TodoItem.Urgency.allCases) { value in Text(L10n.string(value.title)).tag(value) }
                    }
                }
                .formStyle(.columns)
                .pickerStyle(.menu)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        managementButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        managementButtons
                    }
                }
            }

            Form { DefaultScheduleDurationPicker(minutes: $store.settings.defaultScheduleMinutes) }
                .formStyle(.columns)
                .pickerStyle(.menu)
        }
        .disabled(!store.canModify)
    }

    @ViewBuilder
    private var managementButtons: some View {
        Button(L10n.string("管理标签…")) { isManagingTags = true }
        Button(L10n.string("管理项目…")) { isManagingProjects = true }
    }
}

struct AppearancePreferencesView: View {
    var body: some View {
        LanguagePicker()
        AppearanceModePicker()
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

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                AppearanceModePicker()
                LabeledContent(L10n.string("主题色")) {
                    ColorPicker(L10n.string("主题色"), selection: Binding(
                        get: { store.settings.themeColor?.color ?? Color(nsColor: .controlAccentColor) },
                        set: { store.settings.themeColor = TagColor(color: $0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Button(L10n.string("系统默认")) { store.settings.themeColor = nil }
                        .disabled(store.settings.themeColor == nil)
                }
            }
            .formStyle(.columns)
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string("动画效果")).font(.headline).accessibilityAddTraits(.isHeader)
                if reduceMotion {
                    Text(L10n.string("系统已开启减少动态效果。")).foregroundStyle(.secondary)
                }
                ForEach(AppAnimationEffect.allCases) { effect in
                    Toggle(L10n.string(effect.title), isOn: Binding(
                        get: { store.settings.animates(effect) },
                        set: { enabled in
                            if enabled { store.settings.disabledAnimations.remove(effect) }
                            else { store.settings.disabledAnimations.insert(effect) }
                        }
                    ))
                }
            }
            .toggleStyle(.checkbox)
        }
        .disabled(!store.canModify)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(L10n.string("新手指引")).font(.headline)
                Spacer()
                Button(L10n.string(guide.progress.status == .paused ? "继续练习" : "开始练习")) { guide.open() }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("词典"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                term("待办", "要做的一件事，可以设置日期、标签和预计时长。")
                term("安排", "在时间线上留出的一段时间，可以关联待办，也可以独立存在。")
                term("项目", "一组相关待办，用于跟踪共同目标。")
                term("标签", "可跨项目使用的颜色分类，也可以用来筛选。")
                term("重要度", "事情有多重要。")
                term("紧急度", "事情需要多快处理。")
                term("预计时长", "完成待办大约需要的时间。")
            }
        }
    }

    private func term(_ title: String, _ definition: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(title)).fontWeight(.medium)
            Text(L10n.string(definition)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 3)
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DayVDO").font(.title2.weight(.semibold))
            LabeledContent(L10n.string("版本"), value: appVersion)
            Link(destination: URL(string: "https://github.com/AlIenwww/DayVDO")!) {
                Label("GitHub", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            // `swift run` launches a bare executable without an Info.plist. The
            // shipped app always takes the version from its bundle above.
            ?? "0.9.0"
    }
}

struct GuideConceptsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("核心概念")).font(.headline)
            Text(L10n.string("待办是要做的事，安排是分配的时间，项目是相关待办的集合。"))
            Text(L10n.string("安排也可以独立存在，例如午休或会议。安排了时间，不代表待办已经完成。"))
                .foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
