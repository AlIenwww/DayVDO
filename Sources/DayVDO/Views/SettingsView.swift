import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var isManagingTags = false

    var body: some View {
        Form {
            Section(L10n.string("通用")) {
                Picker(L10n.string("语言"), selection: $store.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker(L10n.string("外观"), selection: $store.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .id(store.settings.language)
            }

            Section(L10n.string("待办")) {
                Toggle(L10n.string("显示已完成的待办"), isOn: $store.settings.showCompleted)
                Picker(L10n.string("默认重要度"), selection: $store.settings.defaultPriority) {
                    ForEach(TodoItem.Priority.allCases) { priority in
                        Text(L10n.string(priority.title)).tag(priority)
                    }
                }
                .id(store.settings.language)
                Toggle(L10n.string("删除前询问"), isOn: $store.settings.confirmBeforeDeleting)
            }

            Section(L10n.string("日历")) {
                Toggle(L10n.string("每周从星期一开始"), isOn: $store.settings.startWeekOnMonday)
            }

            Section(L10n.string("标签")) {
                LabeledContent(L10n.string("自定义标签")) {
                    Button(L10n.string("管理标签…")) {
                        isManagingTags = true
                    }
                }
            }

            Section(L10n.string("关于")) {
                LabeledContent(L10n.string("应用"), value: "DayVDO")
                LabeledContent(L10n.string("版本"), value: appVersion)
            }
        }
        .formStyle(.grouped)
        .disabled(!store.canModify)
        .navigationTitle(L10n.string("设置"))
        .sheet(isPresented: $isManagingTags) {
            TaskTagManagementView()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            // `swift run` launches a bare executable without an Info.plist. The
            // shipped app always takes the version from its bundle above.
            ?? "0.8.1"
    }
}
