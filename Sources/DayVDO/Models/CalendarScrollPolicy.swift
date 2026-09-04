import CoreGraphics
import Foundation

enum CalendarScrollDirection: Int, Equatable {
    case earlier = -1
    case later = 1

    init?(signedMovement: CGFloat) {
        guard abs(signedMovement) >= CalendarScrollPolicy.stationaryThreshold else { return nil }
        self = signedMovement > 0 ? .later : .earlier
    }
}

struct CalendarGestureSnapshot: Equatable {
    let startRow: CGFloat
    let currentRow: CGFloat
    let duration: TimeInterval
    let releaseVelocityInWeeksPerSecond: CGFloat
    let usesPreciseDeltas: Bool

    var directMovementInWeeks: CGFloat {
        currentRow - startRow
    }
}

enum CalendarScrollDestination: Equatable {
    case none
    case nearestWeek(direction: CalendarScrollDirection?)
    case adjacentMonth(direction: CalendarScrollDirection)
    case momentumMonth(direction: CalendarScrollDirection)
}

enum CalendarScrollPolicy {
    static let stationaryThreshold: CGFloat = 0.01
    static let fastFlickVelocity: CGFloat = 3
    static let longFlickDistance: CGFloat = 2
    static let precisionDragMinimumDuration: TimeInterval = 0.35
    static let precisionDragMaximumAverageVelocity: CGFloat = 3
    static let velocitySampleWindow: TimeInterval = 0.1
    static let directionalCachePadding = 4
    static let maximumPredictiveDistance = 12

    static func destination(
        for snapshot: CalendarGestureSnapshot
    ) -> CalendarScrollDestination {
        let movement = snapshot.directMovementInWeeks
        guard abs(movement) >= stationaryThreshold else { return .none }

        let movementDirection = CalendarScrollDirection(signedMovement: movement)
        let averageVelocity = abs(movement) / CGFloat(max(snapshot.duration, 0.001))
        let isPrecisionDrag = snapshot.duration >= precisionDragMinimumDuration
            && averageVelocity <= precisionDragMaximumAverageVelocity

        guard snapshot.usesPreciseDeltas,
              !isPrecisionDrag,
              abs(snapshot.releaseVelocityInWeeksPerSecond) >= fastFlickVelocity else {
            return .nearestWeek(direction: movementDirection)
        }

        let releaseDirection = CalendarScrollDirection(
            signedMovement: snapshot.releaseVelocityInWeeksPerSecond
        ) ?? movementDirection
        guard let direction = releaseDirection else { return .none }

        if abs(movement) < longFlickDistance {
            return .adjacentMonth(direction: direction)
        }
        return .momentumMonth(direction: direction)
    }

    static func nearestWeekIndex(
        for rowPosition: CGFloat,
        direction: CalendarScrollDirection?
    ) -> Int {
        if direction == .later {
            return Int(floor(rowPosition + 0.499))
        }
        if direction == .earlier {
            return Int(ceil(rowPosition - 0.499))
        }
        return Int(rowPosition.rounded())
    }

    static func nearestMonthIndex(
        for rowPosition: CGFloat,
        candidates: [Int],
        direction: CalendarScrollDirection?
    ) -> Int? {
        candidates.min { lhs, rhs in
            let lhsDistance = abs(CGFloat(lhs) - rowPosition)
            let rhsDistance = abs(CGFloat(rhs) - rowPosition)
            if abs(lhsDistance - rhsDistance) > 0.0001 {
                return lhsDistance < rhsDistance
            }

            switch direction {
            case .later:
                return lhs > rhs
            case .earlier:
                return lhs < rhs
            case nil:
                return lhs < rhs
            }
        }
    }

    static func targetIndex(
        for destination: CalendarScrollDestination,
        currentRow: CGFloat,
        proposedMomentumRow: CGFloat,
        adjacentMonthIndex: Int?,
        monthCandidates: [Int]
    ) -> Int {
        switch destination {
        case .none:
            return nearestWeekIndex(for: currentRow, direction: nil)
        case let .nearestWeek(direction: direction):
            return nearestWeekIndex(for: currentRow, direction: direction)
        case let .adjacentMonth(direction: direction):
            return adjacentMonthIndex
                ?? nearestWeekIndex(for: currentRow, direction: direction)
        case let .momentumMonth(direction: direction):
            return nearestMonthIndex(
                for: proposedMomentumRow,
                candidates: monthCandidates,
                direction: direction
            ) ?? nearestWeekIndex(for: proposedMomentumRow, direction: direction)
        }
    }

    static func cacheWindow(
        around visibleTop: Int,
        direction: CalendarScrollDirection?,
        cacheCount: Int,
        visibleCount: Int,
        limits: ClosedRange<Int>
    ) -> ClosedRange<Int> {
        precondition(cacheCount >= visibleCount)
        precondition(limits.upperBound - limits.lowerBound + 1 >= cacheCount)

        let availablePadding = cacheCount - visibleCount
        let leadingPadding: Int
        switch direction {
        case .later:
            leadingPadding = min(directionalCachePadding, availablePadding)
        case .earlier:
            leadingPadding = max(0, availablePadding - directionalCachePadding)
        case nil:
            leadingPadding = availablePadding / 2
        }
        return clampedCacheWindow(
            proposedLowerBound: visibleTop - leadingPadding,
            cacheCount: cacheCount,
            limits: limits
        )
    }

    static func cacheWindowCovering(
        currentTop: Int,
        targetTop: Int,
        cacheCount: Int,
        visibleCount: Int,
        limits: ClosedRange<Int>
    ) -> ClosedRange<Int> {
        precondition(cacheCount >= visibleCount)
        precondition(limits.upperBound - limits.lowerBound + 1 >= cacheCount)

        let requiredLowerBound = min(currentTop, targetTop)
        let requiredUpperBound = max(currentTop, targetTop) + visibleCount - 1
        let requiredCount = requiredUpperBound - requiredLowerBound + 1
        guard requiredCount <= cacheCount else {
            return cacheWindow(
                around: targetTop,
                direction: nil,
                cacheCount: cacheCount,
                visibleCount: visibleCount,
                limits: limits
            )
        }

        let extraPadding = cacheCount - requiredCount
        return clampedCacheWindow(
            proposedLowerBound: requiredLowerBound - extraPadding / 2,
            cacheCount: cacheCount,
            limits: limits
        )
    }

    static func predictiveCacheWindow(
        currentTop: Int,
        predictedTop: Int,
        direction: CalendarScrollDirection?,
        cacheCount: Int,
        visibleCount: Int,
        limits: ClosedRange<Int>
    ) -> ClosedRange<Int> {
        precondition(cacheCount >= visibleCount)
        let clampedPrediction = min(
            max(predictedTop, currentTop - maximumPredictiveDistance),
            currentTop + maximumPredictiveDistance
        )
        let requiredLower = min(currentTop, clampedPrediction)
        let requiredUpper = max(currentTop, clampedPrediction) + visibleCount - 1
        let requiredCount = requiredUpper - requiredLower + 1

        guard requiredCount <= cacheCount else {
            return cacheWindow(
                around: currentTop,
                direction: direction,
                cacheCount: cacheCount,
                visibleCount: visibleCount,
                limits: limits
            )
        }

        let extra = cacheCount - requiredCount
        let leadingExtra: Int
        switch direction {
        case .later:
            leadingExtra = min(directionalCachePadding, extra)
        case .earlier:
            leadingExtra = max(0, extra - directionalCachePadding)
        case nil:
            leadingExtra = extra / 2
        }
        return clampedCacheWindow(
            proposedLowerBound: requiredLower - leadingExtra,
            cacheCount: cacheCount,
            limits: limits
        )
    }

    private static func clampedCacheWindow(
        proposedLowerBound: Int,
        cacheCount: Int,
        limits: ClosedRange<Int>
    ) -> ClosedRange<Int> {
        let latestLowerBound = limits.upperBound - cacheCount + 1
        let lowerBound = min(
            max(proposedLowerBound, limits.lowerBound),
            latestLowerBound
        )
        return lowerBound...(lowerBound + cacheCount - 1)
    }
}
