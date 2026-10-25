import Foundation

/// The noop glow showing once: it fades in, holds and fades out. Each press holds it for a while, so presses while it
/// shows, as a held key repeats them, keep it shown until they stop, and one while it fades brings it back: a held key
/// shows it once too.
public struct Pulse {
    /// Seconds it takes to show, or to come back while it fades.
    public static let fadeIn = 0.15
    /// Seconds from a press until it starts to fade, unless the press asks for longer.
    public static let hold = 0.5
    /// Seconds it takes to fade out.
    public static let fadeOut = 0.5

    /// When it last started to show, and how shown it was then.
    private var start: Double
    private var from = 0.0
    /// Until when the presses so far hold it.
    private var held: Double

    /// A press at `time`, in seconds on the clock `press` and `presence` share, holding it `hold` seconds.
    public init(at time: Double, hold: Double = Pulse.hold) {
        start = time
        held = time + hold
    }

    /// When it starts to fade: once it is fully shown and the presses no longer hold it.
    private var fadeStart: Double { max(start + Self.fadeIn, held) }

    /// How shown it is at `time`, from gone (0) to fully shown (1), nil once it has faded out.
    public func presence(at time: Double) -> Double? {
        if time < start + Self.fadeIn { return from + (1 - from) * Self.ease((time - start) / Self.fadeIn) }
        if time < fadeStart { return 1 }
        if time < fadeStart + Self.fadeOut { return 1 - Self.ease((time - fadeStart) / Self.fadeOut) }
        return nil
    }

    /// Another press at `time`: it holds at least `hold` seconds after it, and comes back from where it is if it was
    /// fading. False once it has faded out, when the press needs a pulse of its own.
    @discardableResult
    public mutating func press(at time: Double, hold: Double = Pulse.hold) -> Bool {
        guard let now = presence(at: time) else { return false }
        if time >= fadeStart {
            start = time
            from = now
        }
        held = max(held, time + hold)
        return true
    }

    /// From 0 to 1 along half a cosine: no jolt where it starts or stops.
    private static func ease(_ progress: Double) -> Double {
        (1 - cos(.pi * min(max(progress, 0), 1))) / 2
    }
}

/// The noop glow's look at one moment: the ring around the window, and one band of its colour inside it, `depth`
/// points in at `opacity`. Both fade in and out with the pulse.
public struct GlowBand: Equatable, Sendable {
    /// How far the band reaches into the window, in points.
    public var depth: Double
    /// The band's opacity, 0...1, before the colour's own.
    public var alpha: Double
    /// The ring's opacity.
    public var ring: Double

    public init(depth: Double, opacity: Double, presence: Double) {
        self.depth = depth
        // To 1/256, finer than the eye tells apart: a look that stays the same is not drawn again.
        alpha = (opacity * presence * 256).rounded() / 256
        ring = (presence * 256).rounded() / 256
    }
}
