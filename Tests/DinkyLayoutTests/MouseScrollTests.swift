import CoreGraphics
import Testing
@testable import DinkyLayout

struct MouseDragStartTests {
    @Test func `A press holds the strip once it has gone 4 points, mostly across`() {
        #expect(!MouseDragStart.holds(dx: 0, dy: 0))
        #expect(!MouseDragStart.holds(dx: 3, dy: 0), "a click that wobbled")
        #expect(MouseDragStart.holds(dx: 4, dy: 0))
        #expect(MouseDragStart.holds(dx: -4, dy: 1))
        #expect(MouseDragStart.holds(dx: 3, dy: 3), "as far across as up")
        #expect(!MouseDragStart.holds(dx: 2, dy: 6), "up or down holds nothing")
        #expect(!MouseDragStart.holds(dx: 0, dy: -10))
    }
}

struct ScrollAxisLockTests {
    @Test func `A stroke keeps the axis it chose`() {
        var lock = ScrollAxisLock()
        #expect(lock.delta(x: -6, y: 2) == -6, "4 points along at once")
        #expect(lock.across == true)
        #expect(lock.delta(x: 1, y: 9) == 1, "wavering up or down later does not turn it")
        #expect(lock.delta(x: 0, y: 5) == 0)
    }

    @Test func `A first event a hair off its way does not choose the axis`() {
        var lock = ScrollAxisLock()
        #expect(lock.delta(x: 0, y: 1) == 0, "too little to choose by")
        #expect(lock.across == nil)
        #expect(lock.delta(x: -8, y: 1) == -8, "across, with all it has gone that way")
        #expect(lock.across == true)
        #expect(lock.delta(x: -8, y: 1) == -8)
    }

    @Test func `A wheel that only turns moves the strip by its turns`() {
        var lock = ScrollAxisLock()
        #expect(lock.delta(x: 0, y: 12) == 12)
        #expect(lock.across == false)
        #expect(lock.delta(x: 30, y: -3) == -3)
    }

    @Test func `Three small events choose the axis however little they went`() {
        var lock = ScrollAxisLock()
        #expect(lock.delta(x: 1, y: 0) == 0)
        #expect(lock.delta(x: 1, y: 0.5) == 0)
        #expect(lock.delta(x: 1, y: 0) == 3)
        #expect(lock.across == true)
        var still = ScrollAxisLock()
        for _ in 0..<4 { #expect(still.delta(x: 0, y: 0) == 0) }
        #expect(still.across == nil, "nothing moved")
    }
}

struct LetGoVelocityTests {
    @Test func `Velocity is the moves of the last 60 ms`() {
        var v = LetGoVelocity()
        // 10 points every 10 ms: 1000 points a second.
        for i in 0...10 { v.add(10, at: Double(i) * 0.01) }
        #expect(abs(v.velocity(at: 0.1) - 1000) < 1)
        var slow = LetGoVelocity()
        slow.add(500, at: 0)
        for i in 1...10 { slow.add(2, at: 0.5 + Double(i) * 0.01) }
        #expect(abs(slow.velocity(at: 0.6) - 200) < 1, "moves long before do not count")
    }

    @Test func `A mouse that stopped before letting go lets go still`() {
        var v = LetGoVelocity()
        for i in 0...10 { v.add(10, at: Double(i) * 0.01) }
        #expect(v.velocity(at: 0.1 + LetGoVelocity.window + 0.01) == 0)
        #expect(LetGoVelocity().velocity(at: 1) == 0, "nothing moved")
    }

    @Test func `One move after a pause counts over the window, not a frame`() {
        var v = LetGoVelocity()
        for i in 0...10 { v.add(10, at: Double(i) * 0.01) }
        // Still for 0.2 s, then 3 points.
        v.add(3, at: 0.3)
        let after = v.velocity(at: 0.304)
        #expect(abs(after - 3 / 0.064) < 1, "about 47, not 3 points over a frame: \(after)")
    }

    @Test func `The first move of a hold counts from the press`() {
        // A slow wander from the press to the 4 points a drag starts at.
        var v = LetGoVelocity(since: 0)
        v.add(4, at: 0.2)
        #expect(abs(v.velocity(at: 0.2) - 4 / LetGoVelocity.window) < 1, "over the window at most: \(v.velocity(at: 0.2))")
        var quick = LetGoVelocity(since: 0)
        quick.add(4, at: 0.02)
        #expect(abs(quick.velocity(at: 0.02) - 200) < 1)
        // Without a press, the very first move counts a frame.
        var first = LetGoVelocity()
        first.add(-24, at: 1)
        #expect(abs(first.velocity(at: 1) - -24 * 120) < 1)
    }
}
