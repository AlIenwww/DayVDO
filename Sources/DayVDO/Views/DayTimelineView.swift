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

struct DayTimelineView: View {
    @EnvironmentObject private var store: TodoStore
    let day: LocalDay
    @Binding var hourHeight: CGFloat
    let now: Date
    var obscuredWidth: CGFloat = 0
    @Binding var presentation: SchedulePopoverRequest?
    var create: (Int, Int) -> Void
    var dropTodo: (UUID, Int) -> Void
    var editTodo: (TodoItem) -> Void
    var activityChanged: (Bool) -> Void

    @State private var position = ScrollPosition(y: 0)
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 400
    @State private var viewportWidth: CGFloat = 400
    @State private var selectedID: UUID?
    @State private var magnificationBase: CGFloat?
    @State private var magnificationAnchor: TimelineZoomAnchor?
    @State private var zoomTarget: CGFloat?
    @State private var previousMagnification: CGFloat = 1
    @State private var interaction: Interaction?
    @State private var preview: DaySchedule?
    @State private var createRange: Range<Int>?
    @State private var pointerY: CGFloat?
    @State private var externalTodoID: UUID?
    @State private var externalMinute: Int?
    @State private var externalActive = false
    @State private var pendingDrop: UUID?
    @State private var cancellation = TimelineDragCancellation()
    @FocusState private var isFocused: Bool
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let zoomTicker = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private let gutter: CGFloat = 54

    private struct Interaction {
        var original: DaySchedule?
        var mode: Mode
        var originY: CGFloat
        var originOffset: CGFloat
    }
    private enum Mode { case move, start, end, create }
    private var pixelsPerMinute: CGFloat { hourHeight / 60 }
    private var currentMinute: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
    private var displayed: [DaySchedule] {
        store.schedules(on: day).map { $0.id == preview?.id ? preview! : $0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let placements = DayPlanningPolicy.placements(displayed, on: day)
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    grid(width: geometry.size.width)
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: max(1, geometry.size.width - gutter), height: hourHeight * 24)
                        .offset(x: gutter)
                        .gesture(creationGesture)
                    if day == LocalDay(now) {
                        let lineY = CGFloat(currentMinute) * pixelsPerMinute
                        Rectangle()
                            .fill(.red)
                            .frame(width: max(1, geometry.size.width - gutter), height: 1)
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
                        .frame(width: max(1, geometry.size.width - gutter), height: min(180, viewportHeight))
                        .offset(x: gutter)
                        .allowsHitTesting(false)
                    }
                    ForEach(placements) { placement in
                        if let schedule = displayed.first(where: { $0.id == placement.id }) {
                            scheduleBlock(schedule, placement: placement, width: geometry.size.width)
                        }
                    }
                    if let range = createRange { previewBand(range, width: geometry.size.width) }
                    if let minute = externalMinute {
                        previewBand(minute..<(minute + externalDuration), width: geometry.size.width)
                    }
                    if day == LocalDay(now) {
                        let lineY = CGFloat(currentMinute) * pixelsPerMinute
                        Text(SchedulePresentation.clock(currentMinute))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(width: gutter - 8, alignment: .trailing)
                            .offset(y: max(0, min(hourHeight * 24 - 14, lineY - 7)))
                            .allowsHitTesting(false)
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                            .offset(x: gutter - 3, y: lineY - 3)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geometry.size.width, height: hourHeight * 24, alignment: .topLeading)
                .padding(.vertical, 12)

            }
            .scrollPosition($position)
            .popover(
                item: $presentation,
                attachmentAnchor: .point(popoverAttachmentPoint(
                    placements: placements,
                    width: geometry.size.width,
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
            .onScrollGeometryChange(for: TimelineViewport.self) { value in
                TimelineViewport(offset: value.contentOffset.y, height: value.containerSize.height)
            } action: { _, value in
                scrollOffset = value.offset
                viewportHeight = value.height
            }
            .onAppear { viewportWidth = geometry.size.width; locate() }
            .onChange(of: geometry.size.width) { _, width in viewportWidth = width }
            .onDisappear {
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
                locate()
            }
            .onChange(of: displayed) { _, latest in
                guard let request = presentation else { return }
                if !DayPlanningPolicy.placements(latest, on: day)
                    .contains(where: { $0.id == request.scheduleID }) {
                    presentation = nil
                    if selectedID == request.scheduleID { selectedID = nil }
                }
            }
            .onChange(of: scrollOffset) { _, _ in dismissOffscreenPopover() }
            .onReceive(ticker) { _ in
                finishCancellationIfReleased()
                autoScroll()
            }
            .onReceive(zoomTicker) { _ in advanceZoom() }
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
            .background {
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
            }
            .focusable().focusEffectDisabled().focused($isFocused)
            .onKeyPress(.escape) {
                cancellation.cancel(isDragging: interaction != nil)
                cancel()
                activityChanged(cancellation.isSuppressed)
                return .handled
            }
            .onDeleteCommand {
                guard isFocused, let id = selectedID else { return }
                if presentation?.scheduleID == id { presentation = nil }
                store.deleteSchedule(id); selectedID = nil
            }
            .onKeyPress(.upArrow) { selectAdjacent(-1); return .handled }
            .onKeyPress(.downArrow) { selectAdjacent(1); return .handled }
            .onKeyPress(.space) {
                guard let schedule = store.schedules.first(where: { $0.id == selectedID }),
                      let todo = store.items.first(where: { $0.id == schedule.todoID }) else { return .ignored }
                store.toggle(todo); return .handled
            }
            .onKeyPress(.return) {
                guard let selected = store.schedules.first(where: { $0.id == selectedID }) else { return .ignored }
                showSchedule(selected.id, mode: .editor); return .handled
            }

        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            if let dragTimeLabel, let pointerY {
                Text(dragTimeLabel)
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
                activityChanged(true)
                pointerY = location.y
                externalMinute = dropMinute(at: location)
            },
            update: { location in
                // SwiftUI can deliver a trailing update after performDrop. It must
                // not recreate a hover preview or keep the page busy after saving.
                guard externalActive else { return }
                pointerY = location.y
                externalMinute = dropMinute(at: location)
            },
            identify: { id in if externalActive { externalTodoID = id } },
            exit: { cancelExternal() },
            prepare: { location in
                let minute = dropMinute(at: location)
                let token = UUID()
                pendingDrop = token
                externalActive = false
                pointerY = nil
                externalMinute = nil
                externalTodoID = nil
                activityChanged(true)
                return { id in
                    guard pendingDrop == token else { return }
                    defer { pendingDrop = nil; activityChanged(interaction != nil || externalActive) }
                    if let id { dropTodo(id, minute) }
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
                if half.isMultiple(of: 2) {
                    Text(String(format: "%02d:00", half / 2))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: gutter - 8, alignment: .trailing).offset(y: y - 7)
                }
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
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(color.opacity(isInProgress ? 0.20 : 0.14))
            if isInProgress {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.red.opacity(0.055))
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: max(4, height - 6))
                    .padding(.leading, 3)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color.opacity(selectedID == schedule.id ? 0.9 : 0.35), lineWidth: selectedID == schedule.id ? 2 : 1)
            if height >= 14 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let todo, height >= 24 {
                            Button { store.toggle(todo) } label: {
                                TodoStatusIcon(status: todo.status)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(L10n.string(complete ? "标记为未完成" : "标记为已完成"))
                        }
                        if schedule.startDay != day || schedule.endMinute > 1440 {
                            Image(systemName: schedule.startDay != day ? "arrow.turn.down.right" : "arrow.turn.up.right")
                                .accessibilityLabel(L10n.string(schedule.startDay != day ? "从前一天延续" : "延续至次日"))
                        }
                        Text(SchedulePresentation.title(schedule, store: store))
                            .font(.caption.weight(.medium)).strikethrough(complete).lineLimit(1)
                    }
                    if height >= 40 {
                        Text(SchedulePresentation.time(schedule)).font(.caption2.monospacedDigit()).lineLimit(1)
                    }
                    if height >= 57 && (schedule.startDay != day || schedule.endMinute > 1440) {
                        Text(L10n.string(schedule.startDay != day ? "从前一天延续" : "延续至次日"))
                            .font(.caption2).lineLimit(1)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, height >= 24 ? 4 : 0)
                .foregroundStyle(color)
            }
        }
        .frame(width: max(1, columnWidth - 3), height: height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(blockGesture(schedule, mode: .move))
        .onTapGesture(count: 2) {
            showSchedule(schedule.id, mode: .editor)
        }
        .onTapGesture {
            showSchedule(schedule.id, mode: .details)
        }
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
        .accessibilityLabel(
            SchedulePresentation.title(schedule, store: store)
                + ", " + SchedulePresentation.time(schedule)
                + (isInProgress ? ", " + L10n.string("正在进行") : "")
        )
        .accessibilityAction {
            showSchedule(schedule.id, mode: .details)
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
        }
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
            x: min(0.98, max(0.02, x / max(1, width))),
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

    private func previewBand(_ range: Range<Int>, width: CGFloat) -> some View {
        Rectangle().fill(Color.accentColor.opacity(0.15))
            .frame(width: max(1, width - gutter - 8), height: CGFloat(min(1440, range.upperBound) - range.lowerBound) * pixelsPerMinute)
            .offset(x: gutter, y: CGFloat(range.lowerBound) * pixelsPerMinute)
            .allowsHitTesting(false)
    }

    private var creationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("planningViewport"))
            .onChanged { value in
                guard !cancellation.isSuppressed else { return }
                if interaction == nil {
                    interaction = Interaction(mode: .create, originY: value.startLocation.y, originOffset: scrollOffset)
                    activityChanged(true); isFocused = true
                }
                pointerY = value.location.y
                updatePreview()
            }
            .onEnded { value in
                defer { finishGesture() }
                guard !cancellation.isSuppressed, validRelease(value.location), let interaction else { return }
                let start = min(1435, max(0, DayPlanningPolicy.snapped(Double((interaction.originY + interaction.originOffset - 12) / pixelsPerMinute))))
                if abs(value.translation.height) < 4 { create(start, 30) }
                else if let range = createRange { create(range.lowerBound, range.count) }
            }
    }

    private func blockGesture(_ schedule: DaySchedule, mode: Mode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("planningViewport"))
            .onChanged { value in
                guard !cancellation.isSuppressed else { return }
                if interaction == nil {
                    interaction = Interaction(original: schedule, mode: mode, originY: value.startLocation.y, originOffset: scrollOffset)
                    selectedID = schedule.id; isFocused = true; activityChanged(true)
                }
                pointerY = value.location.y
                updatePreview()
            }
            .onEnded { value in
                if !cancellation.isSuppressed, validRelease(value.location), let preview { store.upsertSchedule(preview) }
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

    private func updatePreview() {
        guard let interaction, let pointerY else { return }
        let delta = Double((pointerY - interaction.originY + scrollOffset - interaction.originOffset) / pixelsPerMinute)
        if var value = interaction.original {
            switch interaction.mode {
            case .move:
                if let start = DayPlanningPolicy.snapped(Double(value.startMinute) + delta, within: 0...1439) {
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
        } else {
            let origin = min(1435, max(0, DayPlanningPolicy.snapped(Double((interaction.originY + interaction.originOffset - 12) / pixelsPerMinute))))
            let end = min(1440, max(0, DayPlanningPolicy.snapped(Double(origin) + delta)))
            createRange = min(origin, end)..<max(min(origin, end) + 5, max(origin, end))
        }
    }

    private func autoScroll() {
        guard let pointerY, interaction != nil || externalActive else { return }
        let direction: CGFloat = pointerY < 36 ? -1 : (pointerY > viewportHeight - 36 ? 1 : 0)
        guard direction != 0 else { return }
        let target = min(max(0, hourHeight * 24 + 24 - viewportHeight), max(0, scrollOffset + direction * 12))
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
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = day == LocalDay(now) ? max(0, (components.hour ?? 0) * 60 + (components.minute ?? 0) - 60) : 480
        position.scrollTo(y: CGFloat(minute) * pixelsPerMinute)
    }
    private func cancelExternal() {
        externalActive = false; externalTodoID = nil; externalMinute = nil; pointerY = nil; activityChanged(pendingDrop != nil || interaction != nil)
    }
    private func cancel() {
        pendingDrop = nil; interaction = nil; preview = nil; createRange = nil; pointerY = nil
        externalMinute = nil; externalTodoID = nil; externalActive = false; activityChanged(false)
    }
}

private struct TimelineControlScrollMonitor: NSViewRepresentable {
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

private struct PlanningDropDelegate: DropDelegate {
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
