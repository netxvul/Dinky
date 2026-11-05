import Testing
@testable import KexLayout

struct ScrollGuardTests {
    private typealias Phase = ScrollGuard.ScrollPhase

    /// A scroll event: its phase, its momentum phase, whether the gesture's fingers are down, and when.
    private struct Event {
        var phase: Int64 = 0
        var momentum: Int64 = 0
        var fingers: Bool
        var at: Double
    }

    /// What becomes of each of `events` in turn, and the guard after them.
    private func run(_ events: [Event], on start: ScrollGuard = ScrollGuard()) -> ([ScrollGuard.Verdict], ScrollGuard) {
        var guard_ = start
        let verdicts = events.map { guard_.scroll(phase: $0.phase, momentum: $0.momentum, fingers: $0.fingers, at: $0.at) }
        return (verdicts, guard_)
    }

    @Test func `A stroke begun with the fingers down is swallowed whole, its momentum with it`() {
        let (verdicts, after) = run([
            Event(phase: Phase.mayBegin, fingers: true, at: 0),
            Event(phase: Phase.began, fingers: true, at: 0.01),
            Event(phase: Phase.changed, fingers: true, at: 0.02),
            // A finger lifting on the way gives nothing back.
            Event(phase: Phase.changed, fingers: false, at: 0.03),
            Event(phase: Phase.ended, fingers: false, at: 0.04),
            Event(momentum: 1, fingers: false, at: 0.05),
            Event(momentum: 2, fingers: false, at: 0.06),
            Event(momentum: Phase.momentumEnded, fingers: false, at: 0.07),
            // The next is the app's.
            Event(phase: Phase.began, fingers: false, at: 0.5),
        ])
        #expect(verdicts == Array(repeating: .swallow, count: 8) + [.pass])
        #expect(!after.holding)
    }

    @Test func `A stroke taken holds till its momentum ends`() {
        let (_, after) = run([
            Event(phase: Phase.began, fingers: true, at: 0),
            Event(phase: Phase.ended, fingers: false, at: 0.01),
            Event(momentum: 1, fingers: false, at: 0.02),
        ])
        #expect(after.holding)
    }

    @Test func `Fingers joining a stroke end it for the app there and take the rest`() {
        let (verdicts, after) = run([
            Event(phase: Phase.began, fingers: false, at: 0),
            Event(phase: Phase.changed, fingers: false, at: 0.01),
            Event(phase: Phase.changed, fingers: true, at: 0.02),
            Event(phase: Phase.changed, fingers: true, at: 0.03),
            // Ended for the app once already.
            Event(phase: Phase.ended, fingers: true, at: 0.04),
            Event(momentum: 1, fingers: false, at: 0.05),
            Event(momentum: Phase.momentumEnded, fingers: false, at: 0.06),
        ])
        #expect(verdicts == [.pass, .pass, .end, .swallow, .swallow, .swallow, .swallow])
        #expect(!after.holding)
    }

    @Test func `A stroke heard first mid-way, the fingers already down, ends for the app`() {
        // The tap went on as they landed, after the stroke began.
        let (verdicts, _) = run([
            Event(phase: Phase.changed, fingers: true, at: 0),
            Event(phase: Phase.changed, fingers: true, at: 0.01),
        ])
        #expect(verdicts == [.end, .swallow])
    }

    @Test func `Fingers landing between a stroke's first touch and its start end what the app heard`() {
        let (verdicts, _) = run([
            Event(phase: Phase.mayBegin, fingers: false, at: 0),
            Event(phase: Phase.began, fingers: true, at: 0.01),
            Event(phase: Phase.changed, fingers: true, at: 0.02),
        ])
        #expect(verdicts == [.pass, .end, .swallow])
    }

    @Test func `A stroke the app ended as the fingers landed keeps its momentum from it`() {
        let (verdicts, _) = run([
            Event(phase: Phase.changed, fingers: false, at: 0),
            // The app has its end.
            Event(phase: Phase.ended, fingers: true, at: 0.01),
            Event(momentum: 1, fingers: true, at: 0.02),
            Event(momentum: Phase.momentumEnded, fingers: false, at: 0.03),
        ])
        #expect(verdicts == [.pass, .pass, .swallow, .swallow])
    }

    @Test func `Without the fingers, every stroke and its momentum are the app's`() {
        let (verdicts, after) = run([
            Event(phase: Phase.mayBegin, fingers: false, at: 0),
            Event(phase: Phase.began, fingers: false, at: 0),
            Event(phase: Phase.changed, fingers: false, at: 0),
            Event(phase: Phase.ended, fingers: false, at: 0),
            Event(momentum: 1, fingers: false, at: 0.01),
            // Fingers landing on momentum the app already has stop it themselves.
            Event(momentum: 2, fingers: true, at: 0.02),
            Event(momentum: Phase.momentumEnded, fingers: false, at: 0.03),
        ])
        #expect(verdicts == Array(repeating: .pass, count: 7))
        #expect(!after.holding)
    }

    @Test func `A wheel without phases is swallowed only while the fingers are down`() {
        let (verdicts, after) = run([Event(fingers: true, at: 0), Event(fingers: false, at: 0.01)])
        #expect(verdicts == [.swallow, .pass])
        #expect(!after.holding)
    }

    @Test func `A new stroke without the fingers starts over`() {
        let (verdicts, _) = run([
            Event(phase: Phase.began, fingers: true, at: 0),
            Event(phase: Phase.ended, fingers: false, at: 0.01),
            // No momentum came; the next stroke is the app's.
            Event(phase: Phase.began, fingers: false, at: 0.2),
            Event(phase: Phase.changed, fingers: false, at: 0.21),
        ])
        #expect(verdicts == [.swallow, .swallow, .pass, .pass])
    }

    @Test func `A stroke taken whose end went by unheard goes stale`() {
        var (_, taken) = run([Event(phase: Phase.began, fingers: true, at: 0)])
        let early = taken.expire(at: 0.5)
        #expect(!early && taken.holding)
        let late = taken.expire(at: 1.5)
        #expect(late && !taken.holding)
        // Stale before it was heard from again: its momentum is the app's.
        let (verdicts, _) = run([
            Event(phase: Phase.changed, fingers: true, at: 0),
            Event(momentum: 2, fingers: false, at: 2),
        ])
        #expect(verdicts == [.end, .pass])
    }
}
