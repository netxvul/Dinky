import Testing
@testable import DinkyLayout

struct PulseTests {
    /// The presence at 120 Hz from `start` until it fades out or `limit` seconds have passed.
    func run(_ pulse: Pulse, from start: Double = 0, limit: Double = 30) -> [(Double, Double)] {
        var states: [(Double, Double)] = []
        var t = start
        while t < start + limit, let presence = pulse.presence(at: t) {
            states.append((t, presence))
            t += 1.0 / 120
        }
        return states
    }

    /// How many times it went from rising to falling.
    func peaks(_ states: [(Double, Double)]) -> Int {
        var count = 0, rising = true
        for (a, b) in zip(states, states.dropFirst()) {
            if b.1 < a.1, rising { count += 1; rising = false }
            if b.1 > a.1 { rising = true }
        }
        return count
    }

    @Test func `A press fades in, holds and fades out once`() {
        let pulse = Pulse(at: 0)
        #expect(pulse.presence(at: 0) == 0)
        #expect(pulse.presence(at: Pulse.fadeIn) == 1)
        #expect(pulse.presence(at: Pulse.hold - 0.01) == 1)
        #expect(abs(pulse.presence(at: Pulse.hold + Pulse.fadeOut / 2)! - 0.5) < 1e-9)
        let states = run(pulse)
        #expect(peaks(states) == 1)
        #expect(abs(states.last!.0 - (Pulse.hold + Pulse.fadeOut)) < 0.01)
        #expect(states.last!.1 < 0.01)
        #expect(pulse.presence(at: Pulse.hold + Pulse.fadeOut) == nil)
    }

    @Test func `Held, it stays shown until let go, then fades once`() {
        var pulse = Pulse(at: 0)
        // A key repeating every 50 ms for 4 seconds.
        var t = 0.05, last = 0.0
        while t < 4 {
            let pressed = pulse.press(at: t)
            #expect(pressed)
            if t >= Pulse.fadeIn { #expect(pulse.presence(at: t) == 1) }
            last = t
            t += 0.05
        }
        let states = run(pulse)
        #expect(peaks(states) == 1)
        #expect(pulse.presence(at: last + Pulse.hold - 0.01) == 1)
        #expect(pulse.presence(at: last + Pulse.hold + Pulse.fadeOut) == nil)
    }

    @Test func `Held with a slow key repeat, it stays shown until the first repeat comes`() {
        // The slowest delay until repeat in Keyboard settings, about 1.8 seconds, then a repeat every 90 ms.
        var pulse = Pulse(at: 0, hold: 1.8 + 0.1)
        var t = 1.8
        while t < 3 {
            let pressed = pulse.press(at: t)
            #expect(pressed)
            #expect(pulse.presence(at: t) == 1)
            t += 0.09
        }
        #expect(peaks(run(pulse)) == 1)
    }

    @Test func `A press while it fades brings it back without a jump`() {
        var pulse = Pulse(at: 0)
        let t = Pulse.hold + Pulse.fadeOut * 0.6
        let fading = pulse.presence(at: t)!
        #expect(fading < 0.5)
        // press is mutating, which #expect cannot call, so its answer is taken first.
        let pressed = pulse.press(at: t)
        #expect(pressed)
        #expect(pulse.presence(at: t) == fading)
        #expect(pulse.presence(at: t + Pulse.fadeIn) == 1)
        #expect(pulse.presence(at: t + Pulse.hold - 0.01) == 1)
        #expect(pulse.presence(at: t + Pulse.hold + Pulse.fadeOut) == nil)
        // Every step small: no frame jumps.
        let states = run(pulse, from: t)
        #expect(zip(states, states.dropFirst()).allSatisfy { abs($1.1 - $0.1) < 0.15 })
    }

    @Test func `Once faded out, a press needs a pulse of its own`() {
        var pulse = Pulse(at: 0)
        let late = pulse.press(at: Pulse.hold + Pulse.fadeOut + 0.1)
        #expect(!late)
        #expect(pulse.presence(at: Pulse.hold + Pulse.fadeOut + 0.1) == nil)
    }

    @Test func `One band, at its opacity when shown, gone with the ring`() {
        let shown = GlowBand(depth: 12, opacity: 0.35, presence: 1)
        #expect(shown.depth == 12)
        #expect(abs(shown.alpha - 0.35) <= 1.0 / 512)
        #expect(shown.ring == 1)
        let half = GlowBand(depth: 12, opacity: 0.35, presence: 0.5)
        #expect(abs(half.alpha - 0.175) <= 1.0 / 512)
        #expect(half.ring == 0.5)
        let gone = GlowBand(depth: 12, opacity: 0.35, presence: 0)
        #expect(gone.alpha == 0)
        #expect(gone.ring == 0)
    }

    @Test func `A look that barely moves is the same look`() {
        let a = GlowBand(depth: 12, opacity: 0.35, presence: 0.5)
        let b = GlowBand(depth: 12, opacity: 0.35, presence: 0.5001)
        #expect(a == b)
    }
}
