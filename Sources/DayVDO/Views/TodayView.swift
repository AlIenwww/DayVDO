import AppKit
import Combine
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var selectedDay: LocalDay
    @Binding var hourHeight: CGFloat
    @Binding var timelineScrollMinute: CGFloat?
    @State private var now = Date.now
    @State private var previousToday = LocalDay(.now)
    @State private var isPickingDate = false
    @State private var showsTodoPanel = false
    @State private var scheduleDraft: DaySchedule?
    @State private var schedulePopover: SchedulePopoverRequest?
    @State private var queuedTodo: TodoItem?
    @State private var pending: PendingSchedule?
    @State private var timelineActive = false

    private struct PendingSchedule {
        var schedule: DaySchedule
    }
    private var isBusy: Bool {
        timelineActive || scheduleDraft != nil || schedulePopover != nil || pending != nil
            || editingItem != nil || isPickingDate
    }

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 720
            let panelWidth: CGFloat = narrow ? min(280, max(220, geometry.size.width * 0.55)) : 280
            // Both columns belong to the same native scroll backdrop. The list
            // stays fixed in the viewport and keeps its own scroll position.
            DayTimelineView(
                day: selectedDay,
                hourHeight: $hourHeight,
                restoredScrollMinute: $timelineScrollMinute,
                now: now,
                reservedTrailingWidth: narrow ? 0 : panelWidth + 1,
                obscuredWidth: narrow && showsTodoPanel ? panelWidth : 0,
                trailingPanel: !narrow || showsTodoPanel ? todoPanel : nil,
                trailingPanelWidth: panelWidth,
                creationDraft: $scheduleDraft,
                presentation: $schedulePopover,
                create: { minute, duration, horizontal in
                    scheduleDraft = DaySchedule(startDay: selectedDay, startMinute: minute,
                        durationMinutes: duration, content: .independent(title: "", notes: ""),
                        horizontalPosition: horizontal, horizontalPositionUpdatedAt: .now)
                },
                dropTodo: requestSchedule,
                editTodo: queueTodoForEditing,
                activityChanged: { timelineActive = $0 }
            )
            .pageTopBar {
                dateHeader(narrow: narrow)
            }
            .onChange(of: narrow) { _, value in if !value { showsTodoPanel = false } }
        }
        .navigationTitle(L10n.string("今日待办"))
        .onChange(of: scheduleDraft) { old, new in
            if old != nil && new == nil { finishPresentation() }
        }
        // Non-key popovers can forward Escape to their presenting window.
        .editorEscapeDismissal(
            enabled: (scheduleDraft != nil || schedulePopover != nil) && !isPickingDate && editingItem == nil
        ) {
            scheduleDraft = nil
            schedulePopover = nil
        }
        .alert(L10n.string("已达到预计时长"), isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        )) {
            Button(L10n.string("继续安排")) {
                guard let request = pending else { return }
                pending = nil
                store.upsertSchedule(request.schedule)
            }
            Button(L10n.string("取消"), role: .cancel) { pending = nil }
        } message: {
            Text(L10n.string("这个待办已安排足够时间，仍要再添加一段吗？"))
        }
        .onReceive(AppClock.refreshes) { _ in refreshClock() }
        .onChange(of: isBusy) { _, busy in if !busy { refreshClock() } }
    }

    private var todoPanel: PlanningTodoPanel {
        PlanningTodoPanel(
            day: selectedDay,
            today: LocalDay(now),
            edit: { editingItem = $0 }
        )
    }

    private func dateHeader(narrow: Bool) -> some View {
        HStack(spacing: 10) {
            Button { isPickingDate.toggle() } label: {
                HStack(spacing: 8) {
                    Text(selectedDay.date().formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)))
                        .font(.title3.bold())
                    Text(selectedDay.date().formatted(.dateTime.weekday(.wide).locale(L10n.locale)))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.string("选择日期"))
            .popover(isPresented: $isPickingDate) {
                BorderlessCalendarPicker(selection: Binding(
                    get: { selectedDay.date() },
                    set: { selectedDay = LocalDay($0); isPickingDate = false }
                ), startsOnMonday: store.settings.startWeekOnMonday)
                .fixedSize().padding(10)
            }
            Spacer(minLength: 0)
            Button(L10n.string("今天")) { selectedDay = LocalDay(.now) }
            Button { selectedDay = selectedDay.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                .help(L10n.string("前一天"))
            Button { selectedDay = selectedDay.adding(days: 1) } label: { Image(systemName: "chevron.right") }
                .help(L10n.string("后一天"))
            if narrow {
                Button { showsTodoPanel.toggle() } label: { Image(systemName: "list.bullet.rectangle.portrait") }
                    .help(L10n.string("待办事项"))
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func requestSchedule(_ id: UUID, at minute: Int, horizontalPosition: Double) {
        guard let todo = store.items.first(where: { $0.id == id }) else { return }
        let scheduled = store.scheduledMinutes(for: id)
        let duration = DayPlanningPolicy.defaultDuration(estimated: todo.estimatedMinutes, scheduled: scheduled)
        let schedule = DaySchedule(startDay: selectedDay, startMinute: minute,
                                   durationMinutes: duration, content: .todo(id),
                                   horizontalPosition: horizontalPosition, horizontalPositionUpdatedAt: .now)
        if let estimated = todo.estimatedMinutes, scheduled >= estimated {
            pending = PendingSchedule(schedule: schedule)
        } else {
            store.upsertSchedule(schedule)
        }
    }

    private func finishPresentation() {
        if let todo = queuedTodo { queuedTodo = nil; editingItem = todo }
        refreshClock()
    }

    private func queueTodoForEditing(_ todo: TodoItem) {
        queuedTodo = todo
        schedulePopover = nil
        scheduleDraft = nil
        DispatchQueue.main.async { finishPresentation() }
    }

    private func refreshClock() {
        now = .now
        guard !isBusy else { return }
        let today = LocalDay(now)
        selectedDay = DayPlanningPolicy.followedDay(selected: selectedDay, previousToday: previousToday, today: today)
        previousToday = today
    }
}
