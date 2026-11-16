import SwiftUI

/// The compact v0.5.2 calendar card, shared by saved items and date-drag previews.
struct CalendarTodoBar: View {
    let item: CalendarWindowSnapshot.Item
    var startsHere = true
    var endsHere = true
    var statusAnimation: Animation?

    nonisolated static let height: CGFloat = 15
    nonisolated static let laneHeight: CGFloat = 20

    var body: some View {
        let color = item.tagColor?.color ?? .accentColor
        HStack(spacing: 3) {
            CalendarTaskStatusIcon(status: item.status, animates: statusAnimation != nil)
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 10)
                .accessibilityHidden(true)
            if item.hasProject {
                Image(systemName: "folder.fill").font(.system(size: 7)).foregroundStyle(.secondary)
            }
            CalendarTaskStatusTitle(title: item.title, isCompleted: item.isCompleted).lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(item.isCompleted ? .secondary : .primary)
        .padding(.horizontal, 4).padding(.leading, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color.opacity(item.isCompleted ? 0.05 : 0.13), in: UnevenRoundedRectangle(
            topLeadingRadius: startsHere ? 3 : 0, bottomLeadingRadius: startsHere ? 3 : 0,
            bottomTrailingRadius: endsHere ? 3 : 0, topTrailingRadius: endsHere ? 3 : 0))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(item.isCompleted ? 0.45 : 0.9))
                .frame(width: 2).padding(.vertical, 2)
        }
        .animation(statusAnimation, value: item.status)
    }
}
