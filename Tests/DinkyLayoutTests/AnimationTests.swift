import CoreGraphics
import Testing
@testable import DinkyLayout

struct AnimationTests {
    let spring = Spring(response: 0.2, damping: 0.85)

    /// Steps at 60 Hz until settled; the frames on the way.
    func run(_ animation: inout FrameAnimation, dt: Double = 1.0 / 60, timeout: Double = 5) -> [CGRect] {
        var frames: [CGRect] = []
        while !animation.step(spring, dt: dt, timeout: timeout) { frames.append(animation.frame) }
        return frames
    }

    @Test func `Settles exactly on the target`() {
        var a = FrameAnimation(from: rect(0, 0, 500, 500), to: rect(500, 0, 500, 1000))
        let frames = run(&a)
        #expect(a.frame == rect(500, 0, 500, 1000))
        #expect(frames.count > 5)
        #expect(frames.count < 60)
    }

    @Test func `A move keeps its size`() {
        var a = FrameAnimation(from: rect(0, 0, 500, 500), to: rect(300, 100, 500, 500))
        #expect(run(&a).allSatisfy { $0.size == CGSize(width: 500, height: 500) })
    }

    @Test func `Stays stable with long frames`() {
        let stiff = Spring(response: 0.03, damping: 0.85)
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<30 { _ = a.step(stiff, dt: 1.0 / 30, timeout: 5) }
        #expect(a.frame == rect(1000, 0, 100, 100))
    }

    @Test func `Carries on from where it was written instead`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<5 { _ = a.step(spring, dt: 1.0 / 60, timeout: 5) }
        a.carryOn(from: rect(400, 0, 300, 100))
        #expect(a.frame == rect(400, 0, 300, 100))
        let frames = run(&a)
        #expect(frames.first!.minX > 400)
        #expect(a.frame == rect(1000, 0, 100, 100))
    }

    @Test func `Retargeting keeps going from where it is`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<5 { _ = a.step(spring, dt: 1.0 / 60, timeout: 5) }
        var fresh = FrameAnimation(from: a.frame, to: rect(0, 0, 100, 100))
        a.retarget(rect(0, 0, 100, 100))
        _ = a.step(spring, dt: 1.0 / 60, timeout: 5)
        _ = fresh.step(spring, dt: 1.0 / 60, timeout: 5)
        // The rightward speed carries over, so it turns around later than a window starting at rest.
        #expect(a.frame.minX > fresh.frame.minX)
        _ = run(&a)
        #expect(a.frame == rect(0, 0, 100, 100))
    }

    @Test func `Gives up after the timeout`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        #expect(a.step(spring, dt: 0.1, timeout: 0.1) == true)
        #expect(a.frame == rect(1000, 0, 100, 100))
    }
}

struct EasingTests {
    @Test(arguments: Easing.allCases)
    func `Starts at 0 and ends at 1`(easing: Easing) {
        #expect(abs(easing(0)) < 1e-9)
        #expect(abs(easing(1) - 1) < 1e-9)
        // Clamped outside 0...1.
        #expect(abs(easing(-1)) < 1e-9)
        #expect(abs(easing(2) - 1) < 1e-9)
    }

    @Test(arguments: Easing.allCases)
    func `Never goes back or past the end`(easing: Easing) {
        let values = (0...100).map { easing(Double($0) / 100) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
        #expect(values.allSatisfy { (-1e-9...(1 + 1e-9)).contains($0) })
    }

    @Test func `Values match easings.net`() {
        #expect(abs(Easing.easeInQuad(0.5) - 0.25) < 1e-9)
        #expect(abs(Easing.easeOutQuad(0.5) - 0.75) < 1e-9)
        #expect(abs(Easing.easeInOutCubic(0.25) - 4 * pow(0.25, 3)) < 1e-9)
        #expect(abs(Easing.easeOutCubic(0.25) - (1 - pow(0.75, 3))) < 1e-9)
        #expect(abs(Easing.easeOutSine(0.5) - sin(.pi / 4)) < 1e-9)
        #expect(abs(Easing.easeOutExpo(0.5) - (1 - pow(2, -5))) < 1e-9)
        #expect(abs(Easing.easeInCirc(0.5) - (1 - 0.75.squareRoot())) < 1e-9)
        #expect(abs(Easing.linear(0.3) - 0.3) < 1e-9)
        // In-outs are symmetric about the middle.
        for easing in Easing.allCases where easing.rawValue.hasPrefix("ease-in-out-") {
            #expect(abs(easing(0.5) - 0.5) < 1e-9, "\(easing)")
            #expect(abs(easing(0.2) + easing(0.8) - 1) < 1e-9, "\(easing)")
        }
    }
}

struct EasedAnimationTests {
    @Test func `Arrives at the end of the duration`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 300, 100))
        let curve = AnimationCurve.eased(.linear, duration: 0.2)
        var steps = 0
        while !a.step(curve, dt: 0.01, timeout: 5) { steps += 1 }
        #expect(a.frame == rect(1000, 0, 300, 100))
        #expect((18...20).contains(steps))
    }

    @Test func `Follows the easing on the way`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        _ = a.step(.eased(.easeOutQuad, duration: 1), dt: 0.5, timeout: 5)
        #expect(a.frame == rect(750, 0, 100, 100))
    }

    @Test func `Retargeting starts the easing over from where it is`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        let curve = AnimationCurve.eased(.linear, duration: 1)
        _ = a.step(curve, dt: 0.5, timeout: 5)
        #expect(a.frame == rect(500, 0, 100, 100))
        a.retarget(rect(0, 0, 100, 100))
        _ = a.step(curve, dt: 0.5, timeout: 5)
        #expect(a.frame == rect(250, 0, 100, 100))
        _ = a.step(curve, dt: 0.5, timeout: 5)
        #expect(a.frame == rect(0, 0, 100, 100))
    }

    @Test func `A zero duration jumps`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        let done = a.step(.eased(.easeOutCubic, duration: 0), dt: 1.0 / 60, timeout: 5)
        #expect(done)
        #expect(a.frame == rect(1000, 0, 100, 100))
    }
}

struct StripStretchTests {
    @Test func `A long scroll takes a little longer for each column past the first, up to a limit`() {
        #expect(AnimationCurve.stripStretch(base: 0.2, columns: 1) == 1)
        #expect(AnimationCurve.stripStretch(base: 0.2, columns: 0.4) == 1)
        #expect(abs(AnimationCurve.stripStretch(base: 0.2, columns: 3) - 1.3) < 1e-9)
        #expect(abs(AnimationCurve.stripStretch(base: 0.2, columns: 30) - 3) < 1e-9)
        // Already as long as the limit, or no time at all: as configured.
        #expect(AnimationCurve.stripStretch(base: 0.8, columns: 9) == 1)
        #expect(AnimationCurve.stripStretch(base: 0, columns: 9) == 1)
    }

    @Test func `A stretched curve takes longer`() {
        #expect(AnimationCurve.eased(.easeOutCubic, duration: 0.2).stretched(1.5) == .eased(.easeOutCubic, duration: 0.2 * 1.5))
        let spring = Spring(response: 0.2, damping: 0.9)
        #expect(AnimationCurve.spring(spring).stretched(2) == .spring(Spring(response: 0.4, damping: 0.9)))
        #expect(AnimationCurve.spring(spring).stretched(1) == .spring(spring))
    }
}
