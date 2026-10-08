import AppKit
import Combine
import SwiftUI

struct CalendarWeekFrames: PreferenceKey {
    static let defaultValue: [LocalDay: CGRect] = [:]
    static func reduce(value: inout [LocalDay: CGRect], nextValue: () -> [LocalDay: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
final class CalendarDateInteraction: ObservableObject {
    struct Drag {
        var item: TodoItem?
        var anchor: LocalDay
        var mode: CalendarDateDragMode
        var range: ClosedRange<LocalDay>
    }
    @Published var drag: Drag?
    @Published var suppressed = false
    // Pointer geometry only updates the native responder. Publishing it as
    // view state makes every date row lay out again after its first layout.
    let hitRegionsChanged = PassthroughSubject<[CalendarDateHitRegion], Never>()
    var hitRegions: [CalendarDateHitRegion] = [] {
        didSet { if oldValue != hitRegions { hitRegionsChanged.send(hitRegions) } }
    }
    let draftID = UUID()
    var frames: [LocalDay: CGRect] = [:]
    var viewport: CGSize = .zero

    func day(at point: CGPoint) -> LocalDay? {
        guard CGRect(origin: .zero, size: viewport).contains(point),
              let (week, frame) = frames.first(where: { $0.value.contains(point) }), frame.width > 0 else { return nil }
        return week.adding(days: min(6, max(0, Int((point.x - frame.minX) / (frame.width / 7)))))
    }

    func update(origin: CGPoint, location: CGPoint, item: TodoItem?, mode: CalendarDateDragMode) {
        guard !suppressed else { return }
        if drag == nil, let anchor = day(at: origin) {
            drag = Drag(item: item, anchor: anchor, mode: mode,
                        range: (item?.startDay ?? anchor)...(item?.dueDay ?? anchor))
        }
        guard var current = drag, let target = day(at: location) else { return }
        current.range = CalendarDatePolicy.range(start: current.item?.startDay ?? current.anchor,
            end: current.item?.dueDay ?? current.anchor, anchor: current.anchor, target: target, mode: current.mode)
        drag = current
    }

    func finish(at point: CGPoint, create: (LocalDay, LocalDay) -> Void, change: (TodoItem) -> Void) {
        defer { drag = nil }
        guard !suppressed, day(at: point) != nil, let drag else { return }
        if var item = drag.item {
            guard item.startDay != drag.range.lowerBound || item.dueDay != drag.range.upperBound else { return }
            item.startDay = drag.range.lowerBound; item.dueDay = drag.range.upperBound
            change(item)
        } else { create(drag.range.lowerBound, drag.range.upperBound) }
    }
    func cancel() { suppressed = true; drag = nil }
    func release() { drag = nil; suppressed = false }
}

struct CalendarDateWeekRow: View {
    static let dateHeaderHeight: CGFloat = 31

    @EnvironmentObject private var selection: CalendarTodoSelection
    @EnvironmentObject private var store: TodoStore
    @ObservedObject var interaction: CalendarDateInteraction
    let week: LocalDay
    let selected: LocalDay
    let month: Int
    let items: [CalendarWindowSnapshot.Item]
    var visibility = TodoFilterContext(showCompleted: true)
    var showsDates = true
    var maxLanes: Int? = nil
    var preparedLayout: CalendarDateLayout? = nil
    var select: (LocalDay) -> Void
    var showMore: (LocalDay) -> Void
    var edit: (TodoItem) -> Void

    private var displayed: [CalendarWindowSnapshot.Item] {
        var candidates = items
        // A dragged task can enter a week that did not originally contain it.
        if let item = interaction.drag?.item,
           !candidates.contains(where: { $0.id == item.id }),
           let start = item.startDay, let end = item.dueDay {
            candidates.append(.init(id: item.id, startDay: start, dueDay: end,
                title: item.title, status: item.status, hasProject: item.projectID != nil,
                tagColor: store.tag(withID: item.tagID)?.color))
        }
        return candidates.compactMap { summary in
            guard let latest = store.item(withID: summary.id),
                  visibility.includes(latest),
                  let start = latest.startDay, let end = latest.dueDay else { return nil }
            var copy = summary
            copy.startDay = start; copy.dueDay = end; copy.title = latest.title; copy.status = latest.status
            copy.hasProject = latest.projectID != nil
            copy.tagColor = store.tag(withID: latest.tagID)?.color
            if interaction.drag?.item?.id == copy.id, let range = interaction.drag?.range {
                copy.startDay = range.lowerBound; copy.dueDay = range.upperBound
            }
            return copy
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let header: CGFloat = showsDates ? Self.dateHeaderHeight : 4
            let capacity = maxLanes ?? max(1, Int((geometry.size.height - header - 19) / CalendarTodoBar.laneHeight))
            let previewID = interaction.drag.map { $0.item?.id ?? interaction.draftID } ?? draft?.id
            let layout = (interaction.drag == nil && draft == nil ? preparedLayout : nil)
                ?? CalendarDateLayout(segments: CalendarDatePolicy.previewSegments(
                    displayed, draft: draft, previewID: previewID, week: week))
            let segments = layout.segments
            let columnWidth = geometry.size.width / 7
            let frame = geometry.frame(in: .named("calendarDateViewport"))
            let visible = segments.filter { $0.lane < capacity }
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        dayBackground(week.adding(days: column), column: column,
                            hidden: segments.filter { $0.item.id != draft?.id && $0.lane >= capacity && ($0.firstColumn...$0.lastColumn).contains(column) }.count)
                    }
                }
                ForEach(visible) { segment in
                    bar(segment)
                        .frame(width: barFrame(segment, columnWidth: columnWidth, header: header).width,
                               height: CalendarTodoBar.height)
                        .offset(x: barFrame(segment, columnWidth: columnWidth, header: header).minX,
                                y: barFrame(segment, columnWidth: columnWidth, header: header).minY)
                }
            }
            .preference(key: CalendarWeekFrames.self, value: [week: frame])
            .preference(key: CalendarDateHitRegions.self, value: [week:
                visible.filter { $0.id != draft?.id }.map { segment in
                    CalendarDateHitRegion(frame: barFrame(segment, columnWidth: columnWidth, header: header)
                        .offsetBy(dx: frame.minX, dy: frame.minY),
                        target: .item(segment.id, startsHere: segment.startsHere, endsHere: segment.endsHere))
                } + (0..<7).compactMap { column in
                    guard segments.contains(where: { $0.item.id != draft?.id && $0.lane >= capacity && ($0.firstColumn...$0.lastColumn).contains(column) }) else { return nil }
                    return CalendarDateHitRegion(frame: CGRect(x: frame.minX + CGFloat(column) * columnWidth,
                        y: frame.maxY - 19, width: columnWidth, height: 19),
                        target: .more(week.adding(days: column)))
                }
            ])
        }
    }

    private var draft: CalendarWindowSnapshot.Item? {
        if let drag = interaction.drag, drag.item == nil {
            return .init(id: interaction.draftID, startDay: drag.range.lowerBound, dueDay: drag.range.upperBound,
                         title: L10n.string("新建待办"), status: .notStarted, hasProject: false, tagColor: nil)
        }
        guard let pending = selection.draft, let start = pending.startDay, let end = pending.dueDay else { return nil }
        return .init(id: pending.id, startDay: start, dueDay: end,
                     title: pending.title.isEmpty ? L10n.string("新建待办") : pending.title,
                     status: .notStarted, hasProject: pending.projectID != nil, tagColor: nil)
    }

    private func barFrame(_ segment: CalendarDatePolicy.Segment, columnWidth: CGFloat, header: CGFloat) -> CGRect {
        CGRect(x: CGFloat(segment.firstColumn) * columnWidth + 6,
               y: header + CGFloat(segment.lane) * CalendarTodoBar.laneHeight,
               width: max(1, CGFloat(segment.lastColumn - segment.firstColumn + 1) * columnWidth - 12),
               height: CalendarTodoBar.height)
    }

    private func dayBackground(_ day: LocalDay, column: Int, hidden: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDates {
                Text("\(day.day)").font(.caption.weight(day == selected ? .semibold : .regular))
                    .foregroundStyle(day == selected ? Color.white : (day == LocalDay(.now) ? .accentColor : .primary))
                    .frame(width: 23, height: 23)
                    .background(day == selected ? Color.accentColor : .clear, in: Circle())
                    .padding(.leading, 6).padding(.top, 4)
            }
            Spacer(minLength: 0)
            if hidden > 0 {
                Button(L10n.format("另有 %lld 项", hidden)) { showMore(day) }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).padding(.horizontal, 6).padding(.bottom, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(day == selected ? Color.accentColor.opacity(0.045) : .clear)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { select(day) }
        .opacity(!showsDates || day.month == month ? 1 : 0.55)
        .focusable().focusEffectDisabled()
        .onKeyPress(.return) { select(day); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityAction { select(day) }
        .accessibilityLabel(day.date().formatted(.dateTime.year().month().day().locale(L10n.locale)))
    }

    private func bar(_ segment: CalendarDatePolicy.Segment) -> some View {
        CalendarTodoBar(item: segment.item, startsHere: segment.startsHere, endsHere: segment.endsHere)
            .overlay {
                if selection.selectedID == segment.id {
                    RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
            .focusable(segment.id != draft?.id).focusEffectDisabled()
            .onKeyPress(.return) {
                if let latest = store.item(withID: segment.id) { edit(latest) }
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(segment.item.title)
            .accessibilityHidden(segment.id == draft?.id)
            .accessibilityAction { if let latest = store.item(withID: segment.id) { edit(latest) } }
    }

}
