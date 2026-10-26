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
    @Test func `A stroke keeps the axis it began on`() {
        var lock = ScrollAxisLock()
        #expect(lock.delta(x: 0, y: 0) == 0, "nothing moved, no axis yet")
        #expect(lock.across == nil)
        #expect(lock.delta(x: -6, y: 2) == -6)
        #expect(lock.across == true)
        #expect(lock.delta(x: 1, y: 9) == 1, "wavering up or down later does not turn it")
        #expect(lock.delta(x: 0, y: 5) == 0)
    }

    @Test func `A wheel that only turns moves the strip by its turns`() {
        var lock = ScrollAxisLock()
        #expect(lock.delta(x: 0, y: 12) == 12)
        #expect(lock.across == false)
        #expect(lock.delta(x: 30, y: -3) == -3)
    }
}

struct LetGoVelocityTests {
    @Test func `Velocity is the moves of the last 60 ms`() {
        var v = LetGoVelocity()
        // 10 points every 10 ms: 1000 points a second.
        for i in 0...10 { v.add(10, at: Double(i) * 0.01) }
        #expect(abs(v.velocity(at: 0.1) - 1000) < 1)
        // Moves long before do not count.
        var slow = LetGoVelocity()
        slow.add(500, at: 0)
        for i in 1...10 { slow.add(2, at: 0.5 + Double(i) * 0.01) }
        #expect(abs(slow.velocity(at: 0.6) - 200) < 1)
    }

    @Test func `A mouse that stopped before letting go lets go still`() {
        var v = LetGoVelocity()
        for i in 0...10 { v.add(10, at: Double(i) * 0.01) }
        #expect(v.velocity(at: 0.1 + LetGoVelocity.window + 0.01) == 0)
        #expect(LetGoVelocity().velocity(at: 1) == 0, "nothing moved")
    }

    @Test func `A flick of one move counts at its own pace`() {
        var v = LetGoVelocity()
        v.add(-24, at: 1)
        // The first move covers a frame before it.
        #expect(abs(v.velocity(at: 1) - -24 * 120) < 1)
        #expect(v.velocity(at: 1.02) < 0)
    }
}
