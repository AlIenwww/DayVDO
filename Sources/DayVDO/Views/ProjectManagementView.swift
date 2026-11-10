import SwiftUI

struct ProjectManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @State private var editing: TodoProject?
    @State private var deleting: TodoProject?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("管理项目")).font(.headline)
                Spacer()
                Button {
                    editing = TodoProject(title: "")
                } label: {
                    Label(L10n.string("新建大项目"), systemImage: "plus")
                }
                .disabled(!store.canModify)
            }
            .padding(16)

            Divider()
            if store.sortedProjects.isEmpty {
                ContentUnavailableView(L10n.string("还没有项目"), systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.sortedProjects) { project in
                    HStack(spacing: 10) {
                        Label(project.title, systemImage: "folder")
                            .lineLimit(1)
                        Spacer()
                        Button { editing = project } label: {
                            Label(L10n.string("编辑大项目"), systemImage: "pencil")
                                .labelStyle(.iconOnly)
                        }
                        .help(L10n.string("编辑大项目"))
                        Button(role: .destructive) { deleting = project } label: {
                            Label(L10n.string("删除项目"), systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .help(L10n.string("删除项目"))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.canModify)
                }
                .listStyle(.inset)
            }
            Divider()

            HStack {
                Spacer()
                Button(L10n.string("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
        .sheet(item: $editing) { project in
            ProjectEditorView(project: project, isEditing: store.project(withID: project.id) != nil) {
                store.upsertProject($0)
            }
        }
        .confirmationDialog(
            L10n.format("删除项目“%@”？", deleting?.title ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { project in
            Button(L10n.string("删除项目并保留子任务")) {
                _ = store.deleteProject(project, strategy: .keepTasks)
            }
            Button(L10n.string("删除项目及所有子任务"), role: .destructive) {
                _ = store.deleteProject(project, strategy: .deleteTasks)
            }
        } message: { _ in
            Text(L10n.string("你可以将子任务保留为普通待办，或将它们一起删除。"))
        }
    }
}
