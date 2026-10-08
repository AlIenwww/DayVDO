import SwiftUI

struct TimelineTimeLabels: View {
    let hourHeight: CGFloat
    let currentMinute: Int?

    var body: some View {
        TimelineTimeLabelLayout(hourHeight: hourHeight, currentMinute: currentMinute) {
            ForEach(0...24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: "%02d:00", hour))
                    .accessibilityIdentifier("timeline.hour.\(hour)")
            }
            if let currentMinute {
                Text(SchedulePresentation.clock(currentMinute))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SchedulePresentation.clock(currentMinute))
                    .accessibilityIdentifier("timeline.current-time")
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TimelineTimeLabelLayout: Layout {
    let hourHeight: CGFloat
    let currentMinute: Int?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 46, height: hourHeight * 24)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Measure intrinsic text sizes during layout, before any collision
        // calculation. No asynchronous geometry state or estimated font heights.
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ticks = (0...24).map { hour in
            CGRect(x: bounds.width - sizes[hour].width, y: CGFloat(hour) * hourHeight - 7,
                   width: sizes[hour].width, height: sizes[hour].height)
        }
        for hour in 0...24 {
            subviews[hour].place(at: CGPoint(x: bounds.minX + ticks[hour].minX,
                                             y: bounds.minY + ticks[hour].minY),
                                 anchor: .topLeading, proposal: ProposedViewSize(sizes[hour]))
        }
        if let currentMinute, subviews.count > 25 {
            let size = sizes[25]
            let top = TimelineCurrentTimeLabelPolicy.top(
                for: CGFloat(currentMinute) * hourHeight / 60 - 7, labelHeight: size.height,
                avoiding: ticks, contentHeight: bounds.height)
            subviews[25].place(at: CGPoint(x: bounds.maxX - size.width, y: bounds.minY + top),
                               anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}
