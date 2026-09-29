import SwiftUI

fileprivate final class ProjectHeightStorage: @unchecked Sendable {
    // SwiftUI Layout callbacks are not main-actor isolated. The lock protects
    // every read and write of the measured sizes.
    private let lock = NSLock()
    private var entries: [UUID: (width: CGFloat, size: CGSize)] = [:]

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    func size(for id: UUID, width: CGFloat) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[id], abs(entry.width - width) < 0.5 else {
            return nil
        }
        return entry.size
    }

    func record(_ size: CGSize, for id: UUID, width: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        entries[id] = (width, size)
    }
}

struct AllTodosView: View {
    enum TopLevelEntry: Identifiable {
        case project(TodoProject)
        case todo(TodoItem)

        var id: String {
            switch self {
            case .project(let project): "project-\(project.id.uuidString)"
            case .todo(let item): "todo-\(item.id.uuidString)"
            }
        }

        var createdAt: Date {
            switch self {
            case .project(let project): project.createdAt
            case .todo(let item): item.createdAt
            }
        }
    }

    struct PresentationSnapshot {
        var topLevelEntries: [TopLevelEntry]
        var childrenByProject: [UUID: [TodoItem]]
    }

    @MainActor
    final class PresentationCache: ObservableObject {
        struct Key: Equatable {
            var revision: UInt64
            var query: String
            var filter: AllTodosFilterState
            var showCompleted: Bool
            var expanded: Set<UUID>
            var rendered: Set<UUID>
            var today: LocalDay
            var locale: String
            var dynamicTypeSize: DynamicTypeSize
        }

        private var key: Key?
        private var snapshot: PresentationSnapshot?
        private var heightContext: HeightContext?
        fileprivate let heightStorage = ProjectHeightStorage()
        private(set) var heightGeneration = 0

        private struct HeightContext: Equatable {
            var revision: UInt64
            var query: String
            var filter: AllTodosFilterState
            var showCompleted: Bool
            var today: LocalDay
            var locale: String
            var dynamicTypeSize: DynamicTypeSize

            init(_ key: Key) {
                revision = key.revision
                query = key.query
                filter = key.filter
                showCompleted = key.showCompleted
                today = key.today
                locale = key.locale
                dynamicTypeSize = key.dynamicTypeSize
            }
        }

        func value(for key: Key, build: () -> PresentationSnapshot) -> PresentationSnapshot {
            let context = HeightContext(key)
            if heightContext != context {
                heightContext = context
                heightStorage.clear()
                heightGeneration &+= 1
            }
            if self.key == key, let snapshot { return snapshot }
            let result = build()
            self.key = key
            snapshot = result
            return result
        }

    }

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var editingItem: TodoItem?
    @Binding var editingProject: TodoProject?
    let searchFocusRequest: Int
    @Binding var query: String
    @Binding var filter: AllTodosFilterState
    @Binding var scrollPosition: ScrollPosition
    @ObservedObject var expansionState: ProjectExpansionState
    let presentationCache: PresentationCache
    @State private var visualExpandedProjectIDs: Set<UUID> = []
    @State private var renderedProjectIDs: Set<UUID> = []
    @State private var pendingCollapseTokens: [UUID: UUID] = [:]
    @State private var projectPendingDeletion: TodoProject?
    @State private var hoveredProjectID: UUID?
    @State private var dropTargetItemID: UUID?
    @State private var isSearchPresented = false
    @State private var isFilterPresented = false
    @FocusState private var focusedProjectAddButtonID: UUID?
    @FocusState private var focusedEntryID: String?

    init(
        editingItem: Binding<TodoItem?>,
        editingProject: Binding<TodoProject?>,
        searchFocusRequest: Int,
        query: Binding<String>,
        filter: Binding<AllTodosFilterState>,
        scrollPosition: Binding<ScrollPosition>,
        expansionState: ProjectExpansionState,
        presentationCache: PresentationCache
    ) {
        _editingItem = editingItem
        _editingProject = editingProject
        self.searchFocusRequest = searchFocusRequest
        _query = query
        _filter = filter
        _scrollPosition = scrollPosition
        self.expansionState = expansionState
        self.presentationCache = presentationCache
        // Restore the expanded rows before the first layout, not in a second pass.
        _visualExpandedProjectIDs = State(initialValue: expansionState.expandedIDs)
        _renderedProjectIDs = State(initialValue: expansionState.expandedIDs)
    }

    var body: some View {
        let presentation = presentationCache.value(for: .init(
            revision: store.contentRevision, query: query, filter: filter,
            showCompleted: store.settings.showCompleted,
            expanded: visualExpandedProjectIDs, rendered: renderedProjectIDs,
            today: LocalDay(.now), locale: L10n.locale.identifier,
            dynamicTypeSize: dynamicTypeSize
        ), build: makePresentationSnapshot)
        Group {
            if presentation.topLevelEntries.isEmpty {
                EmptyStateView(
                    title: L10n.string(hasActiveFiltering ? "没有找到结果" : "还没有待办"),
                    message: L10n.string(
                        hasActiveFiltering
                            ? "请尝试其他关键词或筛选条件。"
                            : "添加待办或大项目，开始规划接下来的事情。"
                    ),
                    symbol: hasActiveFiltering ? "line.3.horizontal.decrease.circle" : "checklist"
                )
            } else {
                ScrollView {
                    // A project retains its measured natural height in the
                    // presentation cache when this lazy stack unloads its row.
                    LazyVStack(spacing: 0) {
                        ForEach(presentation.topLevelEntries) { entry in
                            switch entry {
                            case .project(let project):
                                projectRow(
                                    project,
                                    children: presentation.childrenByProject[project.id] ?? []
                                )
                            case .todo(let item):
                                topLevelTodoRow(item)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                }
                .scrollPosition($scrollPosition)
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .interacting {
                        finishPendingProjectCollapses()
                    }
                }
            }
        }
        .navigationTitle(L10n.string("总待办"))
        .searchable(
            text: $query,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: L10n.string("搜索待办")
        )
        .toolbar {
            ToolbarItem {
                Button {
                    isFilterPresented.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(L10n.string("筛选"))
                            .lineLimit(1)
                        if filter.isActive {
                            Text("\(filter.activeCategoryCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Color.accentColor, in: Circle())
                        }
                    }
                    .foregroundStyle(filter.isActive ? Color.accentColor : Color.primary)
                    .frame(width: 104)
                }
                .help(L10n.string("筛选待办"))
                .accessibilityLabel(L10n.string("筛选待办"))
                .accessibilityValue(
                    filter.isActive
                        ? L10n.format("已启用 %lld 类筛选", filter.activeCategoryCount)
                        : L10n.string("未启用筛选")
                )
                .popover(isPresented: $isFilterPresented, arrowEdge: .top) {
                    AllTodosFilterPopover(filter: $filter)
                }
            }
        }
        .onAppear { synchronizeProjectExpansion(animated: false) }
        .task(id: searchFocusRequest) {
            guard searchFocusRequest > 0 else { return }
            await Task.yield()
            isSearchPresented = true
        }
        .onChange(of: store.projects) { _, projects in
            sanitizeFilter(projectIDs: Set(projects.map(\.id)), tagIDs: Set(store.tags.map(\.id)))
            synchronizeProjectExpansion(animated: true)
        }
        .onChange(of: store.items) { _, _ in synchronizeProjectExpansion(animated: true) }
        .onChange(of: store.tags) { _, tags in
            sanitizeFilter(projectIDs: Set(store.projects.map(\.id)), tagIDs: Set(tags.map(\.id)))
        }
        .confirmationDialog(
            L10n.format("删除项目“%@”？", projectPendingDeletion?.title ?? ""),
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let project = projectPendingDeletion {
                Button(L10n.string("删除项目并保留子任务")) {
                    _ = store.deleteProject(project, strategy: .keepTasks)
                    projectPendingDeletion = nil
                }
                Button(L10n.string("删除项目及所有子任务"), role: .destructive) {
                    _ = store.deleteProject(project, strategy: .deleteTasks)
                    projectPendingDeletion = nil
                }
            }
            Button(L10n.string("取消"), role: .cancel) { projectPendingDeletion = nil }
        } message: {
            Text(L10n.string("你可以将子任务保留为普通待办，或将它们一起删除。"))
        }
    }

    private func topLevelTodoRow(_ item: TodoItem) -> some View {
        VStack(spacing: 0) {
            TodoRow(item: item, showsOverdue: true, presentation: .topLevel) {
                editingItem = item
            }
            .padding(.horizontal, TopLevelTodoRowMetrics.listHorizontalInset)

            topLevelDivider
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedEntryID, equals: "todo-\(item.id.uuidString)")
        .onKeyPress(.return) {
            editingItem = item
            return .handled
        }
        .onKeyPress(.space) {
            _ = store.toggle(item)
            return .handled
        }
    }

    private func projectRow(_ project: TodoProject, children: [TodoItem]) -> some View {
        let expanded = isExpanded(project)

        return VStack(spacing: 0) {
            projectHeader(project, expanded: expanded)
                .padding(.horizontal, TopLevelTodoRowMetrics.listHorizontalInset)

            if expanded || renderedProjectIDs.contains(project.id) {
                CollapsibleProjectRowLayout(
                    progress: expanded ? 1 : 0,
                    projectID: project.id,
                    heightCache: presentationCache.heightStorage,
                    heightGeneration: presentationCache.heightGeneration
                ) {
                    projectChildrenContent(project, children: children)
                }
                .opacity(expanded ? 1 : 0)
                .animation(projectDisclosureAnimation, value: expanded)
                .clipped()
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)
                .padding(.leading, TopLevelTodoRowMetrics.listHorizontalInset)
                .padding(.trailing, TopLevelTodoRowMetrics.listHorizontalInset)
            }

            topLevelDivider
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedEntryID, equals: "project-\(project.id.uuidString)")
        .onKeyPress(.return) {
            editingProject = project
            return .handled
        }
        .onKeyPress(.space) {
            if !isExpansionForced {
                setProjectExpanded(project.id, !expanded, animated: true)
            }
            return .handled
        }
    }

    private var topLevelDivider: some View {
        Divider()
            .padding(
                .leading,
                TopLevelTodoRowMetrics.listHorizontalInset
                    + TopLevelTodoRowMetrics.separatorLeading
            )
            .padding(.trailing, TopLevelTodoRowMetrics.listHorizontalInset)
    }

    @ViewBuilder
    private func projectChildrenContent(_ project: TodoProject, children: [TodoItem]) -> some View {
        if children.isEmpty {
            Text(L10n.string(hasActiveFiltering ? "没有匹配的子任务" : "还没有子任务"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    Color.secondary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                }
                .padding(.top, 5)
                .padding(.leading, 28)
                .padding(.bottom, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, item in
                    let isFirst = index == 0
                    let isLast = index == children.count - 1
                    let shape = UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: isFirst ? 10 : 0,
                            bottomLeading: isLast ? 10 : 0,
                            bottomTrailing: isLast ? 10 : 0,
                            topTrailing: isFirst ? 10 : 0
                        ),
                        style: .continuous
                    )

                    TodoRow(item: item, showsProject: false, showsOverdue: true) {
                        editingItem = item
                    }
                        .padding(.horizontal, 10)
                        .background(Color.secondary.opacity(0.055), in: shape)
                        .overlay { shape.stroke(Color.secondary.opacity(0.12), lineWidth: 0.5) }
                        .overlay(alignment: .top) {
                            if dropTargetItemID == item.id {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.leading, 28)
                        .draggable(item.id.uuidString)
                        .dropDestination(for: String.self) { values, _ in
                            guard let rawID = values.first,
                                  let draggedID = UUID(uuidString: rawID) else { return false }
                            return store.moveProjectItem(draggedID, before: item.id, in: project.id)
                        } isTargeted: { targeted in
                            dropTargetItemID = targeted ? item.id : nil
                        }
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 12)
        }
    }

    private func projectHeader(
        _ project: TodoProject,
        expanded: Bool
    ) -> some View {
        let progress = store.projectProgress(project)
        let completed = store.projectIsCompleted(project)
        let showsAddButton = hoveredProjectID == project.id
            || focusedProjectAddButtonID == project.id

        return HStack(spacing: TopLevelTodoRowMetrics.columnSpacing) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(
                    width: TopLevelTodoRowMetrics.disclosureWidth,
                    height: 18
                )
                .animation(projectDisclosureAnimation, value: expanded)
                .accessibilityHidden(true)

            ProjectFolderIcon(completed: completed)
                .equatable()
                .frame(
                    width: TopLevelTodoRowMetrics.statusWidth,
                    height: TopLevelTodoRowMetrics.statusWidth
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(completed ? .secondary : .primary)
                    .strikethrough(completed)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                HStack(spacing: 8) {
                    if let tag = store.tag(withID: project.tagID) {
                        TaskTagLabel(tag: tag)
                            .frame(maxWidth: 110, alignment: .leading)
                    }

                    if let dueDate = project.dueDate {
                        Label(
                            dueDate.formatted(
                                .dateTime.year().month(.abbreviated).day().locale(L10n.locale)
                            ),
                            systemImage: "calendar"
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }

                    HStack(spacing: 6) {
                        ProgressView(
                            value: Double(progress.completed),
                            total: Double(max(progress.total, 1))
                        )
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .frame(minWidth: 52, idealWidth: 88, maxWidth: 88)

                        Text(L10n.format("%lld / %lld 已完成", progress.completed, progress.total))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .layoutPriority(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editingProject = project }

            Button {
                setProjectExpanded(project.id, true, animated: true)
                editingItem = store.newItem(in: project)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .focused($focusedProjectAddButtonID, equals: project.id)
            .opacity(showsAddButton ? 1 : 0)
            .allowsHitTesting(showsAddButton)
            .animation(.easeOut(duration: 0.1), value: showsAddButton)
            .help(L10n.string("添加子任务"))
        }
        .frame(minHeight: 38, alignment: .center)
        .padding(.vertical, TopLevelTodoRowMetrics.verticalPadding)
        .textCase(nil)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            Button {
                setProjectExpanded(
                    project.id,
                    !visualExpandedProjectIDs.contains(project.id),
                    animated: true
                )
            } label: {
                Color.clear
                    .frame(width: 64, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isExpansionForced)
            .accessibilityLabel(L10n.string(isExpanded(project) ? "收起项目" : "展开项目"))
        }
        .onHover { isHovering in
            guard isHovering != (hoveredProjectID == project.id) else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                if isHovering {
                    hoveredProjectID = project.id
                } else if hoveredProjectID == project.id {
                    hoveredProjectID = nil
                }
            }
        }
        .contextMenu {
            Button(L10n.string("编辑项目"), systemImage: "pencil") { editingProject = project }
            Button(L10n.string("添加子任务"), systemImage: "plus") {
                setProjectExpanded(project.id, true, animated: true)
                editingItem = store.newItem(in: project)
            }
            Divider()
            Button(L10n.string("删除项目"), systemImage: "trash", role: .destructive) {
                projectPendingDeletion = project
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(project.title)
        .accessibilityValue(
            L10n.format(
                "%lld / %lld 已完成，%@",
                progress.completed,
                progress.total,
                L10n.string(expanded ? "已展开" : "已收回")
            )
        )
        .accessibilityAction(named: L10n.string(expanded ? "收起项目" : "展开项目")) {
            setProjectExpanded(project.id, !expanded, animated: true)
        }
        .accessibilityAction(named: L10n.string("编辑项目")) { editingProject = project }
        .accessibilityAction(named: L10n.string("添加子任务")) {
            setProjectExpanded(project.id, true, animated: true)
            editingItem = store.newItem(in: project)
        }
    }

    private func filteredChildren(in project: TodoProject) -> [TodoItem] {
        let projectMatches = projectMatchesQuery(project)
        return store.items(in: project).filter { item in
            let matchesQuery = query.isEmpty || projectMatches || itemMatchesQuery(item)
            let matchesFilter = filter.includes(
                item,
                showCompletedPreference: store.settings.showCompleted,
                matchesSearch: matchesQuery
            )
            return matchesFilter
        }
    }

    private func makePresentationSnapshot() -> PresentationSnapshot {
        var childrenByProject: [UUID: [TodoItem]] = [:]
        var projectEntries: [TopLevelEntry] = []

        for project in store.projects {
            let needsChildren = hasActiveFiltering
                || isExpanded(project)
                || renderedProjectIDs.contains(project.id)
            let children = needsChildren ? filteredChildren(in: project) : []
            if needsChildren { childrenByProject[project.id] = children }

            let isVisible: Bool
            if !hasActiveFiltering {
                isVisible = store.settings.showCompleted || !store.projectIsCompleted(project)
            } else if !children.isEmpty {
                isVisible = true
            } else {
                isVisible = !filter.isActive
                    && projectMatchesQuery(project)
                    && (store.settings.showCompleted || !store.projectIsCompleted(project))
            }
            if isVisible { projectEntries.append(.project(project)) }
        }

        let todoEntries = store.items.lazy
            .filter { $0.projectID == nil && itemMatches($0) }
            .map(TopLevelEntry.todo)
        let entries = (projectEntries + todoEntries).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id > $1.id
        }
        return PresentationSnapshot(
            topLevelEntries: entries,
            childrenByProject: childrenByProject
        )
    }

    private func itemMatches(_ item: TodoItem) -> Bool {
        return filter.includes(
            item,
            showCompletedPreference: store.settings.showCompleted,
            matchesSearch: query.isEmpty || itemMatchesQuery(item)
        )
    }

    private func itemMatchesQuery(_ item: TodoItem) -> Bool {
        item.title.localizedStandardContains(query)
            || item.notes.localizedStandardContains(query)
            || store.tag(withID: item.tagID)?.name.localizedStandardContains(query) == true
    }

    private func projectMatchesQuery(_ project: TodoProject) -> Bool {
        project.title.localizedStandardContains(query)
            || project.notes.localizedStandardContains(query)
            || store.tag(withID: project.tagID)?.name.localizedStandardContains(query) == true
    }

    private func isExpanded(_ project: TodoProject) -> Bool {
        isExpansionForced || visualExpandedProjectIDs.contains(project.id)
    }

    private func setProjectExpanded(_ projectID: UUID, _ expanded: Bool, animated: Bool) {
        guard !isExpansionForced else { return }
        expansionState.setExpanded(expanded, for: projectID)

        if expanded {
            pendingCollapseTokens.removeValue(forKey: projectID)
            renderedProjectIDs.insert(projectID)
            let update = { _ = visualExpandedProjectIDs.insert(projectID) }
            if animated {
                Task { @MainActor in
                    await Task.yield()
                    guard expansionState.isExpanded(projectID) else { return }
                    update()
                }
            } else {
                update()
            }
            return
        }

        if animated {
            let token = UUID()
            pendingCollapseTokens[projectID] = token
            visualExpandedProjectIDs.remove(projectID)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                if pendingCollapseTokens[projectID] == token,
                   !visualExpandedProjectIDs.contains(projectID),
                   !isExpansionForced {
                    renderedProjectIDs.remove(projectID)
                    pendingCollapseTokens.removeValue(forKey: projectID)
                }
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visualExpandedProjectIDs.remove(projectID)
                renderedProjectIDs.remove(projectID)
                pendingCollapseTokens.removeValue(forKey: projectID)
            }
        }
    }

    private var projectDisclosureAnimation: Animation {
        .easeInOut(duration: 0.16)
    }

    private var hasActiveFiltering: Bool {
        !query.isEmpty || filter.isActive
    }

    private var isExpansionForced: Bool {
        !query.isEmpty || filter.isActive
    }

    private func sanitizeFilter(projectIDs: Set<UUID>, tagIDs: Set<UUID>) {
        var sanitized = filter
        sanitized.sanitize(projectIDs: projectIDs, tagIDs: tagIDs)
        if sanitized != filter { filter = sanitized }
    }

    private func synchronizeProjectExpansion(animated: Bool) {
        let projectIDs = Set(store.projects.map(\.id))
        let completedIDs = Set(store.projects.filter(store.projectIsCompleted).map(\.id))
        expansionState.synchronize(projectIDs: projectIDs, completedIDs: completedIDs)
        let desired = expansionState.expandedIDs
        for projectID in desired {
            pendingCollapseTokens.removeValue(forKey: projectID)
        }
        if !desired.isSubset(of: renderedProjectIDs) {
            renderedProjectIDs.formUnion(desired)
        }

        let removed = visualExpandedProjectIDs.subtracting(desired)
        let update = {
            if visualExpandedProjectIDs != desired { visualExpandedProjectIDs = desired }
        }
        if animated {
            let tokens = Dictionary(uniqueKeysWithValues: removed.map { ($0, UUID()) })
            pendingCollapseTokens.merge(tokens) { _, new in new }
            update()
            if !removed.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    let stillPending = Set(tokens.compactMap { projectID, token in
                        pendingCollapseTokens[projectID] == token
                            && !visualExpandedProjectIDs.contains(projectID)
                            ? projectID
                            : nil
                    })
                    renderedProjectIDs.subtract(stillPending)
                    for projectID in stillPending {
                        pendingCollapseTokens.removeValue(forKey: projectID)
                    }
                }
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                update()
                if renderedProjectIDs != desired { renderedProjectIDs = desired }
                if !pendingCollapseTokens.isEmpty { pendingCollapseTokens.removeAll() }
            }
        }
    }

    private func finishPendingProjectCollapses() {
        let collapsedIDs = Set(pendingCollapseTokens.keys)
            .subtracting(visualExpandedProjectIDs)
        guard !collapsedIDs.isEmpty else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            renderedProjectIDs.subtract(collapsedIDs)
            for projectID in collapsedIDs {
                pendingCollapseTokens.removeValue(forKey: projectID)
            }
        }
    }
}

private struct ProjectFolderIcon: View, Equatable {
    let completed: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(completed ? Color.accentColor : .secondary)

            if completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(1)
                    .background(.background, in: Circle())
            }
        }
    }
}

private struct AllTodosFilterPopover: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: AllTodosFilterState

    private let gridColumns = [
        GridItem(.adaptive(minimum: 136), spacing: 8)
    ]

    private var sortedProjects: [TodoProject] {
        store.projects.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("筛选"))
                    .font(.headline)
                Spacer()
                Button(L10n.string("清除全部")) { filter.clear() }
                    .buttonStyle(.borderless)
                    .disabled(!filter.isActive)
                    .accessibilityHint(L10n.string("移除所有筛选条件"))
            }

            Divider()

            filterSection(L10n.string("状态")) {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(TodoItem.Status.allCases) { status in
                        filterChoice(
                            title: L10n.string(status.title),
                            symbol: status.symbolName,
                            color: status.color,
                            isSelected: filter.statuses.contains(status)
                        ) {
                            toggle(status, at: \.statuses)
                        }
                    }

                    filterChoice(
                        title: L10n.string("已逾期"),
                        symbol: "exclamationmark.circle.fill",
                        color: .red,
                        isSelected: filter.overdueOnly
                    ) {
                        filter.overdueOnly.toggle()
                    }
                }
            }

            filterSection(L10n.string("所属项目")) {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        filterListChoice(
                            title: L10n.string("无归类"),
                            symbol: "tray",
                            isSelected: filter.includesUnassignedProject
                        ) {
                            filter.includesUnassignedProject.toggle()
                        }

                        ForEach(sortedProjects) { project in
                            filterListChoice(
                                title: project.title,
                                symbol: "folder",
                                isSelected: filter.projectIDs.contains(project.id)
                            ) {
                                toggle(project.id, at: \.projectIDs)
                            }
                        }
                    }
                }
                .scrollIndicators(sortedProjects.count > 3 ? .visible : .hidden)
                .frame(height: listHeight(itemCount: sortedProjects.count + 1))
            }

            filterSection(L10n.string("标签")) {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        filterListChoice(
                            title: L10n.string("无标签"),
                            symbol: "tag.slash",
                            isSelected: filter.includesUntagged
                        ) {
                            filter.includesUntagged.toggle()
                        }

                        ForEach(store.sortedTags) { tag in
                            filterListChoice(
                                title: tag.name,
                                isSelected: filter.tagIDs.contains(tag.id),
                                leading: { TaskTagDot(tag: tag, size: 9) }
                            ) {
                                toggle(tag.id, at: \.tagIDs)
                            }
                        }
                    }
                }
                .scrollIndicators(store.sortedTags.count > 3 ? .visible : .hidden)
                .frame(height: listHeight(itemCount: store.sortedTags.count + 1))
            }

            filterSection(L10n.string("重要度")) {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(TodoItem.Priority.allCases) { priority in
                        filterChoice(
                            title: L10n.string(priority.title),
                            symbol: priority.symbolName,
                            color: priority.swiftUIColor,
                            isSelected: filter.priorities.contains(priority)
                        ) {
                            toggle(priority, at: \.priorities)
                        }
                    }
                }
            }

            filterSection(L10n.string("紧急度")) {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(TodoItem.Urgency.allCases) { urgency in
                        filterChoice(
                            title: L10n.string(urgency.title),
                            symbol: urgency.symbolName,
                            color: urgency.filterColor,
                            isSelected: filter.urgencies.contains(urgency)
                        ) {
                            toggle(urgency, at: \.urgencies)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .onExitCommand { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("筛选待办"))
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func filterChoice(
        title: String,
        symbol: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 15)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityValue(L10n.string(isSelected ? "已选择" : "未选择"))
    }

    private func filterListChoice(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        filterListChoice(
            title: title,
            isSelected: isSelected,
            leading: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                    .accessibilityHidden(true)
            },
            action: action
        )
    }

    private func filterListChoice<Leading: View>(
        title: String,
        isSelected: Bool,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading()
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityValue(L10n.string(isSelected ? "已选择" : "未选择"))
    }

    private func toggle<Value: Hashable>(
        _ value: Value,
        at keyPath: WritableKeyPath<AllTodosFilterState, Set<Value>>
    ) {
        var updated = filter
        if updated[keyPath: keyPath].contains(value) {
            updated[keyPath: keyPath].remove(value)
        } else {
            updated[keyPath: keyPath].insert(value)
        }
        filter = updated
    }

    private func listHeight(itemCount: Int) -> CGFloat {
        min(CGFloat(max(itemCount, 1)) * 31, 112)
    }
}

private extension TodoItem.Urgency {
    var filterColor: Color {
        switch self {
        case .none: .secondary
        case .canWait: .green
        case .today: .blue
        case .mustToday: .red
        }
    }
}

private struct CollapsibleProjectRowLayout: Layout, Animatable {
    struct Cache {
        var width: CGFloat?
        var naturalSize = CGSize.zero
        var generation = -1
    }

    var progress: Double
    let projectID: UUID
    fileprivate let heightCache: ProjectHeightStorage
    let heightGeneration: Int

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        updateNaturalSizeIfNeeded(proposal: proposal, subview: subview, cache: &cache)
        return CGSize(
            width: proposal.width ?? cache.naturalSize.width,
            height: cache.naturalSize.height * max(0, min(progress, 1))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard let subview = subviews.first else { return }
        updateNaturalSizeIfNeeded(
            proposal: ProposedViewSize(width: bounds.width, height: nil),
            subview: subview,
            cache: &cache
        )
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: cache.naturalSize.height)
        )
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.width = nil
        cache.naturalSize = .zero
        cache.generation = -1
    }

    private func updateNaturalSizeIfNeeded(
        proposal: ProposedViewSize,
        subview: LayoutSubview,
        cache: inout Cache
    ) {
        if cache.generation != heightGeneration {
            cache.width = nil
            cache.naturalSize = .zero
            cache.generation = heightGeneration
        }
        guard cache.width != proposal.width || cache.naturalSize == .zero else { return }
        cache.width = proposal.width
        if let width = proposal.width,
           let measured = heightCache.size(for: projectID, width: width) {
            cache.naturalSize = measured
            return
        }
        cache.naturalSize = subview.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        if let width = proposal.width {
            heightCache.record(cache.naturalSize, for: projectID, width: width)
        }
    }
}
