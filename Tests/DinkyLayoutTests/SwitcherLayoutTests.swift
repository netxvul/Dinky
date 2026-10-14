import CoreGraphics
import Testing
@testable import DinkyLayout

struct SwitcherLayoutTests {
    // A wide window, a column of two narrow ones, and another wide one.
    private let layout = SwitcherLayout(columns: [[1.5], [0.5, 0.5], [1.6]], maxWidth: 2000)
    private let visible = CGRect(x: 0, y: 25, width: 1512, height: 900)

    @Test func `Thumbnails sit in strip order, a column's closer together`() {
        #expect(layout.frames == [
            CGRect(x: 14, y: 14, width: 150, height: 100),
            CGRect(x: 176, y: 14, width: 64, height: 100),
            CGRect(x: 244, y: 14, width: 64, height: 100),
            CGRect(x: 320, y: 14, width: 160, height: 100),
        ])
        // The same padding on every side.
        #expect(layout.size == CGSize(width: 494, height: 128))
    }

    @Test func `Padding follows the corner radius`() {
        let round = SwitcherLayout(columns: [[1.5], [1.5]], cornerRadius: 64, maxWidth: 2000)
        #expect(round.frames[0].origin == CGPoint(x: 19, y: 19))
        #expect(round.size == CGSize(width: 350, height: 138))
    }

    @Test func `A row too wide is scaled down to fit`() {
        let narrow = SwitcherLayout(columns: [[2], [2], [2]], maxWidth: 300)
        #expect(narrow.frames.map(\.minX) == [14, 108, 202])
        #expect(narrow.frames.allSatisfy { $0.width == 82 && $0.height == 41 })
        #expect(narrow.size.width == 298)
    }

    @Test func `The thumbnail under x reaches halfway into the gaps, and past the ends`() {
        #expect(layout.index(atX: -50) == 0)
        #expect(layout.index(atX: 169) == 0)
        #expect(layout.index(atX: 171) == 1)
        #expect(layout.index(atX: 243) == 2)
        #expect(layout.index(atX: 400) == 3)
        #expect(layout.index(atX: 5000) == 3)
        #expect(SwitcherLayout(columns: [], maxWidth: 500).index(atX: 10) == nil)
    }

    @Test func `The anchor's thumbnail sits under the pointer`() {
        // Thumbnail 1's centre is (208, 64).
        #expect(layout.origin(anchor: 1, pointer: CGPoint(x: 500, y: 500), visible: visible) == CGPoint(x: 292, y: 436))
    }

    @Test func `Kept inside the screen's top and bottom`() {
        #expect(layout.origin(anchor: 1, pointer: CGPoint(x: 500, y: 40), visible: visible).y == 33)
        #expect(layout.origin(anchor: 1, pointer: CGPoint(x: 500, y: 920), visible: visible).y == 789)
    }

    @Test func `Kept inside the screen's sides`() {
        #expect(layout.origin(anchor: 3, pointer: CGPoint(x: 50, y: 500), visible: visible).x == 8)
        #expect(layout.origin(anchor: 0, pointer: CGPoint(x: 1500, y: 500), visible: visible).x == 1010)
    }
}
