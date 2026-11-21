import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct CalendarWeekTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: TodoStore
    let week: LocalDay
    let visibility: TodoFilterContext
    @Binding var hourHeight: CGFloat
    @Binding var scrollMinute: CGFloat?
    @ObservedObject var presentationCache: CalendarWeekPresentationCache
    let isActive: Bool
    var editTodo: (TodoItem) -> Void
    @State private var hasRestoredScroll = false
    @State private var now = Date.now
    @State private var position = ScrollPosition()
    @State private var initialScrollMinute: CGFloat
    @State private var offset: CGFloat = 0
    @State private var size = CGSize.zero
    @State private var drag: Interaction?
    @State private var dragAnchor = CalendarWeekDragAnchor.AnchorView()
    @State private var preview: DaySchedule?
    @StateObject private var previewUpdates = FrameUpdateScheduler()
    @Namespace private var dragPositions
    @State private var creation: Creation?
    @State private var draftID = UUID()
    @State private var positionUpdatedAt = Date.now
    @State private var externalLocation: CGPoint?
    @State private var externalTodoID: UUID?
    @State private var pendingDrop: UUID?
    @State private var pendingSchedule: DaySchedule?
    @State private var suppressed = false
    @State private var draft: DaySchedule?
    @State private var presentation: SchedulePopoverRequest?
    @Environment(\.lessonSession) private var guide
    @State private var selectedID: UUID?
    @State private var creationAnchor = CGPoint.zero
    @State private var zoomAnchor: TimelineZoomAnchor?
    @State private var zoomTarget: CGFloat?
    @State private var lastMagnification: CGFloat = 1
    @State private var magnifying = false
    private let gutter: CGFloat
    private let synchronizesScrolling: Bool
    private var ppm: CGFloat { hourHeight / 60 }

    init(week: LocalDay, visibility: TodoFilterContext, hourHeight: Binding<CGFloat>, scrollMinute: Binding<CGFloat?>,
         presentationCache: CalendarWeekPresentationCache, isActive: Bool = true,
         gutter: CGFloat = 54, synchronizesScrolling: Bool = false,
         editTodo: @escaping (TodoItem) -> Void) {
        self.week = week
        self.visibility = visibility
        _hourHeight = hourHeight
        _scrollMinute = scrollMinute
        self.presentationCache = presentationCache
        self.isActive = isActive
        self.gutter = gutter
        self.synchronizesScrolling = synchronizesScrolling
        self.editTodo = editTodo
        _initialScrollMinute = State(initialValue: scrollMinute.wrappedValue ?? 480)
    }

    private struct Interaction {
        var original: DaySchedule?
        var mode: WeekSchedulePolicy.Mode
        var column: Int
        var originY: CGFloat
        var originOffset: CGFloat
        var creationStart: Int
        var creationOrigin: Double
    }
    private struct Creation { var day: LocalDay; var range: Range<Int>; var horizontalPosition: Double }
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                CalendarWeekTimelineContent(version: renderVersion(width: geometry.size.width)) {
                    timeline(width: geometry.size.width)
                }
                    .equatable()
                    .frame(height: hourHeight * 24 + 24)
            }
            .scrollPosition($position)
            .popover(item: $draft,
                     attachmentAnchor: .point(TimelinePopoverAnchor.point(at: creationAnchor, in: geometry.size)),
                     arrowEdge: .trailing) { schedule in
                ScheduleEditorView(schedule: schedule,
                    close: { draft = nil }, editTodo: editTodo)
            }
            .onDrop(of: [.url], delegate: dropDelegate)
            .defaultScrollAnchor(UnitPoint(x: 0, y: CalendarScrollPolicy.initialAnchor(
                offset: initialScrollMinute * ppm, contentHeight: hourHeight * 24 + 24,
                viewportHeight: geometry.size.height
            )), for: .initialOffset)
            .scrollDisabled(drag != nil || suppressed)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in
                offset = value
                if !hasRestoredScroll, geometry.size.height > 0 {
                    let target = min(max(0, initialScrollMinute * ppm),
                                     max(0, hourHeight * 24 + 24 - geometry.size.height))
                    if abs(value - target) <= 1 { hasRestoredScroll = true }
                }
                if hasRestoredScroll && isActive
                    && (scrollMinute.map { abs(value / ppm - $0) > 1 / ppm } ?? true) {
                    scrollMinute = value / ppm
                }
            }
            .onAppear {
                size = geometry.size
            }
            .onChange(of: scrollMinute) { _, minute in
                if synchronizesScrolling, let minute, abs(minute * ppm - offset) > 1 {
                    position.scrollTo(y: minute * ppm)
                }
            }
            .onChange(of: isActive) { _, active in
                if active, let scrollMinute {
                    position.scrollTo(y: scrollMinute * ppm)
                } else if !active && drag == nil {
                    selectedID = nil
                    clearDrag()
                    presentation = nil
                    draft = nil
                    pendingSchedule = nil
                }
            }
            .onChange(of: geometry.size) { _, value in
                if drag != nil { cancel() }
                size = value
            }
            .background(CalendarInteractionMonitor(active: drag != nil || suppressed || externalLocation != nil,
                cancel: cancel, release: {
                    suppressed = false
                    if drag != nil { clearDrag() }
                }, trackDrag: trackDrag, finishDrag: finishDrag))
            .background(CalendarWeekDragAnchor(view: dragAnchor))
            .background(ScheduleClickMonitor(acceptsClick: { point in
                isActive && column(at: point) != nil
            }) { location, count in
                guard count == 1, selectedID != nil, draft == nil, presentation == nil, !suppressed,
                      let column = column(at: location), dragSource(at: location, column: column).0 == nil else { return }
                selectedID = nil
            })
            .background(TimelineControlScrollMonitor { delta, precise in
                beginZoom()
                zoomTarget = TimelineZoomPolicy.clampedHourHeight((zoomTarget ?? hourHeight) + delta * (precise ? 0.8 : 8))
            })
            .simultaneousGesture(MagnificationGesture().onChanged { scale in
                guard drag == nil else { return }
                beginZoom(); magnifying = true
                zoomTarget = TimelineZoomPolicy.clampedHourHeight((zoomTarget ?? hourHeight) * scale / lastMagnification)
                lastMagnification = scale
            }.onEnded { _ in lastMagnification = 1; magnifying = false })
            .task(id: zoomTarget != nil) {
                guard zoomTarget != nil else { return }
                while !Task.isCancelled, let target = zoomTarget, let anchor = zoomAnchor {
                    hourHeight = !reduceMotion && store.settings.animates(.timelineZoom)
                        ? TimelineZoomPolicy.nextFrame(current: hourHeight, target: target) : target
                    position.scrollTo(y: TimelineZoomPolicy.scrollOffset(keeping: anchor, hourHeight: hourHeight, viewportHeight: size.height))
                    if hourHeight == target && !magnifying { zoomTarget = nil; zoomAnchor = nil }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }
        .coordinateSpace(name: "weekTimeViewport")
        .popover(item: $presentation) { request in
            if let schedule = store.schedule(withID: request.scheduleID) {
                SchedulePopoverView(schedule: schedule, startsEditing: request.mode == .editor,
                    showsCalendarStatus: true,
                    editTodo: { item in presentation = nil; DispatchQueue.main.async { editTodo(item) } },
                    close: { presentation = nil })
            }
        }
        .alert(L10n.string("已达到预计时长"), isPresented: Binding(
            get: { pendingSchedule != nil }, set: { if !$0 { pendingSchedule = nil } }
        )) {
            Button(L10n.string("继续安排")) {
                if let pendingSchedule { store.upsertSchedule(pendingSchedule) }
                pendingSchedule = nil
            }
            Button(L10n.string("取消"), role: .cancel) { pendingSchedule = nil }
        } message: {
            Text(L10n.string("这个待办已安排足够时间，仍要再添加一段吗？"))
        }
        .allowAppTerminationDuringDialog()
        .onReceive(AppClock.ticks) { now = $0 }
        .background(TimelineSelectionKeyMonitor(
            enabled: isActive && selectedID != nil && presentation == nil && draft == nil && drag == nil && !suppressed,
            delete: {
                guard let id = selectedID, store.canModify else { return }
                if store.deleteSchedule(id) { selectedID = nil }
            },
            clear: { selectedID = nil }
        ))
        .editorEscapeDismissal(enabled: isActive && draft != nil) { draft = nil }
        .editorReturnSubmission(enabled: isActive && (draft != nil || presentation?.mode == .editor)) {
            if let id = draft?.id ?? presentation?.scheduleID {
                NotificationCenter.default.post(name: .scheduleEditorSubmit, object: id)
            }
        }
        .onChange(of: week) { _, _ in clearDrag(); suppressed = false; presentation = nil; draft = nil; pendingSchedule = nil }
        .onChange(of: visibility) { _, _ in
            if NSEvent.pressedMouseButtons & 1 != 0 { cancel() }
            else { clearDrag(); suppressed = false }
            clearHiddenSelection()
        }
        .onChange(of: store.timelineContentRevision) { _, _ in clearHiddenSelection() }
        .background(FrameUpdateAnchor(scheduler: previewUpdates))
        .onDisappear { clearDrag() }
    }

    private var timelinePresentation: CalendarWeekPresentationCache.Snapshot {
        presentationCache.value(
            for: .init(
                week: week,
                revision: store.timelineContentRevision,
                visibility: visibility
            ),
            schedulesOnDay: { store.schedules(on: $0) },
            preview: activePreview,
            prioritizing: drag?.original != nil && drag?.mode != .move ? nil : activePreview?.id,
            todo: { store.item(withID: $0) }
        )
    }

    private func renderVersion(width: CGFloat) -> CalendarWeekTimelineRenderVersion {
        let time = Calendar.current.dateComponents([.hour, .minute], from: now)
        return CalendarWeekTimelineRenderVersion(week: week, revision: store.timelineContentRevision,
            visibility: visibility, width: width, hourHeight: hourHeight,
            selectedID: selectedID, preview: activePreview,
            prioritizing: drag?.original != nil && drag?.mode != .move ? nil : activePreview?.id,
            dragAnimation: store.settings.calendarDragAnimation(reduceMotion: reduceMotion),
            statusAnimation: store.settings.calendarTaskStatusAnimation(reduceMotion: reduceMotion),
            today: LocalDay(now), minute: (time.hour ?? 0) * 60 + (time.minute ?? 0),
            locale: L10n.locale.identifier)
    }

    private var activePreview: DaySchedule? {
        if let preview { return preview }
        if let preview = presentationCache.dragPreview { return preview }
        guard let creation else { return nil }
        return DaySchedule(id: draftID, startDay: creation.day, startMinute: creation.range.lowerBound,
            durationMinutes: creation.range.count, content: .independent(title: "", notes: ""),
            horizontalPosition: creation.horizontalPosition, horizontalPositionUpdatedAt: positionUpdatedAt)
    }

    private func creationBoundaries(on day: LocalDay) -> [Int] {
        TimelineCreationPolicy.boundaries(in: (timelinePresentation.placementsByDay[day] ?? [])
            .filter { $0.id != draftID }.map(\.interval))
    }

    private func timeline(width: CGFloat) -> some View {
        let columnWidth = max(1, (width - gutter) / 7)
        let presentation = timelinePresentation
        let preview = activePreview
        let dragAnimation = store.settings.calendarDragAnimation(reduceMotion: reduceMotion)
        let statusAnimation = store.settings.calendarTaskStatusAnimation(reduceMotion: reduceMotion)
        return ZStack(alignment: .topLeading) {
            grid(width: width)
            Color.clear.contentShape(Rectangle())
                .frame(width: max(1, width - gutter), height: hourHeight * 24 + 24)
                .offset(x: gutter)
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { column in
                    let day = week.adding(days: column)
                    let placements = presentation.placementsByDay[day] ?? []
                    let schedules = placements.compactMap { presentation.schedulesByID[$0.id] }
                    CalendarWeekDayContent(version: CalendarWeekDayVersion(day: day,
                        revision: store.timelineContentRevision, schedules: schedules, placements: placements,
                        width: columnWidth, hourHeight: hourHeight,
                        selectedID: schedules.contains(where: { $0.id == selectedID }) ? selectedID : nil,
                        draftID: draftID, minute: day == LocalDay(now) ? Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now) : nil,
                        locale: L10n.locale.identifier, dragAnimation: dragAnimation, statusAnimation: statusAnimation,
                        liftedID: dragAnimation == nil ? nil : preview?.id)) {
                        ForEach(placements) { placement in
                            if let schedule = presentation.schedulesByID[placement.id] {
                                let arrangementWidth = max(1, columnWidth - 2) / CGFloat(placement.columnCount)
                                positionedBlock(schedule, placement: placement, day: day,
                                    matchesDragPosition: dragAnimation != nil, statusAnimation: statusAnimation)
                                    .frame(width: arrangementWidth, height: CGFloat(placement.interval.count) * ppm)
                                    .shadow(color: .black.opacity(dragAnimation != nil && schedule.id == preview?.id ? 0.18 : 0),
                                            radius: 3, y: 1)
                                    .offset(x: gutter + CGFloat(column) * columnWidth + CGFloat(placement.column) * arrangementWidth + 1,
                                            y: 12 + CGFloat(placement.interval.lowerBound) * ppm)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .equatable()
                    .zIndex(preview?.interval(on: day) != nil ? 1 : 0)
                }
            }
            .animation(dragAnimation, value: preview)
            Group {
                let today = LocalDay(now)
                if (week...week.adding(days: 6)).contains(today) {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: now)
                    let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    Rectangle().fill(.red).frame(width: columnWidth, height: 1)
                        .offset(x: gutter + CGFloat(week.distance(to: today)) * columnWidth, y: 12 + CGFloat(minute) * ppm)
                }
            }.allowsHitTesting(false)
        }
    }

    private func positionedBlock(_ schedule: DaySchedule, placement: DayPlanningPolicy.Placement,
                                 day: LocalDay, matchesDragPosition: Bool, statusAnimation: Animation?) -> some View {
        let content = Group {
            if schedule.id == draftID {
                TimelineScheduleShape.shape(placement: placement, radius: 4)
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay(TimelineScheduleShape.shape(placement: placement, radius: 4).strokeBorder(Color.accentColor))
                    .allowsHitTesting(false)
            } else {
                block(schedule, placement: placement, day: day, statusAnimation: statusAnimation)
            }
        }
        return Group {
            if matchesDragPosition {
                content.matchedGeometryEffect(id: CalendarWeekScheduleFragment(id: schedule.id,
                    dayOffset: schedule.startDay.distance(to: day)), in: dragPositions, properties: .position)
            } else {
                content
            }
        }
    }

    private func grid(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for hour in 0...24 {
                    let y = 12 + CGFloat(hour) * hourHeight
                    path.move(to: CGPoint(x: gutter, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                }
                for column in 0...7 {
                    let x = gutter + CGFloat(column) * max(1, width - gutter) / 7
                    path.move(to: CGPoint(x: x, y: 12)); path.addLine(to: CGPoint(x: x, y: 12 + hourHeight * 24))
                }
            }.stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            ForEach(0..<(gutter > 0 ? 24 : 0), id: \.self) { hour in
                Text(SchedulePresentation.clock(hour * 60)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary).frame(width: gutter - 8, alignment: .trailing)
                    .offset(y: 5 + CGFloat(hour) * hourHeight)
            }
        }.allowsHitTesting(false)
    }

    private func block(_ schedule: DaySchedule, placement: DayPlanningPolicy.Placement, day: LocalDay,
                       statusAnimation: Animation?) -> some View {
        let todo = store.item(withID: schedule.todoID)
        let color: Color = todo?.isCompleted == true ? .secondary : todo.map { store.tag(withID: $0.tagID)?.color.color ?? .accentColor } ?? .secondary
        let height = CGFloat(placement.interval.count) * ppm
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let inProgress = DayPlanningPolicy.isInProgress(placement,
            at: (components.hour ?? 0) * 60 + (components.minute ?? 0), onCurrentDay: day == LocalDay(now))
        let shape = TimelineScheduleShape.shape(placement: placement, radius: min(5, height / 2))
        return ZStack(alignment: .topLeading) {
            shape.fill(color.opacity(0.14))
            if inProgress {
                Capsule().fill(.red).frame(width: 3, height: max(4, height - 6)).padding(.leading, 3).padding(.top, 3)
            }
            shape.strokeBorder(color.opacity(selectedID == schedule.id ? 0.9 : 0.35), lineWidth: selectedID == schedule.id ? 2 : 1)
            if height >= 14 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        if let todo, height >= 24 {
                            Button { store.toggle(todo) } label: {
                                CalendarTaskStatusIcon(status: todo.status, animates: statusAnimation != nil)
                            }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.string(todo.isCompleted ? "标记为未完成" : "标记为已完成"))
                        }
                        if schedule.startDay != day || schedule.endMinute > 1440 {
                            Image(systemName: schedule.startDay != day ? "arrow.turn.down.right" : "arrow.turn.up.right")
                        }
                        CalendarTaskStatusTitle(title: SchedulePresentation.title(schedule, store: store),
                            isCompleted: todo?.isCompleted == true).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    if height >= 40 { Text(SchedulePresentation.time(schedule)).font(.caption2).lineLimit(1) }
                    if height >= 57 && (schedule.startDay != day || schedule.endMinute > 1440) {
                        Text(L10n.string(schedule.startDay != day ? "从前一天延续" : "延续至次日")).font(.caption2).lineLimit(1)
                    }
                }.padding(.horizontal, 5).padding(.vertical, height >= 24 ? 4 : 0).foregroundStyle(color)
            }
        }
        .animation(statusAnimation, value: todo?.status)
        .clipped().contentShape(Rectangle())
        .guideTarget(.block(schedule.id))
        .focusable(guide != nil)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard guide != nil else { return .ignored }
            openDetails(schedule)
            return .handled
        }
        .accessibilityAction(named: L10n.string("查看详情")) { openDetails(schedule) }
        .onTapGesture(count: 2) { guide?.inspected(schedule.id); selectedID = schedule.id; presentation = .editor(schedule.id) }
        .onTapGesture {
            openDetails(schedule)
        }
        .overlay(alignment: .top) { if schedule.startDay == day { handle(mode: .start, height: height) } }
        .overlay(alignment: .bottom) {
            if schedule.endMinute - schedule.startDay.distance(to: day) * 1440 <= 1440 { handle(mode: .end, height: height) }
        }
        .contextMenu {
            Button(L10n.string("编辑安排")) { presentation = .editor(schedule.id) }
            if let todo { TodoStatusMenuItems(item: todo) }
            Button(L10n.string("移除安排"), role: .destructive) { store.deleteSchedule(schedule.id) }
        }
    }

    private func handle(mode: WeekSchedulePolicy.Mode, height: CGFloat) -> some View {
        Color.clear.frame(height: resizeHandleHeight(for: height)).contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() } }
            .accessibilityLabel(L10n.string(mode == .start ? "调整开始时间" : "调整结束时间"))
    }

    private func openDetails(_ schedule: DaySchedule) {
        selectedID = schedule.id
        presentation = schedule.todoID == nil ? nil : .details(schedule.id)
        guide?.inspected(schedule.id)
    }

    private func resizeHandleHeight(for height: CGFloat) -> CGFloat { min(6, height / 3) }

    private func column(at point: CGPoint) -> Int? {
        guard point.x >= gutter, point.x < size.width, point.y >= 0, point.y < size.height else { return nil }
        return min(6, Int((point.x - gutter) / max(1, (size.width - gutter) / 7)))
    }

    private func trackDrag(from origin: CGPoint, to location: CGPoint) {
        guard !suppressed, store.canModify, draft == nil else { return }
        if drag == nil {
            guard isActive, let column = column(at: origin), targetDay(at: origin) != nil else { return }
            let (original, mode) = dragSource(at: origin, column: column)
            draftID = UUID(); positionUpdatedAt = .now
            presentation = nil
            selectedID = original?.id
            let minute = Double((origin.y + offset - 12) / ppm)
            let start = TimelineCreationPolicy.startMinute(at: minute,
                boundaries: creationBoundaries(on: week.adding(days: column)), pointsPerMinute: Double(ppm))
            drag = Interaction(original: original, mode: mode, column: column,
                originY: origin.y, originOffset: offset, creationStart: start, creationOrigin: minute)
        }
        previewUpdates.submit { updateDrag(at: location) }
        if drag?.original != nil {
            dragAnchor.track(at: location, cancel: cancel) { location in
                previewUpdates.submit { updateDrag(at: location) }
            }
        }
    }

    private func finishDrag(at location: CGPoint) {
        guard let drag else { return }
        defer { clearDrag() }
        guard !suppressed, targetDay(at: location) != nil else { return }
        previewUpdates.cancel()
        updateDrag(at: location)
        if let original = drag.original {
            if let preview, preview != original, store.schedule(withID: original.id) == original {
                _ = store.upsertSchedule(preview)
            }
        } else if let creation {
            let schedule = DaySchedule(startDay: creation.day, startMinute: creation.range.lowerBound,
                durationMinutes: creation.range.count, content: .independent(title: "", notes: ""),
                horizontalPosition: creation.horizontalPosition, horizontalPositionUpdatedAt: .now)
            DispatchQueue.main.async {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                creationAnchor = location
                draft = schedule
            }
        }
    }

    private func dragSource(at point: CGPoint, column: Int) -> (DaySchedule?, WeekSchedulePolicy.Mode) {
        let day = week.adding(days: column)
        let presentation = timelinePresentation
        let columnWidth = max(1, (size.width - gutter) / 7)
        let y = point.y + offset - 12
        for placement in presentation.placementsByDay[day] ?? [] {
            let width = max(1, columnWidth - 2) / CGFloat(placement.columnCount)
            let x = gutter + CGFloat(column) * columnWidth + CGFloat(placement.column) * width + 1
            let top = CGFloat(placement.interval.lowerBound) * ppm
            let bottom = CGFloat(placement.interval.upperBound) * ppm
            guard point.x >= x, point.x < x + width, y >= top, y < bottom,
                  let schedule = presentation.schedulesByID[placement.id] else { continue }
            let handle = resizeHandleHeight(for: bottom - top)
            if schedule.startDay == day, y < top + handle { return (schedule, .start) }
            if schedule.endMinute - schedule.startDay.distance(to: day) * 1440 <= 1440,
               y >= bottom - handle { return (schedule, .end) }
            return (schedule, .move)
        }
        return (nil, .move)
    }

    private func horizontalPosition(at location: CGPoint, column: Int) -> Double {
        let width = max(1, (size.width - gutter) / 7)
        return DayPlanningPolicy.horizontalPosition(x: Double(location.x),
            minX: Double(gutter + CGFloat(column) * width), width: Double(width))
    }

    private func updateDrag(at location: CGPoint) {
        guard let drag, let targetDay = targetDay(at: location) else { return }
        let targetColumn = week.distance(to: targetDay)
        let delta = Double((location.y - drag.originY + offset - drag.originOffset) / ppm)
        if let schedule = drag.original {
            var value = WeekSchedulePolicy.adjusted(schedule, mode: drag.mode,
                dayDelta: targetColumn - drag.column, minuteDelta: delta)
            if drag.mode == .move {
                value.setHorizontalPosition(horizontalPosition(at: location, column: targetColumn), at: positionUpdatedAt)
            }
            if preview != value { preview = value }
            if presentationCache.dragPreview != value { presentationCache.dragPreview = value }
        } else {
            updateCreation(drag, at: location)
        }
    }

    private func targetDay(at location: CGPoint) -> LocalDay? {
        if dragAnchor.isInWeekViewport { return dragAnchor.day(at: location) }
        return column(at: location).map { week.adding(days: $0) }
    }

    private func updateCreation(_ drag: Interaction, at location: CGPoint) {
        let day = week.adding(days: drag.column)
        let minute = Double((location.y + offset - 12) / ppm)
        let movement = location.y - drag.originY + offset - drag.originOffset
        let range = abs(movement) < 4
            ? TimelineCreationPolicy.defaultRange(anchoredAt: drag.creationStart, duration: store.settings.defaultScheduleMinutes)
            : TimelineCreationPolicy.range(from: drag.creationOrigin, anchoredAt: drag.creationStart, to: minute,
                boundaries: creationBoundaries(on: day), pointsPerMinute: Double(ppm))
        creation = Creation(day: day, range: range,
            horizontalPosition: horizontalPosition(at: location, column: drag.column))
    }

    private var dropDelegate: PlanningDropDelegate {
        PlanningDropDelegate(
            isValidLocation: { column(at: $0) != nil && !suppressed },
            enter: { location in
                guard pendingDrop == nil, !suppressed else { return }
                draftID = UUID(); positionUpdatedAt = .now
                externalLocation = location
                updateExternalPreview()
            },
            update: { location in
                guard externalLocation != nil else { return }
                previewUpdates.submit {
                    guard externalLocation != nil else { return }
                    externalLocation = location
                    updateExternalPreview()
                }
            },
            identify: { id in
                guard externalLocation != nil else { return }
                externalTodoID = id
                updateExternalPreview()
            },
            exit: { previewUpdates.cancel(); externalLocation = nil; externalTodoID = nil; creation = nil },
            prepare: { location in
                previewUpdates.cancel()
                let targetColumn = column(at: location) ?? 0
                let day = week.adding(days: targetColumn)
                let minute = dropMinute(at: location)
                let horizontal = horizontalPosition(at: location, column: targetColumn)
                let token = UUID()
                pendingDrop = token
                externalLocation = nil; externalTodoID = nil; creation = nil
                return { id in
                    guard pendingDrop == token else { return }
                    defer { pendingDrop = nil }
                    guard let id, let todo = store.item(withID: id) else { return }
                    let scheduled = store.scheduledMinutes(for: id)
                    let schedule = DaySchedule(startDay: day, startMinute: minute,
                        durationMinutes: DayPlanningPolicy.defaultDuration(estimated: todo.estimatedMinutes, scheduled: scheduled, fallback: store.settings.defaultScheduleMinutes),
                        content: .todo(id), horizontalPosition: horizontal, horizontalPositionUpdatedAt: .now)
                    if let estimated = todo.estimatedMinutes, scheduled >= estimated { pendingSchedule = schedule }
                    else { store.upsertSchedule(schedule) }
                }
            }
        )
    }

    private func dropMinute(at location: CGPoint) -> Int {
        min(1435, max(0, DayPlanningPolicy.snapped(Double((location.y + offset - 12) / ppm))))
    }

    private func updateExternalPreview() {
        guard let location = externalLocation, let targetColumn = column(at: location) else { creation = nil; return }
        let todo = externalTodoID.flatMap { store.item(withID: $0) }
        let duration = DayPlanningPolicy.defaultDuration(estimated: todo?.estimatedMinutes,
            scheduled: externalTodoID.map { store.scheduledMinutes(for: $0) } ?? 0, fallback: store.settings.defaultScheduleMinutes)
        let minute = dropMinute(at: location)
        creation = Creation(day: week.adding(days: targetColumn), range: minute..<(minute + duration),
            horizontalPosition: horizontalPosition(at: location, column: targetColumn))
    }

    private func clearHiddenSelection() {
        func isVisible(_ id: UUID) -> Bool {
            guard let schedule = store.schedule(withID: id) else { return false }
            guard let todoID = schedule.todoID else { return true }
            return store.item(withID: todoID).map { visibility.includes($0) } == true
        }
        if let id = selectedID, !isVisible(id) { selectedID = nil }
        if let request = presentation, !isVisible(request.scheduleID) { presentation = nil }
    }

    private func cancel() { suppressed = true; clearDrag() }
    private func clearDrag() {
        previewUpdates.cancel()
        if let original = drag?.original, presentationCache.dragPreview?.id == original.id {
            presentationCache.dragPreview = nil
        }
        dragAnchor.endDrag()
        drag = nil; preview = nil; creation = nil
        externalLocation = nil; externalTodoID = nil; pendingDrop = nil
    }
    private func beginZoom() {
        guard drag == nil else { return }
        if zoomAnchor == nil { zoomAnchor = TimelineZoomPolicy.anchor(scrollOffset: offset, viewportHeight: size.height, hourHeight: hourHeight) }
    }
}

private struct CalendarWeekTimelineRenderVersion: Equatable, Sendable {
    var week: LocalDay
    var revision: UInt64
    var visibility: TodoFilterContext
    var width: CGFloat
    var hourHeight: CGFloat
    var selectedID: UUID?
    var preview: DaySchedule?
    var prioritizing: UUID?
    var dragAnimation: Animation?
    var statusAnimation: Animation?
    var today: LocalDay
    var minute: Int
    var locale: String
}

private struct CalendarWeekScheduleFragment: Hashable {
    var id: UUID
    var dayOffset: Int
}

/// Scrolling changes the clip origin, not the grid or its arrangement cards.
/// Keep that content stable while scroll synchronization updates the viewport.
private struct CalendarWeekTimelineContent<Content: View>: View, Equatable {
    nonisolated let version: CalendarWeekTimelineRenderVersion
    @ViewBuilder var content: () -> Content

    var body: some View { content() }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.version == rhs.version }
}

/// Only days whose cards or geometry changed need to rebuild during a shared drag.
private struct CalendarWeekDayVersion: Equatable, Sendable {
    var day: LocalDay
    var revision: UInt64
    var schedules: [DaySchedule]
    var placements: [DayPlanningPolicy.Placement]
    var width: CGFloat
    var hourHeight: CGFloat
    var selectedID: UUID?
    var draftID: UUID
    var minute: Int?
    var locale: String
    var dragAnimation: Animation?
    var statusAnimation: Animation?
    var liftedID: UUID?
}

private struct CalendarWeekDayContent<Content: View>: View, Equatable {
    nonisolated let version: CalendarWeekDayVersion
    @ViewBuilder var content: () -> Content
    // Each day's offsets are absolute against the timeline, never cumulative.
    var body: some View { ZStack(alignment: .topLeading) { content() } }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.version == rhs.version }
}
