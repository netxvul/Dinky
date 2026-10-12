import CoreGraphics

/// A damped spring on one value, SwiftUI style: `response` is roughly the time to arrive,
/// `damping` 1 arrives without overshoot. Semi-implicit Euler with substeps short enough to stay stable.
public struct Spring: Equatable, Sendable {
    public let stiffness: Double
    public let friction: Double

    public init(response: Double, damping: Double) {
        let omega = 2 * Double.pi / max(response, 0.001)
        stiffness = omega * omega
        friction = 2 * damping * omega
    }

    /// Advance `value` and `velocity` towards `target` by `dt` seconds.
    public func step(_ value: inout Double, _ velocity: inout Double, to target: Double, dt: Double) {
        let limit = 0.5 / max(stiffness.squareRoot(), friction)
        let steps = max(1, Int((dt / limit).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            velocity += (stiffness * (target - value) - friction * velocity) * h
            value += velocity * h
        }
    }
}

/// A timing function from easings.net, as yabai's `window_animation_easing` offers: progress 0...1 in, the share
/// of the way covered out, 0 at the start and 1 at the end.
public enum Easing: String, CaseIterable, Sendable {
    case linear
    case easeInSine = "ease-in-sine", easeOutSine = "ease-out-sine", easeInOutSine = "ease-in-out-sine"
    case easeInQuad = "ease-in-quad", easeOutQuad = "ease-out-quad", easeInOutQuad = "ease-in-out-quad"
    case easeInCubic = "ease-in-cubic", easeOutCubic = "ease-out-cubic", easeInOutCubic = "ease-in-out-cubic"
    case easeInQuart = "ease-in-quart", easeOutQuart = "ease-out-quart", easeInOutQuart = "ease-in-out-quart"
    case easeInQuint = "ease-in-quint", easeOutQuint = "ease-out-quint", easeInOutQuint = "ease-in-out-quint"
    case easeInExpo = "ease-in-expo", easeOutExpo = "ease-out-expo", easeInOutExpo = "ease-in-out-expo"
    case easeInCirc = "ease-in-circ", easeOutCirc = "ease-out-circ", easeInOutCirc = "ease-in-out-circ"

    public func callAsFunction(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        guard self != .linear else { return t }
        let ease = Self.easeIn(family)
        // Every ease-out is the ease-in run backwards, and every ease-in-out the ease-in for the first half and
        // the ease-out for the second, as easings.net defines them.
        if rawValue.hasPrefix("ease-in-out-") { return t < 0.5 ? ease(2 * t) / 2 : 1 - ease(2 - 2 * t) / 2 }
        if rawValue.hasPrefix("ease-out-") { return 1 - ease(1 - t) }
        return ease(t)
    }

    /// The last word of the name: sine, quad, cubic, quart, quint, expo or circ.
    private var family: Substring { rawValue.split(separator: "-").last! }

    private static func easeIn(_ family: Substring) -> (Double) -> Double {
        switch family {
        case "sine": { 1 - cos($0 * .pi / 2) }
        case "quad": { $0 * $0 }
        case "cubic": { pow($0, 3) }
        case "quart": { pow($0, 4) }
        case "quint": { pow($0, 5) }
        case "expo": { $0 == 0 ? 0 : pow(2, 10 * $0 - 10) }
        case "circ": { 1 - (1 - $0 * $0).squareRoot() }
        default: { $0 }
        }
    }
}

/// How a window travels to its tile: on a spring, or along an easing over a fixed time.
public enum AnimationCurve: Equatable, Sendable {
    case spring(Spring)
    case eased(Easing, duration: Double)
}

/// One window moving from where it is to its tile: x, y, width and height each on the same curve,
/// so shared edges of neighbouring windows move together.
public struct FrameAnimation: Equatable, Sendable {
    private var target: CGRect
    private var value: [Double]
    private var velocity: [Double] = [0, 0, 0, 0]
    /// Seconds since the target last changed, to give up on one that never settles, and how far along an
    /// easing it is.
    private var age: Double = 0
    /// Where an eased animation set out from: the start, or where the window was when the target last changed.
    private var origin: [Double]

    public init(from start: CGRect, to target: CGRect) {
        self.target = target
        value = Self.components(start)
        origin = value
    }

    /// The frame now, rounded to whole points so a pure move does not jitter the size.
    public var frame: CGRect {
        CGRect(x: value[0].rounded(), y: value[1].rounded(), width: value[2].rounded(), height: value[3].rounded())
    }

    /// Head somewhere else from where it is. On a spring the speed carries over, so the motion stays continuous; an
    /// easing starts over from here.
    public mutating func retarget(_ new: CGRect) {
        guard new != target else { return }
        target = new
        age = 0
        origin = value
    }

    /// Advance by `dt` seconds on a spring. True once at rest on the target, or after `timeout` seconds.
    public mutating func step(_ spring: Spring, dt: Double, timeout: Double) -> Bool {
        step(.spring(spring), dt: dt, timeout: timeout)
    }

    /// Advance by `dt` seconds. True once at rest on the target, at the end of an easing, or after `timeout` seconds.
    public mutating func step(_ curve: AnimationCurve, dt: Double, timeout: Double) -> Bool {
        age += dt
        let goal = Self.components(target)
        let settled: Bool
        switch curve {
        case .spring(let spring):
            for i in 0..<4 { spring.step(&value[i], &velocity[i], to: goal[i], dt: dt) }
            settled = (0..<4).allSatisfy { abs(value[$0] - goal[$0]) < 0.5 && abs(velocity[$0]) < 10 }
        case .eased(let easing, let duration):
            let progress = duration > 0 ? min(age / duration, 1) : 1
            let share = easing(progress)
            for i in 0..<4 { value[i] = origin[i] + (goal[i] - origin[i]) * share }
            settled = progress >= 1
        }
        if settled || age >= timeout {
            value = goal
            origin = goal
            velocity = [0, 0, 0, 0]
            return true
        }
        return false
    }

    private static func components(_ r: CGRect) -> [Double] {
        [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
    }
}
