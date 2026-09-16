import CoreGraphics

struct TimelineZoomAnchor: Equatable {
    let minute: CGFloat
    let viewportY: CGFloat
}

enum TimelineZoomPolicy {
    static let minimumHourHeight: CGFloat = 45
    static let maximumHourHeight: CGFloat = 180
    static let verticalContentInset: CGFloat = 12

    static func nextFrame(current: CGFloat, target: CGFloat) -> CGFloat {
        let boundedTarget = clampedHourHeight(target)
        let distance = boundedTarget - current
        if abs(distance) < 0.1 { return boundedTarget }
        return current + distance * 0.45
    }

    static func clampedHourHeight(_ value: CGFloat) -> CGFloat {
        min(maximumHourHeight, max(minimumHourHeight, value))
    }

    static func anchor(
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        hourHeight: CGFloat
    ) -> TimelineZoomAnchor {
        let viewportY = max(0, viewportHeight / 2)
        let minute = max(
            0,
            (scrollOffset + viewportY - verticalContentInset) / (hourHeight / 60)
        )
        return TimelineZoomAnchor(minute: minute, viewportY: viewportY)
    }

    static func scrollOffset(
        keeping anchor: TimelineZoomAnchor,
        hourHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let contentHeight = hourHeight * 24 + verticalContentInset * 2
        let maximumOffset = max(0, contentHeight - viewportHeight)
        let requestedOffset = anchor.minute * (hourHeight / 60)
            + verticalContentInset
            - anchor.viewportY
        return min(maximumOffset, max(0, requestedOffset))
    }
}
