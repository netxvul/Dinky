import CoreGraphics
import Testing
@testable import DinkyLayout

private let area = rect(10, 30, 1000, 600)

struct FloatingTests {
    @Test(arguments: [(Direction.left, rect(350, 230, 300, 200)), (.right, rect(450, 230, 300, 200)),
                      (.up, rect(400, 180, 300, 200)), (.down, rect(400, 280, 300, 200))])
    func `Move shifts by the step`(direction: Direction, expected: CGRect) {
        #expect(FloatingFrame.moved(rect(400, 230, 300, 200), direction, by: 50, within: area) == expected)
    }

    @Test func `Centred keeping its size, a window is at most that share of the area each way`() {
        let area = rect(10, 40, 1000, 800)
        #expect(FloatingFrame.centered(CGSize(width: 400, height: 200), atMost: 0.8, in: area) == rect(310, 340, 400, 200))
        #expect(FloatingFrame.centered(CGSize(width: 1400, height: 200), atMost: 0.8, in: area) == rect(110, 340, 800, 200))
        #expect(FloatingFrame.centered(CGSize(width: 400, height: 790), atMost: 0.8, in: area) == rect(310, 120, 400, 640))
        #expect(FloatingFrame.centered(CGSize(width: 1000, height: 800), atMost: 0.8, in: area) == rect(110, 120, 800, 640))
    }

    @Test func `Move stops at the edge of the area`() {
        #expect(FloatingFrame.moved(rect(30, 40, 300, 200), .left, by: 50, within: area) == rect(10, 40, 300, 200))
        #expect(FloatingFrame.moved(rect(30, 40, 300, 200), .up, by: 50, within: area) == rect(30, 30, 300, 200))
        #expect(FloatingFrame.moved(rect(690, 400, 300, 200), .right, by: 50, within: area) == rect(710, 400, 300, 200))
        #expect(FloatingFrame.moved(rect(690, 400, 300, 200), .down, by: 50, within: area) == rect(690, 430, 300, 200))
        // Already at the edge: nothing moves.
        #expect(FloatingFrame.moved(rect(10, 40, 300, 200), .left, by: 50, within: area) == rect(10, 40, 300, 200))
    }

    @Test func `A window bigger than the area sits against its top left`() {
        #expect(FloatingFrame.moved(rect(0, 0, 1200, 700), .right, by: 50, within: area) == rect(10, 30, 1200, 700))
    }

    @Test func `Resize keeps the centre`() {
        let frame = rect(400, 230, 300, 200)
        #expect(FloatingFrame.resized(frame, by: 50, along: .horizontal, within: area) == rect(375, 230, 350, 200))
        #expect(FloatingFrame.resized(frame, by: -50, along: .vertical, within: area) == rect(400, 255, 300, 150))
        #expect(FloatingFrame.resized(frame, by: 50, along: nil, within: area) == rect(375, 205, 350, 250))
    }

    @Test func `Resize stays inside the area`() {
        // Growing against the left edge pushes the window right rather than over the edge.
        #expect(FloatingFrame.resized(rect(10, 230, 300, 200), by: 100, along: .horizontal, within: area) == rect(10, 230, 400, 200))
        // No wider or taller than the area.
        #expect(FloatingFrame.resized(rect(100, 100, 900, 500), by: 400, along: nil, within: area) == rect(10, 30, 1000, 600))
    }

    @Test func `Resize stops at the minimum size`() {
        #expect(FloatingFrame.resized(rect(400, 230, 150, 120), by: -100, along: nil, within: area) == rect(425, 240, 100, 100))
    }

    @Test func `Resize from the top-left corner grows right and down`() {
        let frame = rect(400, 230, 300, 200)
        #expect(FloatingFrame.resized(frame, by: 50, along: .horizontal, within: area, anchor: .topLeft) == rect(400, 230, 350, 200))
        #expect(FloatingFrame.resized(frame, by: -50, along: .vertical, within: area, anchor: .topLeft) == rect(400, 230, 300, 150))
        #expect(FloatingFrame.resized(frame, by: 50, along: nil, within: area, anchor: .topLeft) == rect(400, 230, 350, 250))
    }

    @Test func `Resize from the top-left corner against the right edge grows left`() {
        // Right edge at 1010: growing by 100 would cross it, so the window slides left to stay inside.
        #expect(FloatingFrame.resized(rect(710, 230, 300, 200), by: 100, along: .horizontal, within: area, anchor: .topLeft)
            == rect(610, 230, 400, 200))
    }

    @Test func `Filling takes the whole area`() {
        #expect(FloatingFrame.filling(area) == area)
        #expect(FloatingFrame.filling(rect(10.4, 30.6, 999.2, 600)) == rect(10, 31, 1000, 600))
    }
}
