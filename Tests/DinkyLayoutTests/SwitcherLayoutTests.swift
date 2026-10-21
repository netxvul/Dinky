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

    @Test func `At the top or bottom, across the middle and clear of the menu bar or Dock`() {
        let size = CGSize(width: 494, height: 128)
        #expect(SwitcherLayout.edge(size, in: visible, top: true) == CGPoint(x: 509, y: 41))
        #expect(SwitcherLayout.edge(size, in: visible, top: false) == CGPoint(x: 509, y: 781))
        // Never above the top of a display too short for it.
        let short = CGRect(x: 0, y: 25, width: 1512, height: 100)
        #expect(SwitcherLayout.edge(size, in: short, top: false).y == 25)
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

    @Test func `The thumbnail under the pointer reaches halfway into the gaps, and past the ends`() {
        #expect(layout.index(at: CGPoint(x: -50, y: 64)) == 0)
        #expect(layout.index(at: CGPoint(x: 169, y: 64)) == 0)
        #expect(layout.index(at: CGPoint(x: 171, y: 64)) == 1)
        #expect(layout.index(at: CGPoint(x: 243, y: 64)) == 2)
        #expect(layout.index(at: CGPoint(x: 400, y: 500)) == 3)
        #expect(layout.index(at: CGPoint(x: 5000, y: 64)) == 3)
        #expect(SwitcherLayout(columns: [], maxWidth: 500).index(at: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func `A column stacked on screen shows one over the other, picked by height too`() {
        let top = CGRect(x: 0, y: 0, width: 1000, height: 446), bottom = CGRect(x: 0, y: 454, width: 1000, height: 446)
        let stacked = SwitcherLayout(groups: [.sideBySide([1.5]), .tiles([top, bottom]), .sideBySide([1.6])], maxWidth: 2000)
        // The column takes the room its 1000 by 900 box would, its two thumbnails a stack gap apart.
        #expect(stacked.frames == [
            CGRect(x: 14, y: 14, width: 150, height: 100),
            CGRect(x: 176, y: 14, width: 111, height: 48),
            CGRect(x: 176, y: 66, width: 111, height: 48),
            CGRect(x: 299, y: 14, width: 160, height: 100),
        ])
        #expect(stacked.size == CGSize(width: 473, height: 128))
        #expect(stacked.index(at: CGPoint(x: 230, y: 30)) == 1)
        #expect(stacked.index(at: CGPoint(x: 230, y: 100)) == 2)
        #expect(stacked.index(at: CGPoint(x: 230, y: -40)) == 1)
        #expect(stacked.index(at: CGPoint(x: 230, y: 200)) == 2)
    }

    @Test func `Tiles apart show as they sit, overlapping ones side by side`() {
        let top = CGRect(x: 0, y: 0, width: 1000, height: 446), bottom = CGRect(x: 0, y: 454, width: 1000, height: 446)
        #expect(SwitcherLayout.Group(aspects: [2.2, 2.2], tiles: [top, bottom]) == .tiles([top, bottom]))
        // An accordion's windows overlap.
        let behind = CGRect(x: 30, y: 0, width: 1000, height: 900)
        #expect(SwitcherLayout.Group(aspects: [1, 1], tiles: [top, behind]) == .sideBySide([1, 1]))
        // A lone window keeps its own shape, and windows without tiles, as on a free workspace, sit side by side.
        #expect(SwitcherLayout.Group(aspects: [1.5], tiles: [top]) == .sideBySide([1.5]))
        #expect(SwitcherLayout.Group(aspects: [1, 1], tiles: []) == .sideBySide([1, 1]))
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

    @Test func `Letters go left to right, a column's top to bottom`() {
        let frames = [CGRect(x: 100, y: 0, width: 50, height: 50), CGRect(x: 0, y: 60, width: 50, height: 40),
                      CGRect(x: 0.5, y: 0, width: 50, height: 50), CGRect(x: 200, y: 0, width: 50, height: 100)]
        #expect(SwitcherLayout.readingOrder(frames) == [2, 1, 0, 3])
        #expect(SwitcherLayout.readingOrder([]) == [])
    }
}
