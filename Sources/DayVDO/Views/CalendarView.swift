import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: TodoStore
    @Binding var editingItem: TodoItem?
    @State private var selectedDate = Date.now
    @State private var topWeekOffset: Int? = 0

    private let weekRange = -2_600...2_600

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = store.settings.startWeekOnMonday ? 2 : 1
        return value
    }

    private var currentMonth: Date {
        let week = weekStart(at: topWeekOffset ?? 0)
        let viewportCenter = calendar.date(byAdding: .day, value: 21, to: week) ?? week
        return monthStart(for: viewportCenter)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        GeometryReader { geometry in
            let inspectorWidth = detailWidth(for: geometry.size.width)
            let calendarWidth = max(420, geometry.size.width - inspectorWidth - 1)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    calendarToolbar
                    GeometryReader { calendarGeometry in
                        VStack(spacing: 0) {
                            weekdayHeader(width: calendarGeometry.size.width)
                            weekTimeline(
                                width: calendarGeometry.size.width,
                                height: max(330, calendarGeometry.size.height - 32)
                            )
                        }
                    }
                }
                .frame(width: calendarWidth)

                Divider()

                dayDetail
                    .frame(width: inspectorWidth)
            }
            .background(.background)
        }
        .navigationTitle("日历")
    }

    private var calendarToolbar: some View {
        HStack(spacing: 8) {
            Text(currentMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            Spacer()
            Button("今天") {
                selectedDate = .now
                withAnimation(.snappy) { topWeekOffset = 0 }
            }
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("上个月")
            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("下个月")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .frame(height: 54)
    }

    private func weekTimeline(width: CGFloat, height: CGFloat) -> some View {
        let cellWidth = max(1, (width - 24) / 7)
        let rowHeight = floor(height / 6)

        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(weekRange, id: \.self) { offset in
                    weekRow(
                        starting: weekStart(at: offset),
                        displayedMonth: currentMonth,
                        cellWidth: cellWidth,
                        rowHeight: rowHeight
                    )
                    .id(offset)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $topWeekOffset, anchor: .top)
    }

    private func weekdayHeader(width: CGFloat) -> some View {
        let cellWidth = max(1, (width - 24) / 7)

        return HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: cellWidth, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func weekRow(
        starting weekStart: Date,
        displayedMonth: Date,
        cellWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                if let date = calendar.date(byAdding: .day, value: column, to: weekStart) {
                    dayCell(
                        date,
                        displayedMonth: displayedMonth,
                        width: cellWidth,
                        height: rowHeight
                    )
                }
            }
        }
        .frame(height: rowHeight)
        .overlay {
            CalendarGridLines(columns: 7, rows: 1)
                .allowsHitTesting(false)
        }
    }

    private func dayCell(
        _ date: Date,
        displayedMonth: Date,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let items = store.items(on: date)
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let belongsToMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return Button {
            selectedDate = date
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(today || selected ? .semibold : .regular))
                    .foregroundStyle(
                        selected ? Color.white :
                            (today ? Color.accentColor : (belongsToMonth ? Color.primary : Color.secondary))
                    )
                    .frame(width: 23, height: 23)
                    .background(selected ? Color.accentColor : Color.clear, in: Circle())

                ForEach(items.prefix(2)) { item in
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.accentColor.opacity(item.isCompleted ? 0.05 : 0.13),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                }

                if items.count > 2 {
                    Text("另有 \(items.count - 2) 项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.06) : Color.clear)
            .opacity(belongsToMonth ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
        .accessibilityValue("\(items.count) 项待办")
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(calendar.component(.day, from: selectedDate))")
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(calendar.isDateInToday(selectedDate) ? Color.accentColor : Color.primary)
                    .frame(minWidth: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate.formatted(.dateTime.year().month(.wide)))
                        .font(.headline)
                    Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider()

            HStack {
                Text("待办事项")
                    .font(.headline)
                Spacer()
                Button {
                    editingItem = TodoItem(title: "", dueDate: selectedDate, priority: store.settings.defaultPriority)
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help("为这一天添加待办")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            let items = store.items(on: selectedDate)
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("这一天暂无安排")
                        .font(.callout.weight(.medium))
                    Text("你可以在这里添加一项待办。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    TodoRow(item: item, showsDate: false) { editingItem = item }
                }
                .listStyle(.inset)
            }
        }
        .background(.background.secondary)
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private var timelineAnchorWeek: Date {
        CalendarMonthGrid.dates(containing: monthStart(for: .now), calendar: calendar).first ?? .now
    }

    private func weekStart(at offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: timelineAnchorWeek) ?? timelineAnchorWeek
    }

    private func weekOffset(forMonth month: Date) -> Int {
        guard let targetWeek = CalendarMonthGrid.dates(containing: monthStart(for: month), calendar: calendar).first else {
            return 0
        }
        let dayDistance = calendar.dateComponents([.day], from: timelineAnchorWeek, to: targetWeek).day ?? 0
        return min(max(dayDistance / 7, weekRange.lowerBound), weekRange.upperBound)
    }

    private func moveMonth(by value: Int) {
        guard let target = calendar.date(byAdding: .month, value: value, to: currentMonth) else { return }
        withAnimation(.snappy) { topWeekOffset = weekOffset(forMonth: target) }
    }

    private func detailWidth(for availableWidth: CGFloat) -> CGFloat {
        min(330, max(230, availableWidth * 0.34))
    }
}

private struct CalendarGridLines: View {
    let columns: Int
    let rows: Int

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for column in 0...columns {
                    let x = geometry.size.width * CGFloat(column) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                for row in 0...rows {
                    let y = geometry.size.height * CGFloat(row) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
        }
    }
}
