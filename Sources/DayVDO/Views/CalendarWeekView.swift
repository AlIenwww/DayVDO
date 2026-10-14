import AppKit
import SwiftUI

struct CalendarWeekView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var selection: CalendarTodoSelection
    let calendar: Calendar
    let visibility: TodoFilterContext
    @Binding var selectedDate: Date
    @Binding var hourHeight: CGFloat
    @Binding var scrollMinute: CGFloat?
    @ObservedObject var windowCache: CalendarWindowCache
    let presentationCache: CalendarWeekPresentationCache
    var navigationID: UUID? = nil
    var navigationDate: Date? = nil
    var visibleRangeChanged: (LocalDay) -> Void = { _ in }
    var createTodo: (LocalDay, LocalDay) -> Void
    var changeTodo: (TodoItem) -> Void
    var editTodo: (TodoItem) -> Void
    var showMore: (LocalDay) -> Void

    @AppStorage("calendarWeekTodoFraction") private var todoFraction = CalendarWeekSplitPolicy.defaultFraction
    @State private var firstVisibleDay: LocalDay?
    @State private var scrollingDay: LocalDay?
    @State private var todoScrollOffset: CGFloat = 0

    private var week: LocalDay {
        LocalDay(calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate,
                 timeZone: calendar.timeZone)
    }
    private var cacheWeek: LocalDay {
        let day = scrollingDay ?? firstVisibleDay ?? week
        return week.adding(days: Int(floor(Double(week.distance(to: day)) / 7)) * 7)
    }
    private var snapshotKey: CalendarWindowSnapshot.Key {
        .init(revision: store.contentRevision, firstDay: cacheWeek.adding(days: -21),
              lastDay: cacheWeek.adding(days: 27), timeZoneIdentifier: calendar.timeZone.identifier,
              firstWeekday: calendar.firstWeekday, visibility: visibility)
    }

    private var todoContentHeight: CGFloat {
        let snapshot = windowCache.snapshotForDisplay(matching: snapshotKey)
        let lane = snapshot?.dateLayoutsByWeek.values.flatMap(\.segments).map(\.lane).max() ?? 0
        return CGFloat(lane + 1) * CalendarTodoBar.laneHeight + 12
    }

    var body: some View {
        let firstDay = firstVisibleDay ?? week
        let visibleDay = scrollingDay ?? firstDay
        CalendarWeekDateViewport(week: week, firstDay: firstDay, leadingInset: 54,
            navigationID: navigationID,
            navigationDay: navigationDate.map { LocalDay($0, timeZone: calendar.timeZone) },
            axis: AnyView(CalendarWeekSplitView(fraction: $todoFraction, showsDividerControl: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 64)
                    Text(L10n.string("待办事项")).font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
                    Spacer(minLength: 0)
                }
            } bottom: {
                CalendarWeekTimeAxis(hourHeight: hourHeight, scrollMinute: $scrollMinute)
            }),
            visibleDayChanged: { day in
                scrollingDay = day
                visibleRangeChanged(day)
            }, settledAtDay: { destination in
                firstVisibleDay = destination
                selection.selectedID = nil
            }) { pageWeek in
                CalendarWeekPage(calendar: calendar, visibility: visibility,
                    selectedDate: $selectedDate, hourHeight: $hourHeight, scrollMinute: $scrollMinute,
                    windowCache: windowCache, presentationCache: presentationCache,
                    createTodo: createTodo, changeTodo: changeTodo, editTodo: editTodo, showMore: showMore,
                    week: pageWeek, isActive: pageWeek <= visibleDay.adding(days: 7)
                        && pageWeek.adding(days: 6) >= visibleDay.adding(days: -1),
                    todoFraction: $todoFraction, todoScrollOffset: $todoScrollOffset,
                    minimumTodoContentHeight: todoContentHeight)
                    .environmentObject(store).environmentObject(selection)
            }
            .id(CalendarViewportIdentity(firstWeekday: calendar.firstWeekday,
                                         timeZoneIdentifier: calendar.timeZone.identifier))
        .overlay { CalendarWeekDivider(fraction: $todoFraction) }
        .task(id: snapshotKey) {
            windowCache.prepare(.init(key: snapshotKey, items: store.items, tags: store.tags))
        }
        .onChange(of: selectedDate) { _, date in
            let day = LocalDay(date, timeZone: calendar.timeZone)
            if !(firstDay...firstDay.adding(days: 6)).contains(day) { firstVisibleDay = week }
        }
        .onChange(of: calendar.firstWeekday) { _, _ in firstVisibleDay = week }
        .onChange(of: calendar.timeZone.identifier) { _, _ in firstVisibleDay = week }
    }
}

private struct CalendarWeekPage: View {
    @EnvironmentObject private var selection: CalendarTodoSelection
    @EnvironmentObject private var store: TodoStore
    let calendar: Calendar
    let visibility: TodoFilterContext
    @Binding var selectedDate: Date
    @Binding var hourHeight: CGFloat
    @Binding var scrollMinute: CGFloat?
    @ObservedObject var windowCache: CalendarWindowCache
    let presentationCache: CalendarWeekPresentationCache
    var createTodo: (LocalDay, LocalDay) -> Void
    var changeTodo: (TodoItem) -> Void
    var editTodo: (TodoItem) -> Void
    var showMore: (LocalDay) -> Void
    let week: LocalDay
    let isActive: Bool
    @Binding var todoFraction: Double
    @Binding var todoScrollOffset: CGFloat
    let minimumTodoContentHeight: CGFloat
    @State private var todoPosition = ScrollPosition()
    @StateObject private var interaction = CalendarDateInteraction()

    private var snapshotKey: CalendarWindowSnapshot.Key {
        .init(revision: store.contentRevision, firstDay: week,
              lastDay: week.adding(days: 6), timeZoneIdentifier: calendar.timeZone.identifier,
              firstWeekday: calendar.firstWeekday, visibility: visibility)
    }

    private func contentHeight(for items: [CalendarWindowSnapshot.Item]) -> CGFloat {
        var values = items
        if let draft = selection.draft, let start = draft.startDay, let end = draft.dueDay {
            values.insert(.init(id: draft.id, startDay: start, dueDay: end, title: "", status: .notStarted,
                                hasProject: false, tagColor: nil), at: 0)
        }
        if let drag = interaction.drag {
            if let index = values.firstIndex(where: { $0.id == drag.item?.id }) {
                values[index].startDay = drag.range.lowerBound
                values[index].dueDay = drag.range.upperBound
            } else if drag.item == nil {
                values.insert(.init(id: interaction.draftID, startDay: drag.range.lowerBound,
                    dueDay: drag.range.upperBound, title: "", status: .notStarted,
                    hasProject: false, tagColor: nil), at: 0)
            }
        }
        let lanes = (CalendarDatePolicy.previewSegments(values, draft: nil,
            previewID: interaction.drag.map { $0.item?.id ?? interaction.draftID }, week: week)
            .map(\.lane).max() ?? 0) + 1
        return CGFloat(lanes) * CalendarTodoBar.laneHeight + 12
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                let day = week.adding(days: column)
                Button { selection.selectedID = nil; selectedDate = day.date() } label: {
                    VStack(spacing: 3) {
                        Text(day.date().formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale)))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(day.day)").font(.title3.weight(.medium))
                            .foregroundStyle(day == LocalDay(selectedDate) ? Color.white : (day == LocalDay(.now) ? .accentColor : .primary))
                            .frame(width: 30, height: 30)
                            .background(day == LocalDay(selectedDate) ? Color.accentColor : .clear, in: Circle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.plain)
            }
        }
        .frame(height: 64)
    }

    var body: some View {
        let snapshot = windowCache.snapshotForDisplay(matching: snapshotKey)
        let items = snapshot?.items(inWeek: week) ?? []
        let rowHeight = max(minimumTodoContentHeight, contentHeight(for: items))
        CalendarWeekSplitView(fraction: $todoFraction, showsDividerControl: false) {
            GeometryReader { datesGeometry in
                ScrollView(.vertical) {
                    CalendarDateWeekRow(interaction: interaction, week: week,
                        selected: LocalDay(selectedDate), month: week.month,
                        items: items, visibility: visibility, showsDates: false, maxLanes: Int.max,
                        preparedLayout: snapshot?.dateLayoutsByWeek[week],
                        select: { selectedDate = $0.date() }, showMore: showMore, edit: editTodo)
                        .frame(height: max(rowHeight, datesGeometry.size.height))
                }
                .scrollPosition($todoPosition)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                    if isActive && abs(offset - todoScrollOffset) > 1 { todoScrollOffset = offset }
                }
                .onChange(of: todoScrollOffset) { _, offset in todoPosition.scrollTo(y: offset) }
                .onAppear { todoPosition.scrollTo(y: todoScrollOffset) }
                .scrollClipDisabled()
                // Keep the native toolbar's sampling area while clipping at the divider.
                .padding(.top, max(0, datesGeometry.frame(in: .global).minY))
                .clipped()
                .padding(.top, -max(0, datesGeometry.frame(in: .global).minY))
                .scrollIndicators(.hidden)
                .scrollDisabled(interaction.drag != nil || interaction.suppressed)
                .coordinateSpace(name: "calendarDateViewport")
                .onPreferenceChange(CalendarWeekFrames.self) { interaction.frames = $0 }
                .onPreferenceChange(CalendarDateHitRegions.self) { regions in
                    let updated = regions.keys.sorted().flatMap { regions[$0] ?? [] }
                    if interaction.hitRegions != updated { interaction.hitRegions = updated }
                }
                .onAppear { interaction.viewport = datesGeometry.size }
                .onChange(of: datesGeometry.size) { _, size in
                    if interaction.drag != nil { interaction.cancel() }
                    interaction.viewport = size
                }
                .overlay {
                    CalendarDateInput(interaction: interaction, store: store,
                        select: { selectedDate = $0.date() }, showMore: showMore,
                        create: createTodo, change: changeTodo, edit: editTodo)
                }
            }
            .pageTopBar { weekdayHeader }
        } bottom: {
            CalendarWeekTimeline(week: week, visibility: visibility, hourHeight: $hourHeight,
                scrollMinute: $scrollMinute, presentationCache: presentationCache,
                isActive: isActive, gutter: 0, synchronizesScrolling: true, editTodo: editTodo)
        }
        .onChange(of: week) { _, _ in interaction.release() }
        .onChange(of: visibility) { _, _ in
            if NSEvent.pressedMouseButtons & 1 != 0 { interaction.cancel() }
            else { interaction.release() }
            interaction.hitRegions = []
        }
        .onDisappear { interaction.release() }
    }
}

/// Only vertical scrolling affects this axis; horizontal dates never enter it.
private struct CalendarWeekTimeAxis: View {
    let hourHeight: CGFloat
    @Binding var scrollMinute: CGFloat?
    @State private var position = ScrollPosition()
    @State private var offset: CGFloat = 0
    @State private var restored = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(SchedulePresentation.clock(hour * 60)).font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                            .offset(y: 5 + CGFloat(hour) * hourHeight)
                    }
                }
                .frame(width: 54, height: hourHeight * 24 + 24, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .defaultScrollAnchor(UnitPoint(x: 0, y: CalendarScrollPolicy.initialAnchor(
                offset: (scrollMinute ?? 480) * hourHeight / 60,
                contentHeight: hourHeight * 24 + 24, viewportHeight: geometry.size.height)), for: .initialOffset)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in
                offset = value
                let expected = min((scrollMinute ?? 480) * hourHeight / 60,
                    max(0, hourHeight * 24 + 24 - geometry.size.height))
                if !restored && abs(value - expected) <= 1 { restored = true }
                if restored && abs(value - expected) > 1 { scrollMinute = value * 60 / hourHeight }
            }
            .onChange(of: scrollMinute) { _, minute in
                if let minute, abs(minute * hourHeight / 60 - offset) > 1 {
                    position.scrollTo(y: minute * hourHeight / 60)
                }
            }
            .onChange(of: hourHeight) { _, height in position.scrollTo(y: (scrollMinute ?? 480) * height / 60) }
        }
        .accessibilityIdentifier("calendar.week.time-axis")
    }
}
