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

/// The axis one stroke of the wheel or a swipe moves the strip by, so a stroke that wavers between across and up or
/// down does not turn back on itself: across, or for a wheel that only turns, up and down. Nothing moves till the
/// stroke has gone `MouseDragStart.distance` points or sent `events` events, so a first event a hair off its way, as a
/// Magic Mouse's often is, does not choose it; then the axis it has gone furthest along, kept to its end, and all it
/// has gone that way at once. A delta's sign is the way the content goes, right or down positive, as the system has it,
/// with natural scrolling or without.
public struct ScrollAxisLock: Equatable, Sendable {
    public static let events = 3

    public private(set) var across: Bool?
    private var sum = (x: 0.0, y: 0.0), travel = (x: 0.0, y: 0.0), seen = 0

    public init() {}

    /// The delta the stroke moves the strip by, 0 till it has chosen its axis.
    public mutating func delta(x: Double, y: Double) -> Double {
        if let across { return across ? x : y }
        sum = (sum.x + x, sum.y + y)
        travel = (travel.x + abs(x), travel.y + abs(y))
        seen += 1
        guard hypot(sum.x, sum.y) >= MouseDragStart.distance || seen >= Self.events,
              travel.x != 0 || travel.y != 0 else { return 0 }
        // The way it went on the whole; for one that came back to where it began, the way it went furthest.
        across = abs(sum.x) != abs(sum.y) ? abs(sum.x) > abs(sum.y) : travel.x >= travel.y
        return across! ? sum.x : sum.y
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.across == b.across && a.sum == b.sum && a.travel == b.travel && a.seen == b.seen
    }
}

/// How fast the strip went as the mouse let go of it, from the moves of the last `window` seconds, in each event's own
/// time: none for a mouse that stopped before letting go. Each move covers the time since the one before it, no more
/// than `window`; the first of a hold, since the press when it is known, else a frame.
public struct LetGoVelocity: Equatable, Sendable {
    public static let window: CFTimeInterval = 0.06
    /// Moves older than this are forgotten, all but when the newest of them came.
    public static let kept: CFTimeInterval = 0.12
    static let frame: CFTimeInterval = 1.0 / 120

    private var samples: [(at: CFTimeInterval, delta: Double)] = []
    /// When the move before the oldest kept came, or the press, if known.
    private var before: CFTimeInterval?

    /// `since`, the press the moves follow, when there is one.
    public init(since: CFTimeInterval? = nil) {
        before = since
    }

    public mutating func add(_ delta: Double, at time: CFTimeInterval) {
        samples.append((time, delta))
        while let first = samples.first, time - first.at > Self.kept {
            before = first.at
            samples.removeFirst()
        }
    }

    /// Points a second, at `now`.
    public func velocity(at now: CFTimeInterval) -> Double {
        guard let first = samples.firstIndex(where: { now - $0.at <= Self.window }) else { return 0 }
        let moved = samples[first...].reduce(0) { $0 + $1.delta }
        let start = samples[first].at
        let previous = first > 0 ? samples[first - 1].at : before ?? start - Self.frame
        let since = max(previous, start - Self.window)
        return moved / max(now - since, Self.frame)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.before == b.before && a.samples.elementsEqual(b.samples) { $0.at == $1.at && $0.delta == $1.delta }
    }
}
