import Foundation

/// Where the user is pulling the jelly: an angle (radians, screen coordinates) and a
/// distance from the centre.
public struct JellyPull: Equatable, Sendable {
    public var angle: Double
    public var distance: Double

    public init(angle: Double, distance: Double) {
        self.angle = angle
        self.distance = distance
    }
}

/// A soft-body blob: a ring of points, each with a radius from the centre, held by springs
/// toward a target shape and to their neighbours. Pure value type, stepped by the view.
public struct JellyBody: Equatable, Sendable {
    public let count: Int
    public private(set) var radii: [Double]
    public private(set) var velocities: [Double]
    /// Radius of the relaxed blob. Changing it makes the jelly grow/shrink smoothly.
    public var restRadius: Double
    public var pull: JellyPull?

    public var stiffness = 170.0
    public var coupling = 80.0
    public var damping = 8.0

    public init(count: Int = 32, restRadius: Double) {
        precondition(count >= 6, "a jelly needs at least 6 points")
        self.count = count
        self.restRadius = restRadius
        radii = Array(repeating: restRadius, count: count)
        velocities = Array(repeating: 0, count: count)
    }

    public func angle(of index: Int) -> Double {
        2 * Double.pi * Double(index) / Double(count)
    }

    /// The shape the jelly wants to be in: round, or bulging toward the pull with the far
    /// side thinning slightly (a cheap stand-in for volume preservation).
    public func targetRadius(at index: Int) -> Double {
        guard let pull else { return restRadius }
        let d = Self.angularDistance(angle(of: index), pull.angle)
        let stretch = max(0, pull.distance - restRadius)
        let near = exp(-(d * d) / (2 * 0.5 * 0.5))
        let far = exp(-((Double.pi - d) * (Double.pi - d)) / (2 * 0.9 * 0.9))
        return max(restRadius * 0.6, restRadius + stretch * near - stretch * 0.15 * far)
    }

    /// Advances the simulation. Large or invalid steps are clamped so it can never explode.
    public mutating func step(by dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        let total = min(dt, 1.0 / 20.0)
        let substeps = max(1, Int((total * 240).rounded(.up)))
        let h = total / Double(substeps)
        var acceleration = Array(repeating: 0.0, count: count)
        for _ in 0..<substeps {
            for i in 0..<count {
                let left = radii[(i + count - 1) % count]
                let right = radii[(i + 1) % count]
                acceleration[i] = stiffness * (targetRadius(at: i) - radii[i])
                    + coupling * (left + right - 2 * radii[i])
                    - damping * velocities[i]
            }
            for i in 0..<count {
                velocities[i] += acceleration[i] * h
                radii[i] += velocities[i] * h
            }
        }
    }

    /// Kicks the jelly into an oval wobble (release, poke, pause jiggle).
    public mutating func wobble(strength: Double) {
        for i in 0..<count {
            velocities[i] += strength * cos(2 * angle(of: i))
        }
    }

    /// Jumps straight to the target shape (Reduce Motion).
    public mutating func settle() {
        for i in 0..<count {
            radii[i] = targetRadius(at: i)
            velocities[i] = 0
        }
    }

    public var isSettled: Bool {
        for i in 0..<count where abs(velocities[i]) > 0.3 || abs(radii[i] - targetRadius(at: i)) > 0.3 {
            return false
        }
        return true
    }

    /// Outline points around a centre (screen coordinates: y grows downward).
    public func outline(centerX: Double, centerY: Double) -> [SIMD2<Double>] {
        (0..<count).map { i in
            let a = angle(of: i)
            return SIMD2(centerX + radii[i] * cos(a), centerY + radii[i] * sin(a))
        }
    }

    static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 2 * Double.pi))
        return d > Double.pi ? 2 * Double.pi - d : d
    }
}

/// Maps how far the jelly is stretched (in points, beyond its edge) to a session length:
/// 5-minute steps from 5 to 60, then 15-minute steps up to 3 hours.
public enum JellyDial {
    public static let pointsPerStep = 6.0
    public static let stepCount = 20

    public static var allValues: [Int] { (0..<stepCount).map { minutes(atStep: $0) } }

    public static func minutes(atStep step: Int) -> Int {
        let s = min(max(step, 0), stepCount - 1)
        return s <= 11 ? 5 + 5 * s : 60 + 15 * (s - 11)
    }

    /// The step whose value is the largest one not above `value`.
    public static func step(forMinutes value: Int) -> Int {
        var best = 0
        for s in 0..<stepCount where minutes(atStep: s) <= value {
            best = s
        }
        return best
    }

    public static func minutes(forStretch stretch: Double) -> Int {
        guard stretch.isFinite, stretch > 0 else { return minutes(atStep: 0) }
        let clamped = min(stretch, pointsPerStep * Double(stepCount))
        return minutes(atStep: Int((clamped / pointsPerStep).rounded(.down)))
    }

    /// A stretch that lands in the middle of `value`'s step.
    public static func stretch(forMinutes value: Int) -> Double {
        (Double(step(forMinutes: value)) + 0.5) * pointsPerStep
    }

    /// The value `delta` steps away (arrow keys, VoiceOver), clamped to the range.
    public static func adjusted(_ value: Int, bySteps delta: Int) -> Int {
        minutes(atStep: step(forMinutes: value) + delta)
    }

    /// Visual stretch with rubber-band resistance: follows the pointer at first, then
    /// saturates at `limit` so the jelly never leaves its frame.
    public static func rubberBand(_ stretch: Double, limit: Double) -> Double {
        guard stretch.isFinite, stretch > 0, limit > 0 else { return 0 }
        return limit * (1 - exp(-stretch / limit))
    }
}
