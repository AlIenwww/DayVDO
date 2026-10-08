import AppKit
import SwiftUI

struct CalendarWeekView: View {
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
    @AppStorage("calendarWeekTodoFraction") private var todoFraction = CalendarWeekSplitPolicy.defaultFraction
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @StateObject private var interaction = CalendarDateInteraction()

    private var week: LocalDay {
        LocalDay(calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate,
                 timeZone: calendar.timeZone)
    }
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
            Color.clear.frame(width: 54)
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
        GeometryReader { _ in
            let items = windowCache.snapshot.flatMap {
                $0.key.matchesContent(of: snapshotKey) ? $0.items(inWeek: week) : nil
            } ?? []
            let rowHeight = contentHeight(for: items)
            Group {
                CalendarWeekSplitView(fraction: $todoFraction) {
                    HStack(alignment: .top, spacing: 0) {
                        Text(L10n.string("待办事项")).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 54).padding(.top, 6)
                        GeometryReader { datesGeometry in
                            ScrollView(.vertical) {
                                CalendarDateWeekRow(interaction: interaction, week: week,
                                    selected: LocalDay(selectedDate), month: week.month,
                                    items: items, visibility: visibility, showsDates: false, maxLanes: Int.max,
                                    select: { selectedDate = $0.date() }, showMore: showMore, edit: editTodo)
                                    .frame(height: max(rowHeight, datesGeometry.size.height))
                            }
                            .scrollClipDisabled()
                            // Expand the clipping bounds upward, then restore
                            // the original layout size. The divider stays clipped.
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
                    }
                    .background(.background)
                    .pageTopBar { weekdayHeader }
                    .environmentObject(store).environmentObject(selection).environment(\.colorScheme, colorScheme).environment(\.locale, locale)
                } bottom: {
                    CalendarWeekTimeline(week: week, visibility: visibility, hourHeight: $hourHeight,
                                         scrollMinute: $scrollMinute,
                                         presentationCache: presentationCache,
                                         editTodo: editTodo)
                        .environmentObject(store).environmentObject(selection).environment(\.colorScheme, colorScheme).environment(\.locale, locale)
                }
            }
        }
        .task(id: snapshotKey) {
            windowCache.prepare(.init(key: snapshotKey, items: store.items, tags: store.tags))
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
