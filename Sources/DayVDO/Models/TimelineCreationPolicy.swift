import Foundation

/// Creating an arrangement aligns to visible edges before the five-minute grid.
enum TimelineCreationPolicy {
    /// Measured in view points so zooming does not change the capture distance.
    static let snapDistance: Double = 6

    static func boundaries(in intervals: [Range<Int>]) -> [Int] {
        Array(Set(intervals.flatMap { [$0.lowerBound, $0.upperBound] })).sorted()
    }

    static func startMinute(at minute: Double, boundaries: [Int], pointsPerMinute: Double) -> Int {
        snapped(minute, boundaries: boundaries, pointsPerMinute: pointsPerMinute, within: 0...1435)
    }

    /// The fixed anchor can be off-grid; the moving edge follows the absolute
    /// pointer time, not a delta added to the snapped anchor.
    static func range(from origin: Double, anchoredAt start: Int, to minute: Double,
                      boundaries: [Int], pointsPerMinute: Double) -> Range<Int> {
        if minute < origin, start >= 5 {
            let end = snapped(minute, boundaries: boundaries, pointsPerMinute: pointsPerMinute,
                              within: 0...(start - 5))
            return end..<start
        }
        let end = snapped(minute, boundaries: boundaries, pointsPerMinute: pointsPerMinute,
                          within: (start + 5)...1440)
        return start..<end
    }

    private static func snapped(_ minute: Double, boundaries: [Int], pointsPerMinute: Double,
                                within limits: ClosedRange<Int>) -> Int {
        let tolerance = snapDistance / max(0.001, pointsPerMinute)
        let target = boundaries.filter { limits.contains($0) && abs(Double($0) - minute) <= tolerance }
            .min {
                let left = abs(Double($0) - minute)
                let right = abs(Double($1) - minute)
                return left == right ? $0 < $1 : left < right
            }
        return target ?? DayPlanningPolicy.snapped(minute, within: limits)!
    }
}
