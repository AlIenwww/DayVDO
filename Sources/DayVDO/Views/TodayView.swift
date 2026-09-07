import AppKit
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var selectedDay: LocalDay
    @State private var now = Date.now
    @State private var previousToday = LocalDay(.now)
    @State private var isPickingDate = false
    @State private var showsTodoPanel = false
    @State private var hourHeight: CGFloat = 90
    @State private var scheduleDraft: DaySchedule?
    @State private var schedulePopover: SchedulePopoverRequest?
    @State private var queuedTodo: TodoItem?
    @State private var pending: PendingSchedule?
    @State private var timelineActive = false
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
            VStack(spacing: 0) {
                dateHeader(narrow: narrow)
                Divider()
                ZStack(alignment: .trailing) {
                    HStack(spacing: 0) {
                        DayTimelineView(
                            day: selectedDay, hourHeight: $hourHeight, now: now,
                            obscuredWidth: narrow && showsTodoPanel ? min(280, max(220, geometry.size.width * 0.55)) : 0,
                            presentation: $schedulePopover,
                            create: { minute, duration in
                                scheduleDraft = DaySchedule(startDay: selectedDay, startMinute: minute,
                                    durationMinutes: duration, content: .independent(title: "", notes: ""))
                            },
                            dropTodo: requestSchedule,
                            editTodo: queueTodoForEditing,
                            activityChanged: { timelineActive = $0 }
                        )
                        if !narrow {
                            Divider()
                            todoPanel.frame(width: 280)
                        }
                    }
                    if narrow && showsTodoPanel {
                        todoPanel
                            .frame(width: min(280, max(220, geometry.size.width * 0.55)))
                            .overlay(alignment: .leading) { Divider() }
                            .shadow(color: .black.opacity(0.08), radius: 8, x: -4)
                    }
                }
            }
            .onChange(of: narrow) { _, value in if !value { showsTodoPanel = false } }
        }
        .navigationTitle(L10n.string("今日待办"))
        .popover(item: $scheduleDraft) { schedule in
            ScheduleEditorView(schedule: schedule, editTodo: queueTodoForEditing)
        }
        .onChange(of: scheduleDraft) { old, new in
            if old != nil && new == nil { finishPresentation() }
        }
        .alert(L10n.string("已达到预计时长"), isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        )) {
            Button(L10n.string("继续安排 30 分钟")) {
                guard let request = pending else { return }
                pending = nil
                store.upsertSchedule(request.schedule)
            }
            Button(L10n.string("取消"), role: .cancel) { pending = nil }
        } message: {
            Text(L10n.string("这个待办已安排足够时间，仍要再添加一段吗？"))
        }
        .onReceive(clock) { _ in refreshClock() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshClock() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshClock() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshClock() }
        .onChange(of: isBusy) { _, busy in if !busy { refreshClock() } }
    }

    private var todoPanel: some View {
        PlanningTodoPanel(day: selectedDay, edit: { editingItem = $0 })
    }

    private func dateHeader(narrow: Bool) -> some View {
        HStack(spacing: 10) {
            Button { selectedDay = selectedDay.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                .help(L10n.string("前一天"))
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
            Button { selectedDay = selectedDay.adding(days: 1) } label: { Image(systemName: "chevron.right") }
                .help(L10n.string("后一天"))
            Button(L10n.string("今天")) { selectedDay = LocalDay(.now) }
            Spacer(minLength: 0)
            if narrow {
                Button { showsTodoPanel.toggle() } label: { Image(systemName: "list.bullet.rectangle.portrait") }
                    .help(L10n.string("待办事项"))
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func requestSchedule(_ id: UUID, at minute: Int) {
        guard let todo = store.items.first(where: { $0.id == id }), todo.dueDay == selectedDay else { return }
        let scheduled = store.scheduledMinutes(for: id)
        let duration = DayPlanningPolicy.defaultDuration(estimated: todo.estimatedMinutes, scheduled: scheduled)
        let schedule = DaySchedule(startDay: selectedDay, startMinute: minute,
                                   durationMinutes: duration, content: .todo(id))
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
