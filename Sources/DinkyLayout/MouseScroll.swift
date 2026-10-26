import CoreGraphics
import Foundation

// The mouse scrolling a strip (`[gestures.mouse-scroll]`): a press dragged with the modifier held, or a swipe or wheel
// with it, moves the strip as fingers on the trackpad do. What is measured here is the pure part: when a drag starts
// to hold the strip, which axis a stroke of the wheel moves it by, and how fast the strip went as the mouse let go.

/// Whether a press dragged from where it went down holds the strip yet: once it is `distance` points away, and has gone
/// mostly across rather than up or down. A press that has gone up or down holds nothing till it goes across.
public enum MouseDragStart {
    public static let distance: CGFloat = 4

    public static func holds(dx: CGFloat, dy: CGFloat) -> Bool {
        hypot(dx, dy) >= distance && abs(dx) >= abs(dy)
    }
}

/// The axis one stroke of the wheel or a swipe moves the strip by, chosen by its first move and kept to its end, so a
/// stroke that wavers between across and up or down does not turn back on itself: across, or for a wheel that only
/// turns, up and down. A delta's sign is the way the content goes, right or down positive, as the system has it, with
/// natural scrolling or without.
public struct ScrollAxisLock: Equatable, Sendable {
    public private(set) var across: Bool?

    public init() {}

    /// The delta the stroke moves the strip by, 0 till it has moved.
    public mutating func delta(x: Double, y: Double) -> Double {
        if across == nil, x != 0 || y != 0 { across = abs(x) >= abs(y) }
        guard let across else { return 0 }
        return across ? x : y
    }
}

/// How fast the strip went as the mouse let go of it, from the moves of the last `window` seconds: none for a mouse
/// that stopped before letting go.
public struct LetGoVelocity: Equatable, Sendable {
    public static let window: CFTimeInterval = 0.06

    private var samples: [(at: CFTimeInterval, delta: Double)] = []

    public init() {}

    public mutating func add(_ delta: Double, at time: CFTimeInterval) {
        samples.append((time, delta))
        samples.removeAll { time - $0.at > 2 * Self.window }
    }

    /// Points a second, at `now`.
    public func velocity(at now: CFTimeInterval) -> Double {
        guard let first = samples.firstIndex(where: { now - $0.at <= Self.window }) else { return 0 }
        let moved = samples[first...].reduce(0) { $0 + $1.delta }
        // Each move covers the time since the one before it, at most the window after a pause; the very first, a frame.
        let since = first > 0 ? max(samples[first - 1].at, samples[first].at - Self.window) : samples[first].at - 1.0 / 120
        return moved / max(now - since, 1.0 / 120)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.samples.elementsEqual(b.samples) { $0.at == $1.at && $0.delta == $1.delta }
    }
}
