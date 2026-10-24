import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SchedulePopoverRequest: Identifiable, Equatable {
    enum Mode: Equatable { case details, editor }

    var id = UUID()
    var scheduleID: UUID
    var mode: Mode

    static func details(_ scheduleID: UUID) -> Self {
        Self(scheduleID: scheduleID, mode: .details)
    }

    static func editor(_ scheduleID: UUID) -> Self {
        Self(scheduleID: scheduleID, mode: .editor)
    }
}

private struct ScheduleTitleFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ScheduleStatusFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct DayTimelineView: View {
    @EnvironmentObject private var store: TodoStore
    let day: LocalDay
    @Binding var hourHeight: CGFloat
    @Binding var restoredScrollMinute: CGFloat?
    let now: Date
    /// Keep the native scroll viewport full-width while laying out schedules
    /// beside the overlaid todo list.
    var reservedTrailingWidth: CGFloat = 0
    var obscuredWidth: CGFloat = 0
    var trailingPanel: PlanningTodoPanel? = nil
    var trailingPanelWidth: CGFloat = 280
    var creationDraft: Binding<DaySchedule?> = .constant(nil)
    @Binding var presentation: SchedulePopoverRequest?
    var create: (Int, Int, Double) -> Void
    var dropTodo: (UUID, Int, Double) -> Void
    var editTodo: (TodoItem) -> Void
    var activityChanged: (Bool) -> Void

    @State private var position = ScrollPosition(y: 0)
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 400
    @State private var maximumScrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 400
    @State private var isViewportReady = false
    @State private var needsInitialPosition = true
    @State private var selectedID: UUID?
    @State private var creationAnchor = CGPoint.zero
    @State private var titleFrames: [UUID: CGRect] = [:]
    @State private var statusFrames: [UUID: CGRect] = [:]
    @State private var magnificationBase: CGFloat?
    @State private var magnificationAnchor: TimelineZoomAnchor?
    @State private var zoomTarget: CGFloat?
    @State private var previousMagnification: CGFloat = 1
    @State private var interaction: Interaction?
    @State private var preview: DaySchedule?
    @State private var createRange: Range<Int>?
    @State private var pointerX: CGFloat?
    @State private var pointerY: CGFloat?
    @State private var draftID = UUID()
    @State private var positionUpdatedAt = Date.now
    @State private var externalTodoID: UUID?
    @State private var externalMinute: Int?
    @State private var externalActive = false
    @State private var pendingDrop: UUID?
    @State private var cancellation = TimelineDragCancellation()
    @FocusState private var isFocused: Bool
    private let gutter: CGFloat = 54

    private struct Interaction {
        var original: DaySchedule?
        var mode: Mode
        var originY: CGFloat
        var originOffset: CGFloat
        var creationStart: Int? = nil
        var creationOrigin: Double? = nil
    }
    private enum Mode { case move, start, end, create }
    private var pixelsPerMinute: CGFloat { hourHeight / 60 }
    private var currentMinute: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
    private var activePreview: DaySchedule? {
        if let preview { return preview }
        guard let range = createRange ?? externalMinute.map({ $0..<($0 + externalDuration) }) else { return nil }
        return DaySchedule(id: draftID, startDay: day, startMinute: range.lowerBound,
            durationMinutes: range.count, content: .independent(title: "", notes: ""),
            horizontalPosition: horizontalPosition, horizontalPositionUpdatedAt: positionUpdatedAt)
    }
    private var horizontalPosition: Double {
        DayPlanningPolicy.horizontalPosition(x: Double(pointerX ?? gutter), minX: Double(gutter),
                                              width: Double(viewportWidth - gutter - 8))
    }
    private var placementPriority: UUID? {
        if let interaction, interaction.original != nil, interaction.mode != .move { return nil }
        return activePreview?.id
    }
    private var displayed: [DaySchedule] {
        var values = store.schedules(on: day).map { $0.id == activePreview?.id ? activePreview! : $0 }
        if let activePreview, !values.contains(where: { $0.id == activePreview.id }) { values.append(activePreview) }
        return values
    }

    var body: some View {
        GeometryReader { geometry in
            let timelineWidth = max(1, geometry.size.width - reservedTrailingWidth)
            let placements = DayPlanningPolicy.placements(displayed, on: day, prioritizing: placementPriority)
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    grid(width: timelineWidth)
                    if day == LocalDay(now) {
                        let lineY = CGFloat(currentMinute) * pixelsPerMinute
                        Rectangle()
                            .fill(.red)
                            .frame(width: max(1, timelineWidth - gutter), height: 1)
                            .offset(x: gutter, y: lineY - 0.5)
                            .allowsHitTesting(false)
                    }
                    if displayed.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                            Text(L10n.string("这一天暂无安排"))
                        }
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(width: max(1, timelineWidth - gutter), height: min(180, viewportHeight))
                        .offset(x: gutter)
                        .allowsHitTesting(false)
                    }
                    ForEach(placements) { placement in
                        if let schedule = displayed.first(where: { $0.id == placement.id }) {
                            if schedule.id == draftID {
                                previewBand(placement, width: timelineWidth)
                            } else {
                                scheduleBlock(schedule, placement: placement, width: timelineWidth)
                            }
                        }
                    }
                    TimelineTimeLabels(hourHeight: hourHeight,
                                       currentMinute: day == LocalDay(now) ? currentMinute : nil)
                        .frame(width: gutter - 8, height: hourHeight * 24)
                    if day == LocalDay(now) {
                        let lineY = CGFloat(currentMinute) * pixelsPerMinute
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                            .offset(x: gutter - 3, y: lineY - 3)
                            .allowsHitTesting(false)
                    }
                    if let trailingPanel {
                        PlanningTodoViewport(panel: trailingPanel, isDropTarget: isReturningToList,
                                             castsShadow: reservedTrailingWidth == 0)
                            .frame(width: trailingPanelWidth, height: 1)
                    }
                }
                .frame(width: timelineWidth, height: hourHeight * 24, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .background(alignment: .topLeading) {
                    Color.clear
                        .frame(width: max(1, timelineWidth - gutter))
                        .contentShape(Rectangle())
                        .offset(x: gutter)
                        .gesture(creationGesture)
                }

            }
            .contentMargins(.trailing, reservedTrailingWidth, for: .scrollIndicators)
            .scrollClipDisabled()
            .onPreferenceChange(ScheduleTitleFrames.self) { titleFrames = $0 }
            .onPreferenceChange(ScheduleStatusFrames.self) { statusFrames = $0 }
            .scrollPosition($position)
            .popover(item: creationDraft,
                     attachmentAnchor: .point(TimelinePopoverAnchor.point(at: creationAnchor, in: geometry.size)),
                     arrowEdge: .trailing) { schedule in
                ScheduleEditorView(schedule: schedule, isCreating: true,
                    close: { creationDraft.wrappedValue = nil }, editTodo: editTodo)
            }
            .popover(
                item: $presentation,
                attachmentAnchor: .point(popoverAttachmentPoint(
                    placements: placements,
                    width: timelineWidth,
                    height: geometry.size.height
                )),
                arrowEdge: .trailing
            ) { request in
                if let latest = store.schedules.first(where: { $0.id == request.scheduleID }) {
                    SchedulePopoverView(
                        schedule: latest,
                        startsEditing: request.mode == .editor,
                        editTodo: editTodo,
                        close: { presentation = nil }
                    )
                    .id(request.id)
                }
            }
            .scrollDisabled(magnificationAnchor != nil)
            .coordinateSpace(name: "planningViewport")
            .contentShape(Rectangle())
            .background(alignment: .leading) {
                ScheduleClickMonitor(acceptsClick: { location in
                    scheduleHit(at: location, placements: placements, width: timelineWidth) != nil
                }) { location, count in
                    guard let hit = scheduleHit(at: location, placements: placements, width: timelineWidth) else { return }
                    if count == 2 {
                        if titleFrames[hit.id]?.contains(hit.point) == true {
                            editScheduleTodo(hit.id)
                        } else {
                            showSchedule(hit.id, mode: .editor)
                        }
                    } else if count == 1 {
                        selectSchedule(hit.id)
                    }
                }
                .frame(width: timelineWidth, height: geometry.size.height)
            }
            .onScrollGeometryChange(for: TodayTimelineViewport.self) { value in
                TodayTimelineViewport(offset: value.contentOffset.y + value.contentInsets.top,
                                      height: value.containerSize.height,
                                      maximumOffset: max(0, value.contentSize.height + value.contentInsets.top
                                          + value.contentInsets.bottom - value.containerSize.height))
            } action: { _, value in
                scrollOffset = value.offset
                viewportHeight = value.height
                maximumScrollOffset = value.maximumOffset
                isViewportReady = value.height > 0
                applyInitialPositionIfReady()
            }
            .onAppear {
                viewportWidth = timelineWidth
                applyInitialPositionIfReady()
            }
            .onChange(of: store.isInitialLoading) { _, _ in applyInitialPositionIfReady() }
            .onChange(of: timelineWidth) { _, width in viewportWidth = width }
            .onDisappear {
                if !needsInitialPosition {
                    restoredScrollMinute = scrollOffset / max(pixelsPerMinute, 0.001)
                }
                needsInitialPosition = true
                isViewportReady = false
                cancel()
                magnificationBase = nil
                magnificationAnchor = nil
                zoomTarget = nil
            }
            .onChange(of: day) { _, _ in
                cancel()
                magnificationBase = nil
                magnificationAnchor = nil
                zoomTarget = nil
                selectedID = nil
                presentation = nil
                restoredScrollMinute = nil
                needsInitialPosition = true
                applyInitialPositionIfReady()
            }
            .onChange(of: displayed) { _, latest in
                if let id = selectedID, !latest.contains(where: { $0.id == id && $0.interval(on: day) != nil }) {
                    selectedID = nil
                }
                guard let request = presentation else { return }
                if !DayPlanningPolicy.placements(latest, on: day)
                    .contains(where: { $0.id == request.scheduleID }) {
                    presentation = nil
                    if selectedID == request.scheduleID { selectedID = nil }
                }
            }
            .onChange(of: scrollOffset) { _, _ in dismissOffscreenPopover() }
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .idle && !needsInitialPosition {
                    restoredScrollMinute = scrollOffset / max(pixelsPerMinute, 0.001)
                }
            }
            .task(id: needsInteractionTicks) {
                guard needsInteractionTicks else { return }
                while !Task.isCancelled {
                    finishCancellationIfReleased()
                    autoScroll()
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            .task(id: needsZoomTicks) {
                guard needsZoomTicks else { return }
                while !Task.isCancelled {
                    advanceZoom()
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if magnificationBase == nil {
                            magnificationBase = hourHeight
                            previousMagnification = 1
                            zoomTarget = hourHeight
                            magnificationAnchor = TimelineZoomPolicy.anchor(
                                scrollOffset: scrollOffset,
                                viewportHeight: viewportHeight,
                                hourHeight: hourHeight
                            )
                        }
                        // Accumulate input against the bounded target so reversing
                        // at a limit responds immediately, without a dead zone.
                        zoomTarget = TimelineZoomPolicy.clampedHourHeight(
                            (zoomTarget ?? hourHeight) * scale / max(0.001, previousMagnification)
                        )
                        previousMagnification = scale
                    }
                    .onEnded { _ in
                        magnificationBase = nil
                    }
            )
            .background(alignment: .leading) {
                TimelineControlScrollMonitor { delta, precise in
                    let sensitivity: CGFloat = precise ? 0.8 : 8
                    if magnificationAnchor == nil {
                        magnificationAnchor = TimelineZoomPolicy.anchor(
                            scrollOffset: scrollOffset,
                            viewportHeight: viewportHeight,
                            hourHeight: hourHeight
                        )
                    }
                    zoomTarget = TimelineZoomPolicy.clampedHourHeight(
                        (zoomTarget ?? hourHeight) + delta * sensitivity
                    )
                }
                .frame(width: timelineWidth, height: geometry.size.height)
            }
            .focusable().focusEffectDisabled().focused($isFocused)
            .editorReturnSubmission(enabled: presentation?.mode == .editor || creationDraft.wrappedValue != nil) {
                if let id = creationDraft.wrappedValue?.id ?? presentation?.scheduleID {
                    NotificationCenter.default.post(name: .scheduleEditorSubmit, object: id)
                }
            }
            .background(TimelineSelectionKeyMonitor(
                enabled: selectedID != nil && presentation == nil && creationDraft.wrappedValue == nil
                    && interaction == nil && !cancellation.isSuppressed,
                delete: deleteSelectedSchedule,
                clear: { selectedID = nil }
            ))
            .onKeyPress(.escape) {
                selectedID = nil
                cancellation.cancel(isDragging: interaction != nil)
                cancel()
                activityChanged(cancellation.isSuppressed)
                return .handled
            }
            .onDeleteCommand {
                guard isFocused else { return }
                deleteSelectedSchedule()
            }
            .onKeyPress(.upArrow) { selectAdjacent(-1); return .handled }
            .onKeyPress(.downArrow) { selectAdjacent(1); return .handled }
            .onKeyPress(.space) {
                guard let schedule = store.schedules.first(where: { $0.id == selectedID }),
                      let todo = store.item(withID: schedule.todoID) else { return .ignored }
                store.toggle(todo); return .handled
            }
            .onKeyPress(.return) {
                if let id = creationDraft.wrappedValue?.id ?? (presentation?.mode == .editor ? presentation?.scheduleID : nil) {
                    NotificationCenter.default.post(name: .scheduleEditorSubmit, object: id)
                    return .handled
                }
                guard let selected = store.schedules.first(where: { $0.id == selectedID }) else { return .ignored }
                showSchedule(selected.id, mode: .editor); return .handled
            }

        }
        .overlay(alignment: .topLeading) {
            if let dragTimeLabel, let pointerY {
                Text(isReturningToList ? L10n.string("移除安排") : dragTimeLabel)
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: gutter + 6, y: max(4, min(viewportHeight - 30, pointerY - 32)))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.url], delegate: dropDelegate(width: viewportWidth))
    }

    private func dropDelegate(width: CGFloat) -> PlanningDropDelegate {
        PlanningDropDelegate(
            isValidLocation: { $0.x >= gutter && $0.x <= width - obscuredWidth && $0.y >= 0 && $0.y <= viewportHeight },
            enter: { location in
                guard pendingDrop == nil else { return }
                externalActive = true
                draftID = UUID(); positionUpdatedAt = .now
                activityChanged(true)
                pointerX = location.x
                pointerY = location.y
                externalMinute = dropMinute(at: location)
            },
            update: { location in
                // SwiftUI can deliver a trailing update after performDrop. It must
                // not recreate a hover preview or keep the page busy after saving.
                guard externalActive else { return }
                pointerX = location.x
                pointerY = location.y
                externalMinute = dropMinute(at: location)
            },
            identify: { id in if externalActive { externalTodoID = id } },
            exit: { cancelExternal() },
            prepare: { location in
                let minute = dropMinute(at: location)
                let horizontal = DayPlanningPolicy.horizontalPosition(x: Double(location.x), minX: Double(gutter),
                                                                      width: Double(width - gutter - 8))
                let token = UUID()
                pendingDrop = token
                externalActive = false
                pointerX = nil
                pointerY = nil
                externalMinute = nil
                externalTodoID = nil
                activityChanged(true)
                return { id in
                    guard pendingDrop == token else { return }
                    defer { pendingDrop = nil; activityChanged(interaction != nil || externalActive) }
                    if let id { dropTodo(id, minute, horizontal) }
                }
            }
        )
    }

    private func dropMinute(at location: CGPoint) -> Int {
        min(1435, max(0, DayPlanningPolicy.snapped(Double((location.y + scrollOffset - 12) / pixelsPerMinute))))
    }

    private var externalDuration: Int {
        guard let id = externalTodoID, let todo = store.items.first(where: { $0.id == id }) else { return 30 }
        return DayPlanningPolicy.defaultDuration(estimated: todo.estimatedMinutes, scheduled: store.scheduledMinutes(for: id))
    }

    private func grid(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<49, id: \.self) { half in
                let y = CGFloat(half) * hourHeight / 2
                Rectangle().fill(Color.secondary.opacity(half.isMultiple(of: 2) ? 0.18 : 0.07))
                    .frame(width: max(1, width - gutter), height: 1).offset(x: gutter, y: y)
            }
        }.allowsHitTesting(false)
    }

    private func scheduleBlock(_ schedule: DaySchedule, placement: DayPlanningPolicy.Placement, width: CGFloat) -> some View {
        let available = max(1, width - gutter - 8)
        let columnWidth = available / CGFloat(placement.columnCount)
        let height = CGFloat(placement.interval.count) * pixelsPerMinute
        let todo = store.items.first { $0.id == schedule.todoID }
        let complete = todo?.isCompleted == true
        let color = complete ? Color.secondary : todo.map { store.tag(withID: $0.tagID)?.color.color ?? .accentColor } ?? .secondary
        let isInProgress = DayPlanningPolicy.isInProgress(
            placement,
            at: currentMinute,
            onCurrentDay: day == LocalDay(now)
        )
        let cornerRadius = min(5, height / 2)
        let shape = TimelineScheduleShape.shape(placement: placement, radius: cornerRadius)
        return ZStack(alignment: .topLeading) {
            shape
                .fill(color.opacity(0.14))
            if isInProgress {
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: max(4, height - 6))
                    .padding(.leading, 3)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            shape
                .strokeBorder(color.opacity(selectedID == schedule.id ? 0.9 : 0.35), lineWidth: selectedID == schedule.id ? 2 : 1)
            if height >= 14 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let todo, height >= 24 {
                            Button { store.toggle(todo) } label: {
                                TodoStatusIcon(status: todo.status)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(L10n.string(complete ? "标记为未完成" : "标记为已完成"))
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: ScheduleStatusFrames.self,
                                            value: [schedule.id: geometry.frame(in: .named(schedule.id))])
                                    }
                                }
                        }
                        if schedule.startDay != day || schedule.endMinute > 1440 {
                            Image(systemName: schedule.startDay != day ? "arrow.turn.down.right" : "arrow.turn.up.right")
                                .accessibilityLabel(L10n.string(schedule.startDay != day ? "从前一天延续" : "延续至次日"))
                        }
                        Text(SchedulePresentation.title(schedule, store: store))
                            .font(.caption.weight(.medium)).strikethrough(complete).lineLimit(1)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: ScheduleTitleFrames.self,
                                        value: [schedule.id: geometry.frame(in: .named(schedule.id))])
                                }
                            }
                            .accessibilityIdentifier("timeline.title.\(schedule.id)")
                            .allowsHitTesting(false)
                    }
                    if height >= 40 {
                        Text(SchedulePresentation.time(schedule)).font(.caption2.monospacedDigit()).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if height >= 57 && (schedule.startDay != day || schedule.endMinute > 1440) {
                        Text(L10n.string(schedule.startDay != day ? "从前一天延续" : "延续至次日"))
                            .font(.caption2).lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, height >= 24 ? 4 : 0)
                .foregroundStyle(color)
            }
        }
        .frame(width: columnWidth, height: height)
        .coordinateSpace(name: schedule.id)
        .clipped()
        .contentShape(Rectangle())
        .gesture(blockGesture(schedule, mode: .move))
        .overlay(alignment: .top) {
            if height >= 24 && schedule.startDay == day {
                resizeHandle(schedule, mode: .start)
            }
        }
        .overlay(alignment: .bottom) {
            if height >= 24 && schedule.endMinute - schedule.startDay.distance(to: day) * 1440 <= 1440 {
                resizeHandle(schedule, mode: .end)
            }
        }
        .offset(x: gutter + CGFloat(placement.column) * columnWidth,
                y: CGFloat(placement.interval.lowerBound) * pixelsPerMinute)
        .contextMenu {
            if let todo {
                TodoStatusMenuItems(item: todo)
                Divider()
            }
            if todo != nil {
                Button(L10n.string("编辑任务")) {
                    DispatchQueue.main.async { editScheduleTodo(schedule.id) }
                }
            }
            Button(L10n.string("编辑安排")) {
                // Present after the native context menu has closed.
                DispatchQueue.main.async { showSchedule(schedule.id, mode: .editor) }
            }
            Button(L10n.string("移除安排"), role: .destructive) {
                presentation = nil
                store.deleteSchedule(schedule.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.schedule.\(schedule.id)")
        .accessibilityLabel(
            SchedulePresentation.title(schedule, store: store)
                + ", " + SchedulePresentation.time(schedule)
                + (isInProgress ? ", " + L10n.string("正在进行") : "")
        )
        .accessibilityAction {
            selectSchedule(schedule.id)
        }
        .accessibilityActions {
            if todo != nil {
                Button(L10n.string("编辑任务")) { editScheduleTodo(schedule.id) }
            }
        }
        .accessibilityAction(named: Text(L10n.string("编辑安排"))) { showSchedule(schedule.id, mode: .editor) }
        .accessibilityAction(named: Text(L10n.string("移除安排"))) {
            presentation = nil
            store.deleteSchedule(schedule.id)
        }
        .help(SchedulePresentation.title(schedule, store: store) + " · " + SchedulePresentation.time(schedule))
    }

    private func resizeHandle(_ schedule: DaySchedule, mode: Mode) -> some View {
        Color.clear
            .contentShape(Rectangle()).frame(height: 7)
            .gesture(blockGesture(schedule, mode: mode))
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() }
                else { NSCursor.arrow.set() }
            }
            .help(L10n.string("拖动调整时长"))
    }

    private func advanceZoom() {
        guard let target = zoomTarget, let anchor = magnificationAnchor else { return }
        let next = TimelineZoomPolicy.nextFrame(current: hourHeight, target: target)
        applyZoom(to: next, keeping: anchor)
        if next == target, magnificationBase == nil {
            zoomTarget = nil
            magnificationAnchor = nil
            restoredScrollMinute = scrollOffset / max(pixelsPerMinute, 0.001)
        }
    }

    private var needsInteractionTicks: Bool {
        interaction != nil || externalActive || cancellation.isSuppressed
    }

    private var needsZoomTicks: Bool {
        zoomTarget != nil && magnificationAnchor != nil
    }

    private func applyZoom(
        to targetHourHeight: CGFloat,
        keeping anchor: TimelineZoomAnchor
    ) {
        guard abs(targetHourHeight - hourHeight) > 0.001 else { return }
        let targetOffset = TimelineZoomPolicy.scrollOffset(
            keeping: anchor,
            hourHeight: targetHourHeight,
            viewportHeight: viewportHeight
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hourHeight = targetHourHeight
            scrollOffset = targetOffset
            position.scrollTo(y: targetOffset)
        }
    }

    private func selectSchedule(_ id: UUID) {
        guard displayed.contains(where: { $0.id == id && $0.interval(on: day) != nil }) else { return }
        selectedID = id
        isFocused = true
        presentation = nil
    }

    private func deleteSelectedSchedule() {
        guard let id = selectedID, store.canModify else { return }
        if presentation?.scheduleID == id { presentation = nil }
        if store.deleteSchedule(id) { selectedID = nil }
    }

    private func scheduleHit(at location: CGPoint, placements: [DayPlanningPolicy.Placement],
                             width: CGFloat) -> (id: UUID, point: CGPoint)? {
        guard validRelease(location) else { return nil }
        for placement in placements where placement.id != draftID {
            let columnWidth = max(1, width - gutter - 8) / CGFloat(placement.columnCount)
            let frame = CGRect(x: gutter + CGFloat(placement.column) * columnWidth,
                y: CGFloat(placement.interval.lowerBound) * pixelsPerMinute + 12 - scrollOffset,
                width: columnWidth, height: CGFloat(placement.interval.count) * pixelsPerMinute)
            guard frame.contains(location) else { continue }
            let point = CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
            guard statusFrames[placement.id]?.contains(point) != true else { return nil }
            return (placement.id, point)
        }
        return nil
    }

    private func editScheduleTodo(_ id: UUID) {
        guard let schedule = store.schedules.first(where: { $0.id == id }),
              schedule.interval(on: day) != nil else { return }
        if let todo = store.item(withID: schedule.todoID) {
            selectSchedule(id)
            editTodo(todo)
        } else {
            showSchedule(id, mode: .editor)
        }
    }

    private func showSchedule(_ id: UUID, mode: SchedulePopoverRequest.Mode) {
        guard displayed.contains(where: { $0.id == id && $0.interval(on: day) != nil }) else { return }
        selectedID = id
        isFocused = true
        presentation = mode == .editor ? .editor(id) : .details(id)
    }

    /// Attach the native popover to the stable scroll viewport, not to a
    /// disabled transparent overlay or a dynamic schedule block.
    private func popoverAttachmentPoint(
        placements: [DayPlanningPolicy.Placement],
        width: CGFloat,
        height: CGFloat
    ) -> UnitPoint {
        guard let placement = placements.first(where: { $0.id == presentation?.scheduleID }) else {
            return .center
        }
        let available = max(1, width - gutter - 8)
        let columnWidth = available / CGFloat(placement.columnCount)
        let blockHeight = CGFloat(placement.interval.count) * pixelsPerMinute
        let x = gutter + CGFloat(placement.column + 1) * columnWidth - 10
        let y = CGFloat(placement.interval.lowerBound) * pixelsPerMinute
            + 12 - scrollOffset + min(20, blockHeight / 2)
        return UnitPoint(
            x: min(0.98, max(0.02, x / max(1, width + reservedTrailingWidth))),
            y: min(0.98, max(0.02, y / max(1, height)))
        )
    }

    private func dismissOffscreenPopover() {
        guard let request = presentation,
              let placement = DayPlanningPolicy.placements(displayed, on: day)
                .first(where: { $0.id == request.scheduleID }) else { return }
        let top = CGFloat(placement.interval.lowerBound) * pixelsPerMinute + 12 - scrollOffset
        let bottom = CGFloat(placement.interval.upperBound) * pixelsPerMinute + 12 - scrollOffset
        if bottom < 0 || top > viewportHeight { presentation = nil }
    }

    private var dragTimeLabel: String? {
        if let preview { return SchedulePresentation.time(preview) }
        let range = createRange ?? externalMinute.map { $0..<($0 + externalDuration) }
        guard let range else { return nil }
        return SchedulePresentation.time(DaySchedule(startDay: day, startMinute: range.lowerBound,
            durationMinutes: range.count, content: .independent(title: "", notes: "")))
    }

    private func previewBand(_ placement: DayPlanningPolicy.Placement, width: CGFloat) -> some View {
        let columnWidth = max(1, width - gutter - 8) / CGFloat(placement.columnCount)
        return Rectangle().fill(Color.accentColor.opacity(0.15))
            .frame(width: columnWidth, height: CGFloat(placement.interval.count) * pixelsPerMinute)
            .offset(x: gutter + CGFloat(placement.column) * columnWidth,
                    y: CGFloat(placement.interval.lowerBound) * pixelsPerMinute)
            .allowsHitTesting(false)
    }

    private var creationGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("planningViewport"))
            .onChanged { value in
                guard !cancellation.isSuppressed else { return }
                if interaction == nil {
                    selectedID = nil
                    draftID = UUID(); positionUpdatedAt = .now
                    let minute = Double((value.startLocation.y + scrollOffset - 12) / pixelsPerMinute)
                    interaction = Interaction(mode: .create, originY: value.startLocation.y, originOffset: scrollOffset,
                        creationStart: TimelineCreationPolicy.startMinute(at: minute,
                            boundaries: creationBoundaries, pointsPerMinute: Double(pixelsPerMinute)),
                        creationOrigin: minute)
                    activityChanged(true)
                }
                pointerX = value.location.x; pointerY = value.location.y
                updatePreview()
            }
            .onEnded { value in
                defer { finishGesture() }
                guard !cancellation.isSuppressed, validRelease(value.location),
                      let interaction, let start = interaction.creationStart else { return }
                pointerX = value.location.x; pointerY = value.location.y
                updatePreview()
                let movement = value.translation.height + scrollOffset - interaction.originOffset
                let range = abs(movement) < 4 ? TimelineCreationPolicy.defaultRange(anchoredAt: start) : createRange
                guard let range else { return }
                let horizontal = horizontalPosition
                let anchor = value.location
                // Let the native mouse-up finish before a popover can take focus.
                DispatchQueue.main.async {
                    guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                    creationAnchor = anchor
                    create(range.lowerBound, range.count, horizontal)
                }
            }
    }

    private func blockGesture(_ schedule: DaySchedule, mode: Mode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("planningViewport"))
            .onChanged { value in
                guard !cancellation.isSuppressed else { return }
                if interaction == nil {
                    positionUpdatedAt = .now
                    interaction = Interaction(original: schedule, mode: mode, originY: value.startLocation.y, originOffset: scrollOffset)
                    selectedID = schedule.id; isFocused = true; activityChanged(true)
                }
                pointerX = value.location.x; pointerY = value.location.y
                updatePreview()
            }
            .onEnded { value in
                if !cancellation.isSuppressed, mode == .move, schedule.todoID != nil,
                   isInsideTodoPanel(value.location) {
                    store.deleteSchedule(schedule.id)
                    selectedID = nil
                } else if !cancellation.isSuppressed, validRelease(value.location) {
                    pointerX = value.location.x; pointerY = value.location.y
                    updatePreview()
                    if let preview { store.upsertSchedule(preview) }
                }
                finishGesture()
            }
    }

    private func finishGesture() {
        cancel()
        finishCancellationIfReleased()
        activityChanged(cancellation.isSuppressed)
    }

    private func finishCancellationIfReleased() {
        if cancellation.observeMouseButton(isPressed: NSEvent.pressedMouseButtons & 1 != 0) {
            activityChanged(interaction != nil || externalActive || pendingDrop != nil)
        }
    }

    private func validRelease(_ location: CGPoint) -> Bool {
        location.x >= gutter && location.x <= viewportWidth - obscuredWidth && location.y >= 0 && location.y <= viewportHeight
    }

    private func isInsideTodoPanel(_ point: CGPoint) -> Bool {
        guard trailingPanel != nil else { return false }
        let fullWidth = viewportWidth + reservedTrailingWidth
        return point.x >= fullWidth - trailingPanelWidth && point.x <= fullWidth
            && point.y >= 0 && point.y <= viewportHeight
    }

    private var isReturningToList: Bool {
        guard interaction?.mode == .move, interaction?.original?.todoID != nil,
              let pointerX, let pointerY else { return false }
        return isInsideTodoPanel(CGPoint(x: pointerX, y: pointerY))
    }

    private func updatePreview() {
        guard let interaction, let pointerY else { return }
        // Returning to the list cancels this one arrangement. Keep its original
        // time while hovering, so leaving the target can resume the same drag.
        if isReturningToList { preview = interaction.original; return }
        let delta = Double((pointerY - interaction.originY + scrollOffset - interaction.originOffset) / pixelsPerMinute)
        if var value = interaction.original {
            switch interaction.mode {
            case .move:
                value.setHorizontalPosition(horizontalPosition, at: positionUpdatedAt)
                if abs(delta) > 0.001,
                   let start = DayPlanningPolicy.snapped(Double(value.startMinute) + delta, within: 0...1439) {
                    value.startMinute = start
                }
            case .start:
                let end = value.endMinute
                if let start = DayPlanningPolicy.snapped(Double(value.startMinute) + delta,
                    within: max(0, end - 1440)...min(1439, end - 1)) {
                    value.startMinute = start
                    value.durationMinutes = end - start
                }
            case .end:
                if let end = DayPlanningPolicy.snapped(Double(value.endMinute) + delta,
                    within: (value.startMinute + 1)...(value.startMinute + 1440)) {
                    value.durationMinutes = end - value.startMinute
                }
            case .create: break
            }
            preview = value.isValid ? value : nil
        } else if let start = interaction.creationStart, let origin = interaction.creationOrigin {
            let minute = Double((pointerY + scrollOffset - 12) / pixelsPerMinute)
            createRange = TimelineCreationPolicy.range(from: origin, anchoredAt: start, to: minute,
                boundaries: creationBoundaries, pointsPerMinute: Double(pixelsPerMinute))
        }
    }

    private var creationBoundaries: [Int] {
        TimelineCreationPolicy.boundaries(in: store.schedules(on: day).compactMap { $0.interval(on: day) })
    }

    private func autoScroll() {
        guard !isReturningToList, let pointerY, interaction != nil || externalActive else { return }
        let direction: CGFloat = pointerY < 36 ? -1 : (pointerY > viewportHeight - 36 ? 1 : 0)
        guard direction != 0 else { return }
        let target = min(maximumScrollOffset, max(0, scrollOffset + direction * 12))
        scrollOffset = target
        position.scrollTo(y: target)
        updatePreview()
        if externalActive {
            externalMinute = min(1435, max(0, DayPlanningPolicy.snapped(Double((pointerY + target - 12) / pixelsPerMinute))))
        }
    }

    private func selectAdjacent(_ direction: Int) {
        let placements = DayPlanningPolicy.placements(displayed, on: day)
        guard !placements.isEmpty else { return }
        let current = placements.firstIndex { $0.id == selectedID } ?? (direction > 0 ? -1 : placements.count)
        let index = min(placements.count - 1, max(0, current + direction))
        selectedID = placements[index].id
        position.scrollTo(y: max(0, CGFloat(placements[index].interval.lowerBound) * pixelsPerMinute - 40))
    }

    private func locate() {
        let minute = DayPlanningPolicy.initialScrollMinute(schedules: store.schedules, on: day, now: now)
        let target = min(CGFloat(minute) * pixelsPerMinute,
                         maximumScrollOffset)
        scrollOffset = target
        position.scrollTo(y: target)
    }

    private func applyInitialPositionIfReady() {
        guard needsInitialPosition, isViewportReady, !store.isInitialLoading else { return }
        // ScrollPosition needs the laid-out viewport, and launch data can
        // arrive afterwards. Only locate once, so edits don't move the user.
        needsInitialPosition = false
        restorePositionOrLocate()
    }

    private func restorePositionOrLocate() {
        guard let restoredScrollMinute else {
            locate()
            return
        }
        let target = max(0, restoredScrollMinute * pixelsPerMinute)
        scrollOffset = target
        position.scrollTo(y: target)
    }
    private func cancelExternal() {
        pointerX = nil
        externalActive = false; externalTodoID = nil; externalMinute = nil; pointerY = nil; activityChanged(pendingDrop != nil || interaction != nil)
    }
    private func cancel() {
        pointerX = nil
        pendingDrop = nil; interaction = nil; preview = nil; createRange = nil; pointerY = nil
        externalMinute = nil; externalTodoID = nil; externalActive = false; activityChanged(false)
    }
}

private struct TodayTimelineViewport: Equatable {
    var offset: CGFloat
    var height: CGFloat
    var maximumOffset: CGFloat
}

struct TimelineControlScrollMonitor: NSViewRepresentable {
    var zoom: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> ControlScrollView {
        let view = ControlScrollView()
        view.zoom = zoom
        return view
    }

    func updateNSView(_ nsView: ControlScrollView, context: Context) {
        nsView.zoom = zoom
    }

    static func dismantleNSView(_ nsView: ControlScrollView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class ControlScrollView: NSView {
        var zoom: ((CGFloat, Bool) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func updateMonitor() {
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaY) > 0.01 else { return event }
                self.zoom?(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct TimelineViewport: Equatable {
    var offset: CGFloat
    var height: CGFloat
}

struct PlanningDropDelegate: DropDelegate {
    var isValidLocation: (CGPoint) -> Bool
    var enter: (CGPoint) -> Void
    var update: (CGPoint) -> Void
    var identify: (UUID) -> Void
    var exit: () -> Void
    var prepare: (CGPoint) -> @MainActor @Sendable (UUID?) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.url]) }
    func dropEntered(info: DropInfo) {
        enter(info.location)
        guard let provider = info.itemProviders(for: [.url]).first else { return }
        PlanningTodoTransfer.loadID(from: provider) { id in
            guard let id else { return }
            DispatchQueue.main.async { identify(id) }
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info.location)
        return DropProposal(operation: isValidLocation(info.location) ? .copy : .forbidden)
    }
    func dropExited(info: DropInfo) { exit() }
    func performDrop(info: DropInfo) -> Bool {
        guard isValidLocation(info.location), let provider = info.itemProviders(for: [.url]).first else { exit(); return false }
        let location = info.location
        let accept = prepare(location)
        PlanningTodoTransfer.loadID(from: provider) { id in
            DispatchQueue.main.async { accept(id) }
        }
        return true
    }
}
