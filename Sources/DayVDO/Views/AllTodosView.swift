import SwiftUI
import Combine

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
        let topLevelEntries: [TopLevelEntry]
        let topLevelIDs: [String]
        let childrenByProject: [UUID: [TodoItem]]

        init(topLevelEntries: [TopLevelEntry], childrenByProject: [UUID: [TodoItem]]) {
            self.topLevelEntries = topLevelEntries
            topLevelIDs = topLevelEntries.map(\.id)
            self.childrenByProject = childrenByProject
        }
    }

    @MainActor
    final class PresentationCache: ObservableObject {
        struct Key: Equatable {
            var revision: UInt64
            var query: String
            var filter: TodoFilterState
            var showCompleted: Bool
            var expanded: Set<UUID>
            var rendered: Set<UUID>
            var today: LocalDay
            var startsOnMonday = true
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
            var filter: TodoFilterState
            var showCompleted: Bool
            var today: LocalDay
            var startsOnMonday: Bool
            var locale: String
            var dynamicTypeSize: DynamicTypeSize

            init(_ key: Key) {
                revision = key.revision
                query = key.query
                filter = key.filter
                showCompleted = key.showCompleted
                today = key.today
                startsOnMonday = key.startsOnMonday
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
    @Binding var filter: TodoFilterState
    @Binding var scrollPosition: ScrollPosition
    @ObservedObject var expansionState: ProjectExpansionState
    let presentationCache: PresentationCache
    @State private var visualExpandedProjectIDs: Set<UUID> = []
    @State private var filteredExpansionOverrides: [UUID: Bool] = [:]
    @State private var renderedProjectIDs: Set<UUID> = []
    @State private var pendingCollapseDeadlines: [UUID: ContinuousClock.Instant] = [:]
    @State private var projectPendingDeletion: TodoProject?
    @State private var hoveredProjectID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSearchPresented = false
    @FocusState private var focusedProjectAddButtonID: UUID?
    @FocusState private var focusedEntryID: String?
    @State private var today = LocalDay(.now)

    init(
        editingItem: Binding<TodoItem?>,
        editingProject: Binding<TodoProject?>,
        searchFocusRequest: Int,
        query: Binding<String>,
        filter: Binding<TodoFilterState>,
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
            today: today, startsOnMonday: store.settings.startWeekOnMonday, locale: L10n.locale.identifier,
            dynamicTypeSize: dynamicTypeSize
        ), build: makePresentationSnapshot)
        ScrollView {
            // Keep the stack mounted so the final row can transition out.
            // The lazy stack still unloads offscreen rows and preserves measured project heights.
            LazyVStack(spacing: 0) {
                ForEach(presentation.topLevelEntries) { entry in
                    switch entry {
                    case .project(let project):
                        projectRow(
                            project,
                            children: presentation.childrenByProject[project.id] ?? []
                        )
                        .transition(.opacity)
                    case .todo(let item):
                        topLevelTodoRow(item)
                            .transition(.opacity)
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
        .overlay {
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
                .transition(.opacity)
            }
        }
        .animation(store.settings.allTodosListAnimation(reduceMotion: reduceMotion), value: presentation.topLevelIDs)
        .navigationTitle(L10n.string("总待办"))
        .onReceive(AppClock.refreshes) { _ in today = LocalDay(.now) }
        .searchable(
            text: $query,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: L10n.string("搜索待办")
        )
        .toolbar {
            ToolbarItem {
                TodoFilterButton(filter: $filter)
            }
        }
        .onAppear { synchronizeProjectExpansion(animated: false) }
        .onChange(of: hasActiveFiltering) { _, active in
            if !active { filteredExpansionOverrides.removeAll() }
        }
        .onDisappear {
            finishPendingProjectCollapses()
        }
        .task(id: pendingCollapseDeadlines.values.min()) {
            guard let deadline = pendingCollapseDeadlines.values.min() else { return }
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            let due = Set(pendingCollapseDeadlines.compactMap { $0.value <= .now ? $0.key : nil })
            renderedProjectIDs.subtract(due.subtracting(visualExpandedProjectIDs))
            for id in due { pendingCollapseDeadlines.removeValue(forKey: id) }
        }
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

            if hasActiveFiltering || expanded || renderedProjectIDs.contains(project.id) {
                CollapsibleProjectRowLayout(
                    progress: expanded ? 1 : 0,
                    projectID: project.id,
                    heightCache: presentationCache.heightStorage,
                    heightGeneration: presentationCache.heightGeneration
                ) {
                    ProjectTaskList(
                        project: project, children: children, editingItem: $editingItem, today: today,
                        emptyMessage: L10n.string(hasActiveFiltering && store.projectProgress(project).total > 0
                            ? "没有匹配的子任务" : "还没有子任务")
                    )
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
            setProjectExpanded(project.id, !expanded, animated: true)
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
            .animation(listControlAnimation, value: showsAddButton)
            .help(L10n.string("添加子任务"))
        }
        .frame(minHeight: 38, alignment: .center)
        .padding(.vertical, TopLevelTodoRowMetrics.verticalPadding)
        .textCase(nil)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            Button {
                setProjectExpanded(project.id, !expanded, animated: true)
            } label: {
                Color.clear
                    .frame(width: 64, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string(expanded ? "收起项目" : "展开项目"))
        }
        .onHover { isHovering in
            guard isHovering != (hoveredProjectID == project.id) else { return }
            withAnimation(listControlAnimation) {
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

    private func filteredChildren(in project: TodoProject, criteria: TodoFilterContext) -> [TodoItem] {
        let projectMatches = projectMatchesQuery(project)
        return store.items(in: project).filter { item in
            let matchesQuery = query.isEmpty || projectMatches || itemMatchesQuery(item)
            return matchesQuery && criteria.includes(item)
        }
    }

    private func makePresentationSnapshot() -> PresentationSnapshot {
        let criteria = TodoFilterContext(filter: filter, showCompleted: store.settings.showCompleted,
            today: today, startsOnMonday: store.settings.startWeekOnMonday)
        var childrenByProject: [UUID: [TodoItem]] = [:]
        var projectEntries: [TopLevelEntry] = []

        for project in store.projects {
            let needsChildren = hasActiveFiltering
                || isExpanded(project)
                || renderedProjectIDs.contains(project.id)
            let children = needsChildren ? filteredChildren(in: project, criteria: criteria) : []
            if needsChildren { childrenByProject[project.id] = children }

            let isVisible: Bool
            if !hasActiveFiltering {
                isVisible = store.settings.showCompleted || !store.projectIsCompleted(project)
            } else if !children.isEmpty {
                isVisible = true
            } else if filter.projectIDs.contains(project.id), store.projectProgress(project).total == 0 {
                isVisible = query.isEmpty || projectMatchesQuery(project)
            } else {
                isVisible = !filter.isActive
                    && projectMatchesQuery(project)
                    && (store.settings.showCompleted || !store.projectIsCompleted(project))
            }
            if isVisible { projectEntries.append(.project(project)) }
        }

        let todoEntries = store.items.lazy
            .filter { $0.projectID == nil && criteria.includes($0)
                && (query.isEmpty || itemMatchesQuery($0)) }
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
        if hasActiveFiltering { return filteredExpansionOverrides[project.id] ?? true }
        return visualExpandedProjectIDs.contains(project.id)
    }

    private func setProjectExpanded(_ projectID: UUID, _ expanded: Bool, animated: Bool) {
        if hasActiveFiltering {
            filteredExpansionOverrides[projectID] = expanded
            return
        }
        expansionState.setExpanded(expanded, for: projectID)

        if expanded {
            pendingCollapseDeadlines.removeValue(forKey: projectID)
            renderedProjectIDs.insert(projectID)
            let update = { _ = visualExpandedProjectIDs.insert(projectID) }
            if animated && projectDisclosureAnimation != nil {
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

        if animated && projectDisclosureAnimation != nil {
            pendingCollapseDeadlines[projectID] = .now + .milliseconds(180)
            visualExpandedProjectIDs.remove(projectID)
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visualExpandedProjectIDs.remove(projectID)
                renderedProjectIDs.remove(projectID)
                pendingCollapseDeadlines.removeValue(forKey: projectID)
            }
        }
    }

    private var projectDisclosureAnimation: Animation? {
        store.settings.animation(.easeInOut(duration: 0.16), for: .projectDisclosure, reduceMotion: reduceMotion)
    }

    private var listControlAnimation: Animation? {
        store.settings.animation(.easeOut(duration: 0.1), for: .listControls, reduceMotion: reduceMotion)
    }

    private var hasActiveFiltering: Bool {
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
            pendingCollapseDeadlines.removeValue(forKey: projectID)
        }
        if !desired.isSubset(of: renderedProjectIDs) {
            renderedProjectIDs.formUnion(desired)
        }

        let removed = visualExpandedProjectIDs.subtracting(desired)
        let update = {
            if visualExpandedProjectIDs != desired { visualExpandedProjectIDs = desired }
        }
        if animated && projectDisclosureAnimation != nil {
            let deadline = ContinuousClock.now + .milliseconds(180)
            for projectID in removed { pendingCollapseDeadlines[projectID] = deadline }
            update()
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                update()
                if renderedProjectIDs != desired { renderedProjectIDs = desired }
                if !pendingCollapseDeadlines.isEmpty { pendingCollapseDeadlines.removeAll() }
            }
        }
    }

    private func finishPendingProjectCollapses() {
        let collapsedIDs = Set(pendingCollapseDeadlines.keys)
            .subtracting(visualExpandedProjectIDs)
        guard !collapsedIDs.isEmpty else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            renderedProjectIDs.subtract(collapsedIDs)
            for projectID in collapsedIDs {
                pendingCollapseDeadlines.removeValue(forKey: projectID)
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
