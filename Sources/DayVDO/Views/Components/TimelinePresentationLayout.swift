import SwiftUI

enum TimelinePopoverAnchor {
    static func point(at cursor: CGPoint, in viewport: CGSize) -> UnitPoint {
        UnitPoint(x: min(1, max(0, cursor.x / max(1, viewport.width))),
                  y: min(1, max(0, cursor.y / max(1, viewport.height))))
    }
}

enum TimelineScheduleShape {
    static func shape(placement _: DayPlanningPolicy.Placement, radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                               bottomTrailingRadius: radius, topTrailingRadius: radius)
    }
}
