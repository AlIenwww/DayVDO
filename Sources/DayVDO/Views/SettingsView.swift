import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore

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
            }

            Section(L10n.string("待办")) {
                Toggle(L10n.string("显示已完成的待办"), isOn: $store.settings.showCompleted)
                Picker(L10n.string("默认重要度"), selection: $store.settings.defaultPriority) {
                    ForEach(TodoItem.Priority.allCases) { priority in
                        Text(L10n.string(priority.title)).tag(priority)
                    }
                }
                Toggle(L10n.string("删除前询问"), isOn: $store.settings.confirmBeforeDeleting)
            }

            Section(L10n.string("日历")) {
                Toggle(L10n.string("每周从星期一开始"), isOn: $store.settings.startWeekOnMonday)
            }

            Section(L10n.string("关于")) {
                LabeledContent(L10n.string("应用"), value: "DayVDO")
                LabeledContent(L10n.string("版本"), value: "0.2.0")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.string("设置"))
        .padding(.top, 8)
    }
}
