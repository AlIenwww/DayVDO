import AppKit
import Combine
import SwiftUI

@MainActor
final class CalendarWeekPresentationCache: ObservableObject {
    struct Key: Equatable {
        var week: LocalDay
        var revision: UInt64
        var showCompleted: Bool
    }

    struct Snapshot {
        var schedulesByID: [UUID: DaySchedule]
        var placementsByDay: [LocalDay: [DayPlanningPolicy.Placement]]
    }

    private var key: Key?
    private var snapshot: Snapshot?

    func value(
        for key: Key,
        schedules: [DaySchedule],
        preview: DaySchedule?,
        isCompletedTodo: (UUID) -> Bool
    ) -> Snapshot {
        if preview == nil, self.key == key, let snapshot { return snapshot }

        let visible = schedules.compactMap { schedule -> DaySchedule? in
            let current = schedule.id == preview?.id ? (preview ?? schedule) : schedule
            let lastDay = current.startDay.adding(days: (current.endMinute - 1) / 1440)
            guard current.startDay <= key.week.adding(days: 6), lastDay >= key.week else { return nil }
            if !key.showCompleted, let id = current.todoID, isCompletedTodo(id) {
                return nil
            }
            return current
        }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var placements: [LocalDay: [DayPlanningPolicy.Placement]] = [:]
        for offset in 0..<7 {
            let day = key.week.adding(days: offset)
            placements[day] = DayPlanningPolicy.placements(visible, on: day)
        }
        let result = Snapshot(schedulesByID: byID, placementsByDay: placements)
        if preview == nil {
            self.key = key
            snapshot = result
        }
        return result
    }
}

struct CalendarWeekTimeline: View {
    @EnvironmentObject private var store: TodoStore
    let week: LocalDay
    @Binding var hourHeight: CGFloat
    @Binding var scrollMinute: CGFloat?
    let presentationCache: CalendarWeekPresentationCache
    var editTodo: (TodoItem) -> Void
    @State private var hasRestoredScroll = false
    @State private var now = Date.now
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var position = ScrollPosition()
    @State private var initialScrollMinute: CGFloat
    @State private var offset: CGFloat = 0
    @State private var size = CGSize.zero
    @State private var drag: Interaction?
    @State private var preview: DaySchedule?
    @State private var creation: Creation?
    @State private var suppressed = false
    @State private var draft: DaySchedule?
    @State private var presentation: SchedulePopoverRequest?
    @State private var selectedID: UUID?
    @State private var zoomAnchor: TimelineZoomAnchor?
    @State private var zoomTarget: CGFloat?
    @State private var lastMagnification: CGFloat = 1
    @State private var magnifying = false
    private let gutter: CGFloat = 54
    private var ppm: CGFloat { hourHeight / 60 }

    init(week: LocalDay, hourHeight: Binding<CGFloat>, scrollMinute: Binding<CGFloat?>,
         presentationCache: CalendarWeekPresentationCache, editTodo: @escaping (TodoItem) -> Void) {
        self.week = week
        _hourHeight = hourHeight
        _scrollMinute = scrollMinute
        self.presentationCache = presentationCache
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
    }
    private struct Creation { var day: LocalDay; var range: Range<Int> }
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                timeline(width: geometry.size.width)
                    .frame(height: hourHeight * 24 + 24)
            }
            .scrollPosition($position)
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
                if hasRestoredScroll { scrollMinute = value / ppm }
            }
            .onAppear {
                size = geometry.size
            }
            .onChange(of: geometry.size) { _, value in
                if drag != nil { cancel() }
                size = value
            }
            .background(CalendarInteractionMonitor(active: drag != nil || suppressed,
                cancel: cancel, release: { suppressed = false; clearDrag() }))
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
                    hourHeight = TimelineZoomPolicy.nextFrame(current: hourHeight, target: target)
                    position.scrollTo(y: TimelineZoomPolicy.scrollOffset(keeping: anchor, hourHeight: hourHeight, viewportHeight: size.height))
                    if hourHeight == target && !magnifying { zoomTarget = nil; zoomAnchor = nil }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }
        .coordinateSpace(name: "weekTimeViewport")
        .popover(item: $draft) { schedule in
            ScheduleEditorView(schedule: schedule, editTodo: editTodo)
        }
        .popover(item: $presentation) { request in
            if let schedule = store.schedules.first(where: { $0.id == request.scheduleID }) {
                SchedulePopoverView(schedule: schedule, startsEditing: request.mode == .editor,
                    editTodo: { item in presentation = nil; DispatchQueue.main.async { editTodo(item) } },
                    close: { presentation = nil })
            }
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: week) { _, _ in clearDrag(); suppressed = false; presentation = nil; draft = nil }
        .onDisappear { clearDrag() }
    }

    private func timeline(width: CGFloat) -> some View {
        let columnWidth = max(1, (width - gutter) / 7)
        let presentation = presentationCache.value(
            for: .init(
                week: week,
                revision: store.contentRevision,
                showCompleted: store.settings.showCompleted
            ),
            schedules: store.schedules,
            preview: preview,
            isCompletedTodo: { store.item(withID: $0)?.isCompleted == true }
        )
        return ZStack(alignment: .topLeading) {
            grid(width: width)
            Color.clear.contentShape(Rectangle())
                .frame(width: max(1, width - gutter), height: hourHeight * 24)
                .offset(x: gutter, y: 12)
                .gesture(gesture(nil, mode: .move))
            ForEach(0..<7, id: \.self) { column in
                let day = week.adding(days: column)
                let placements = presentation.placementsByDay[day] ?? []
                ForEach(placements) { placement in
                    if let schedule = presentation.schedulesByID[placement.id] {
                        block(schedule, placement: placement, day: day)
                            .frame(width: max(1, columnWidth / CGFloat(placement.columnCount) - 3),
                                   height: CGFloat(placement.interval.count) * ppm)
                            .offset(x: gutter + CGFloat(column) * columnWidth + CGFloat(placement.column) * columnWidth / CGFloat(placement.columnCount) + 1,
                                    y: 12 + CGFloat(placement.interval.lowerBound) * ppm)
                    }
                }
            }
            if let creation {
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor))
                    .frame(width: columnWidth - 3, height: CGFloat(creation.range.count) * ppm)
                    .offset(x: gutter + CGFloat(week.distance(to: creation.day)) * columnWidth + 1,
                            y: 12 + CGFloat(creation.range.lowerBound) * ppm)
                    .allowsHitTesting(false)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let today = LocalDay(context.date)
                if (week...week.adding(days: 6)).contains(today) {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                    let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    Rectangle().fill(.red).frame(width: columnWidth, height: 1)
                        .offset(x: gutter + CGFloat(week.distance(to: today)) * columnWidth, y: 12 + CGFloat(minute) * ppm)
                }
            }.allowsHitTesting(false)
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
            ForEach(0..<24, id: \.self) { hour in
                Text(SchedulePresentation.clock(hour * 60)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary).frame(width: gutter - 8, alignment: .trailing)
                    .offset(y: 5 + CGFloat(hour) * hourHeight)
            }
        }.allowsHitTesting(false)
    }

    private func block(_ schedule: DaySchedule, placement: DayPlanningPolicy.Placement, day: LocalDay) -> some View {
        let todo = store.item(withID: schedule.todoID)
        let color: Color = todo?.isCompleted == true ? .secondary : todo.map { store.tag(withID: $0.tagID)?.color.color ?? .accentColor } ?? .secondary
        let height = CGFloat(placement.interval.count) * ppm
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let inProgress = DayPlanningPolicy.isInProgress(placement,
            at: (components.hour ?? 0) * 60 + (components.minute ?? 0), onCurrentDay: day == LocalDay(now))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: min(5, height / 2)).fill(color.opacity(inProgress ? 0.20 : 0.14))
            if inProgress {
                RoundedRectangle(cornerRadius: min(5, height / 2)).fill(Color.red.opacity(0.055))
                Capsule().fill(.red).frame(width: 3, height: max(4, height - 6)).padding(.leading, 3).padding(.top, 3)
            }
            RoundedRectangle(cornerRadius: min(5, height / 2)).stroke(color.opacity(selectedID == schedule.id ? 0.9 : 0.35), lineWidth: selectedID == schedule.id ? 2 : 1)
            if height >= 14 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        if let todo, height >= 24 {
                            Button { store.toggle(todo) } label: { TodoStatusIcon(status: todo.status) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.string(todo.isCompleted ? "标记为未完成" : "标记为已完成"))
                        }
                        if schedule.startDay != day || schedule.endMinute > 1440 {
                            Image(systemName: schedule.startDay != day ? "arrow.turn.down.right" : "arrow.turn.up.right")
                        }
                        Text(SchedulePresentation.title(schedule, store: store)).font(.caption.weight(.medium))
                            .strikethrough(todo?.isCompleted == true).lineLimit(1)
                    }
                    if height >= 40 { Text(SchedulePresentation.time(schedule)).font(.caption2).lineLimit(1) }
                    if height >= 57 && (schedule.startDay != day || schedule.endMinute > 1440) {
                        Text(L10n.string(schedule.startDay != day ? "从前一天延续" : "延续至次日")).font(.caption2).lineLimit(1)
                    }
                }.padding(.horizontal, 5).padding(.vertical, height >= 24 ? 4 : 0).foregroundStyle(color)
            }
        }
        .clipped().contentShape(Rectangle())
        .gesture(gesture(schedule, mode: .move))
        .onTapGesture(count: 2) { selectedID = schedule.id; presentation = .editor(schedule.id) }
        .onTapGesture { selectedID = schedule.id; presentation = .details(schedule.id) }
        .overlay(alignment: .top) { if schedule.startDay == day { handle(schedule, mode: .start, height: height) } }
        .overlay(alignment: .bottom) {
            if schedule.endMinute - schedule.startDay.distance(to: day) * 1440 <= 1440 { handle(schedule, mode: .end, height: height) }
        }
        .contextMenu {
            Button(L10n.string("编辑安排")) { presentation = .editor(schedule.id) }
            Button(L10n.string("移除安排"), role: .destructive) { store.deleteSchedule(schedule.id) }
        }
    }

    private func handle(_ schedule: DaySchedule, mode: WeekSchedulePolicy.Mode, height: CGFloat) -> some View {
        Color.clear.frame(height: min(6, height / 3)).contentShape(Rectangle())
            .gesture(gesture(schedule, mode: mode))
            .onHover { if $0 { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() } }
            .accessibilityLabel(L10n.string(mode == .start ? "调整开始时间" : "调整结束时间"))
    }

    private func column(at point: CGPoint) -> Int? {
        guard point.x >= gutter, point.x < size.width, point.y >= 0, point.y < size.height else { return nil }
        return min(6, Int((point.x - gutter) / max(1, (size.width - gutter) / 7)))
    }

    private func gesture(_ original: DaySchedule?, mode: WeekSchedulePolicy.Mode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("weekTimeViewport"))
            .onChanged { value in
                guard !suppressed else { return }
                if drag == nil, let column = column(at: value.startLocation) {
                    presentation = nil
                    selectedID = original?.id
                    let start = DayPlanningPolicy.snapped(Double((value.startLocation.y + offset - 12) / ppm), within: 0...1435) ?? 0
                    drag = Interaction(original: original, mode: mode, column: column,
                        originY: value.startLocation.y, originOffset: offset, creationStart: start)
                }
                guard let drag, let targetColumn = column(at: value.location) else { return }
                let delta = Double((value.location.y - drag.originY + offset - drag.originOffset) / ppm)
                if let schedule = drag.original {
                    preview = WeekSchedulePolicy.adjusted(schedule, mode: drag.mode,
                        dayDelta: targetColumn - drag.column, minuteDelta: delta)
                } else {
                    let end = min(1440, max(0, DayPlanningPolicy.snapped(Double(drag.creationStart) + delta)))
                    let lower = min(drag.creationStart, end)
                    creation = Creation(day: week.adding(days: drag.column), range: lower..<max(lower + 5, max(drag.creationStart, end)))
                }
            }
            .onEnded { value in
                defer { clearDrag() }
                guard !suppressed, column(at: value.location) != nil else { return }
                if let preview, let original = drag?.original, preview != original,
                   store.schedules.first(where: { $0.id == original.id }) == original {
                    _ = store.upsertSchedule(preview)
                }
                else if let creation {
                    draft = DaySchedule(startDay: creation.day, startMinute: creation.range.lowerBound,
                        durationMinutes: creation.range.count, content: .independent(title: "", notes: ""))
                }
            }
    }

    private func cancel() { suppressed = true; clearDrag() }
    private func clearDrag() {
        drag = nil; preview = nil; creation = nil
    }
    private func beginZoom() {
        guard drag == nil else { return }
        if zoomAnchor == nil { zoomAnchor = TimelineZoomPolicy.anchor(scrollOffset: offset, viewportHeight: size.height, hourHeight: hourHeight) }
    }
}
