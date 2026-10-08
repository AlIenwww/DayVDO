import CoreGraphics

enum TimelineCurrentTimeLabelPolicy {
    /// Find the nearest free vertical position without moving the time marker.
    static func top(for naturalTop: CGFloat, labelHeight: CGFloat,
                    avoiding tickFrames: [CGRect], contentHeight: CGFloat,
                    minimumGap: CGFloat = 3) -> CGFloat {
        let maximumTop = max(0, contentHeight - labelHeight)
        func bounded(_ top: CGFloat) -> CGFloat { min(maximumTop, max(0, top)) }
        let preferred = bounded(naturalTop)
        let candidates: [CGFloat] = [preferred, 0, maximumTop] + tickFrames.flatMap { frame -> [CGFloat] in
            [bounded(frame.minY - minimumGap - labelHeight), bounded(frame.maxY + minimumGap)]
        }
        let free = candidates.filter { top in
            tickFrames.allSatisfy {
                top + labelHeight + minimumGap <= $0.minY + 0.000_001
                    || top >= $0.maxY + minimumGap - 0.000_001
            }
        }
        return free.min { lhs, rhs in
            let leftDistance = abs(lhs - preferred)
            let rightDistance = abs(rhs - preferred)
            if abs(leftDistance - rightDistance) < 0.000_001 { return lhs > rhs }
            return leftDistance < rightDistance
        } ?? preferred
    }
}
