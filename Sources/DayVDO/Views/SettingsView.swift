import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        Form {
            Section("待办") {
                Toggle("显示已完成的待办", isOn: $store.settings.showCompleted)
                Picker("默认优先级", selection: $store.settings.defaultPriority) {
                    ForEach(TodoItem.Priority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                Toggle("删除前询问", isOn: $store.settings.confirmBeforeDeleting)
            }

            Section("日历") {
                Toggle("每周从星期一开始", isOn: $store.settings.startWeekOnMonday)
            }

            Section("关于") {
                LabeledContent("应用", value: "DayVDO")
                LabeledContent("版本", value: "0.1.0")
                Text("一款专注、原生且尊重系统外观的 macOS 待办应用。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .padding(.top, 8)
    }
}
