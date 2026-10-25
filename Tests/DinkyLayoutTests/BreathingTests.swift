import Testing
@testable import DinkyLayout

struct BreathingTests {
    /// Every part at the middle of its range.
    let middle: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }

    /// The states at 120 Hz from `start` until it fades out or `limit` seconds have passed.
    func run(_ breathing: inout Breathing, from start: Double = 0, limit: Double = 30) -> [(Double, Breathing.State)] {
        var states: [(Double, Breathing.State)] = []
        var t = start
        while t < start + limit, let state = breathing.state(at: t) {
            states.append((t, state))
            t += 1.0 / 120
        }
        return states
    }

    /// How many times it went from dim to bright, a dim being below a quarter, after a bright above three quarters.
    func brightenings(_ states: [(Double, Breathing.State)]) -> Int {
        var count = 0, dim = false
        for (_, state) in states {
            if state.level < 0.25 { dim = true }
            if state.level > 0.75, dim { count += 1; dim = false }
        }
        return count
    }

    @Test func `A press fades in bright, brightens again and fades out`() {
        var breathing = Breathing(count: 2, at: 0, random: middle)
        let states = run(&breathing)
        #expect(states.first!.1 == Breathing.State(level: 1, presence: 0))
        var fresh = Breathing(count: 2, at: 0, random: middle)
        #expect(fresh.state(at: Breathing.fadeIn) == Breathing.State(level: 1, presence: 1))
        #expect(brightenings(states) == 1)
        // Fade in, then at half again Claude's pace: hold bright, dim, hold dim, brighten, hold bright and fade.
        let parts = [Breathing.brightHold, Breathing.fall, Breathing.dimHold, Breathing.rise, Breathing.brightHold, Breathing.fall]
        let duration = Breathing.fadeIn + parts.map(middle).reduce(0, +) / Breathing.quick
        #expect(abs(states.last!.0 - duration) < 0.01)
        #expect(states.last!.1.presence < 0.01)
        #expect(breathing.state(at: duration + 0.01) == nil)
    }

    @Test func `Count brightenings, then it is over`() {
        for count in 1...5 {
            var breathing = Breathing(count: count, at: 0, random: middle)
            #expect(brightenings(run(&breathing)) == count - 1, "\(count)")
        }
    }

    @Test func `No two breaths alike`() {
        // Each part drawn at the low end of its range, the middle or the high end in turn, held so it keeps breathing.
        var draws = 0
        var breathing = Breathing(count: 1, at: 0) { range in
            defer { draws += 1 }
            return range.lowerBound + (range.upperBound - range.lowerBound) * [0, 0.5, 1][draws % 3]
        }
        var rises: [Double] = []
        var last = 1.0
        var t = 0.0
        while t < 12 {
            // press is mutating, which #expect cannot call, so its answer is taken first.
            let pressed = breathing.press(at: t)
            #expect(pressed)
            let level = breathing.state(at: t)!.level
            if last < 0.5, level >= 0.5 { rises.append(t) }
            last = level
            t += 1.0 / 120
        }
        let lengths = zip(rises, rises.dropFirst()).map { $1 - $0 }
        #expect(lengths.count >= 3)
        #expect(lengths.max()! - lengths.min()! > 0.3)
    }

    @Test func `Held, it keeps breathing until let go`() {
        var breathing = Breathing(count: 2, at: 0, random: middle)
        // A key repeating every 50 ms for 8 seconds.
        var t = 0.0
        var states: [(Double, Breathing.State)] = []
        while t < 8 {
            let pressed = breathing.press(at: t)
            #expect(pressed)
            states.append((t, breathing.state(at: t)!))
            t += 0.05
        }
        #expect(states.allSatisfy { $0.1.presence > 0.99 || $0.0 < Breathing.fadeIn })
        // About 2 seconds a breath at the middle of every range.
        let breath = [Breathing.brightHold, Breathing.fall, Breathing.dimHold, Breathing.rise].map(middle).reduce(0, +)
        #expect(abs(breath - 2.05) < 1e-9)
        #expect(brightenings(states) >= 3)
        // Let go, it fades out within a breath and a fade.
        let rest = run(&breathing, from: 8)
        #expect(rest.last!.0 - 8 < Breathing.release + breath + Breathing.fall.upperBound)
        #expect(breathing.state(at: 8 + 10) == nil)
    }

    @Test func `A press while it fades brings it back`() {
        var breathing = Breathing(count: 1, at: 0, random: middle)
        let states = run(&breathing)
        let end = states.last!.0
        var again = Breathing(count: 1, at: 0, random: middle)
        let fading = again.state(at: end - 0.1)!
        #expect(fading.presence < 0.5)
        let pressed = again.press(at: end - 0.1)
        #expect(pressed)
        #expect(again.state(at: end - 0.1 + Breathing.fadeIn)! == Breathing.State(level: 1, presence: 1))
        #expect(again.state(at: end + 0.5) != nil)
        // Once faded out, a press needs a breathing of its own.
        let late = breathing.press(at: end + 1)
        #expect(!late)
    }

    @Test func `Bands at the brightest, dim and gone`() {
        let bright = GlowBands(spread: 68, state: Breathing.State(level: 1, presence: 1))
        #expect(bright.edges == [0, 4, 10, 18, 30, 46, 68])
        #expect(zip(bright.alphas, [0.6, 0.48, 0.35, 0.22, 0.12, 0.05]).allSatisfy { abs($0 - $1) <= 1.0 / 512 })
        #expect(bright.ring == 1)
        #expect(bright.spread == 68)
        // Dim, 65% as strong and reaching 70% as far; the ring stays.
        let dim = GlowBands(spread: 68, state: Breathing.State(level: 0, presence: 1))
        #expect(abs(dim.edges.last! - 68 * 0.7) <= 0.125)
        #expect(abs(dim.alphas[0] - 0.6 * 0.65) <= 1.0 / 512)
        #expect(dim.ring == 1)
        let gone = GlowBands(spread: 68, state: Breathing.State(level: 1, presence: 0))
        #expect(gone.alphas.allSatisfy { $0 == 0 })
        #expect(gone.ring == 0)
        // Bands wider inward, each fainter than the one outside it.
        let widths = zip(bright.edges, bright.edges.dropFirst()).map { $1 - $0 }
        #expect(widths == widths.sorted())
        #expect(bright.alphas == bright.alphas.sorted(by: >))
    }

    @Test func `A look that barely moves is the same look`() {
        let a = GlowBands(spread: 68, state: Breathing.State(level: 0.5, presence: 1))
        let b = GlowBands(spread: 68, state: Breathing.State(level: 0.5001, presence: 1))
        #expect(a == b)
    }
}
