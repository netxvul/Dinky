import Foundation

/// The noop glow's breathing, the way the screen's edges breathe while Claude uses the computer: bright, dim and bright
/// again, never twice alike. A breath holds bright, dims, holds dim and brightens again, each part lasting a time drawn
/// at random, so one breath may take 1.3 seconds and the next 2.8, about 2 on the whole, as the screen's do. A press fades
/// in bright, brightens `count` times in all at half again Claude's pace and fades out as it dims after the last; presses
/// while it shows, as a held key repeats them, keep it breathing at Claude's own pace until they stop, `count` times at
/// least.
public struct Breathing {
    /// Where the breath is: `level` from dim (0) to bright (1), `presence` from gone (0) to fully shown (1).
    public struct State: Equatable, Sendable {
        public var level: Double
        public var presence: Double

        public init(level: Double, presence: Double) {
            self.level = level
            self.presence = presence
        }
    }

    /// Seconds each part of a breath takes at Claude's pace, drawn anew for every breath.
    public static let brightHold = 0.0...0.6
    public static let fall = 0.65...0.95
    public static let dimHold = 0.0...0.3
    public static let rise = 0.65...0.95
    /// How much faster than Claude a lone press breathes.
    public static let quick = 1.5
    /// Seconds a press takes to show the glow, or to bring back one fading out.
    public static let fadeIn = 0.15
    /// Seconds without a press after which a held glow fades out at its next dimming, once it has brightened `count`
    /// times.
    public static let release = 0.5

    private enum Phase { case fadeIn, brightHold, fall, dimHold, rise, fadeOut }

    private struct Part {
        var phase: Phase
        var start: Double
        var duration: Double
        var from: State
        var to: State

        var end: Double { start + duration }

        /// From `from` to `to` along half a cosine: no jolt where one part meets the next.
        func state(at time: Double) -> State {
            let progress = duration > 0 ? min(max((time - start) / duration, 0), 1) : 1
            let share = (1 - cos(.pi * progress)) / 2
            return State(level: from.level + (to.level - from.level) * share,
                         presence: from.presence + (to.presence - from.presence) * share)
        }
    }

    private static let bright = State(level: 1, presence: 1)
    private static let dim = State(level: 0, presence: 1)

    private let count: Int
    private let random: (ClosedRange<Double>) -> Double
    private var part: Part
    private var brightenings = 1
    private var lastPress: Double
    private var held = false

    /// A press at `time`, in seconds on the clock `press` and `state` share. `random` draws each part's length.
    public init(count: Int, at time: Double, random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.count = max(count, 1)
        self.random = random
        lastPress = time
        part = Part(phase: .fadeIn, start: time, duration: Self.fadeIn,
                    from: State(level: 1, presence: 0), to: Self.bright)
    }

    /// Another press at `time`: the glow keeps breathing, from now on at Claude's pace, and comes back bright if it was
    /// fading out. False once it has faded out, when the press needs a breathing of its own.
    @discardableResult
    public mutating func press(at time: Double) -> Bool {
        guard let now = state(at: time) else { return false }
        lastPress = time
        held = true
        if part.phase == .fadeOut {
            part = Part(phase: .rise, start: time, duration: Self.fadeIn, from: now, to: Self.bright)
        }
        return true
    }

    /// Where the breath is at `time`, nil once it has faded out. Times only move forward.
    public mutating func state(at time: Double) -> State? {
        while time >= part.end {
            guard let next = next() else { return nil }
            part = next
        }
        return part.state(at: time)
    }

    /// The part after the current one, nil after the fade.
    private mutating func next() -> Part? {
        let start = part.end
        let pace = held ? 1 : Self.quick
        func make(_ phase: Phase, _ range: ClosedRange<Double>, _ from: State, _ to: State) -> Part {
            Part(phase: phase, start: start, duration: random(range) / pace, from: from, to: to)
        }
        switch part.phase {
        case .fadeIn, .rise:
            return make(.brightHold, Self.brightHold, Self.bright, Self.bright)
        case .brightHold:
            // Held, presses come faster than this; let go, it fades as it next dims.
            let done = brightenings >= count && (!held || start - lastPress >= Self.release)
            return done ? make(.fadeOut, Self.fall, Self.bright, State(level: 0, presence: 0))
                        : make(.fall, Self.fall, Self.bright, Self.dim)
        case .fall:
            return make(.dimHold, Self.dimHold, Self.dim, Self.dim)
        case .dimHold:
            brightenings += 1
            return make(.rise, Self.rise, Self.dim, Self.bright)
        case .fadeOut:
            return nil
        }
    }
}

/// The noop glow's look at one moment: six bands inside the window, each fainter than the one outside it, and the ring
/// around the window. Bright and fully shown the bands reach `spread` points in at 60% down to 5% of the colour; dim, as
/// the screen's edges are between breaths, they are 65% as strong and reach 70% as far. The ring only fades in and out.
public struct GlowBands: Equatable, Sendable {
    /// Where each band starts and the last one ends, in points in from the window's edge: one more than `alphas`.
    public var edges: [Double]
    /// Each band's opacity, 0...1, before the colour's own.
    public var alphas: [Double]
    /// The ring's opacity.
    public var ring: Double
    /// How far the bands reach at their brightest: all they may ever cover.
    public var spread: Double

    /// The bands' bounds at their brightest, as shares of the spread: 4, 6, 8, 12, 16 and 22 of 68, wider inward.
    static let shares = [0.0, 4, 10, 18, 30, 46, 68].map { $0 / 68 }
    static let brightest = [0.6, 0.48, 0.35, 0.22, 0.12, 0.05]

    public init(spread: Double, state: Breathing.State) {
        let strength = state.presence * (0.65 + 0.35 * state.level)
        let reach = spread * (0.7 + 0.3 * state.presence) * (0.7 + 0.3 * state.level)
        // To a quarter point and 1/256, finer than pixels or the eye tell apart: a look that stays the same is not drawn
        // again.
        edges = Self.shares.map { ($0 * reach * 4).rounded() / 4 }
        alphas = Self.brightest.map { ($0 * strength * 256).rounded() / 256 }
        ring = (state.presence * 256).rounded() / 256
        self.spread = spread
    }
}
