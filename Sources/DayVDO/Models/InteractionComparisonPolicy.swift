import Foundation

/// Experimental policies for the isolated interaction lab. Production keeps
/// its existing snapping, reordering, autoscroll and zoom defaults.
enum InteractionComparisonPolicy {
    static func zoom(current: Double, target: Double, elapsed: Double) -> Double {
        let target = min(180, max(45, target))
        guard abs(target - current) >= 0.1 else { return target }
        let alpha = 1 - pow(0.55, max(0, min(elapsed, 0.1)) / 0.016)
        return current + (target - current) * alpha
    }

    static func edgeVelocity(pointer: Double, height: Double) -> Double {
        let width = min(36, max(0, height / 2))
        guard width > 0 else { return 0 }
        if pointer < width { return -240 * pow(min(1, max(0, (width - pointer) / width)), 2) }
        if pointer > height - width { return 240 * pow(min(1, max(0, (pointer - height + width) / width)), 2) }
        return 0
    }

    struct Snap: Equatable {
        private(set) var held: Double?
        mutating func value(pointer: Double, boundaries: [Double], enabled: Bool) -> Double {
            if enabled, let held, boundaries.contains(held), abs(pointer - held) <= 9 { return held }
            held = boundaries.filter { abs($0 - pointer) <= 6 }.min {
                let left = abs($0 - pointer), right = abs($1 - pointer)
                return left == right ? $0 < $1 : left < right
            }
            return held ?? pointer
        }
        mutating func reset() { held = nil }
    }

    static func crossesRow(pointer: Double, midpoint: Double, movingDown: Bool) -> Bool {
        movingDown ? pointer > midpoint + 4 : pointer < midpoint - 4
    }
}
