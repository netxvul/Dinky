import CoreGraphics
import Testing
@testable import DinkyLayout

struct SwitcherMapTests {
    // A 1600x1000 workspace: a left half, and a right half split into a top and two bottom quarters.
    private let bounds = CGRect(x: 0, y: 25, width: 1600, height: 1000)
    private var tiles: [CGRect] {
        [CGRect(x: 0, y: 25, width: 800, height: 1000), CGRect(x: 800, y: 25, width: 800, height: 500),
         CGRect(x: 800, y: 525, width: 400, height: 500), CGRect(x: 1200, y: 525, width: 400, height: 500)]
    }
    private let visible = CGRect(x: 0, y: 25, width: 1600, height: 1000)

    @Test func `Tiles keep their places, scaled to the map with a gap between`() {
        let map = SwitcherMap(tiles: tiles, bounds: bounds, cornerRadius: 0, maxWidth: 1000)
        // (220 - 28) / 1000 = 0.192 points per point.
        #expect(map.size == CGSize(width: 335, height: 220))
        #expect(map.frames == [
            CGRect(x: 16, y: 16, width: 150, height: 188),
            CGRect(x: 170, y: 16, width: 149, height: 92),
            CGRect(x: 170, y: 112, width: 72, height: 92),
            CGRect(x: 246, y: 112, width: 73, height: 92),
        ])
    }

    @Test func `Padding grows with the corner radius`() {
        #expect(SwitcherMap.padding(cornerRadius: 20) == 14)
        #expect(SwitcherMap.padding(cornerRadius: 64) == 19)
        let round = SwitcherMap(tiles: tiles, bounds: bounds, cornerRadius: 64, maxWidth: 1000)
        #expect(round.frames[0].minX == 21)
        #expect(round.size.height == 220)
    }

    @Test func `A map too wide is scaled down`() {
        let map = SwitcherMap(tiles: tiles, bounds: bounds, cornerRadius: 0, maxWidth: 188)
        #expect(map.size == CGSize(width: 188, height: 128))
    }

    @Test func `The cell under the point, else the nearest`() {
        let map = SwitcherMap(tiles: tiles, bounds: bounds, cornerRadius: 0, maxWidth: 1000)
        #expect(map.index(at: CGPoint(x: 50, y: 50)) == 0)
        #expect(map.index(at: CGPoint(x: 200, y: 50)) == 1)
        #expect(map.index(at: CGPoint(x: 280, y: 150)) == 3)
        // In the gap between the bottom quarters, as near the one as the other: the first wins.
        #expect(map.index(at: CGPoint(x: 244, y: 150)) == 2)
        #expect(map.index(at: CGPoint(x: 500, y: 300)) == 3)
        #expect(map.index(at: CGPoint(x: -40, y: 90)) == 0)
    }

    @Test func `The anchor's cell sits under the pointer, inside the screen`() {
        let map = SwitcherMap(tiles: tiles, bounds: bounds, cornerRadius: 0, maxWidth: 1000)
        // Cell 1's centre is (244.5, 62).
        #expect(map.origin(anchor: 1, pointer: CGPoint(x: 800, y: 500), visible: visible) == CGPoint(x: 556, y: 438))
        #expect(map.origin(anchor: 0, pointer: CGPoint(x: 10, y: 40), visible: visible) == CGPoint(x: 8, y: 33))
        #expect(map.origin(anchor: 3, pointer: CGPoint(x: 1595, y: 1020), visible: visible) == CGPoint(x: 1257, y: 797))
    }
}

struct SwitcherKeysTests {
    @Test func `Keys step along a row, round from end to end`() {
        #expect(SwitcherLayout.step(0, count: 3, toward: .right) == 1)
        #expect(SwitcherLayout.step(2, count: 3, toward: .down) == 0)
        #expect(SwitcherLayout.step(0, count: 3, toward: .left) == 2)
        #expect(SwitcherLayout.step(1, count: 3, toward: .up) == 0)
        #expect(SwitcherLayout.step(0, count: 0, toward: .right) == 0)
    }

    @Test func `Keys pick the nearest cell that way on a map`() {
        // One tile on the left, two stacked on the right.
        let map = SwitcherMap(tiles: [CGRect(x: 0, y: 0, width: 500, height: 600), CGRect(x: 500, y: 0, width: 500, height: 300),
                                      CGRect(x: 500, y: 300, width: 500, height: 300)],
                              bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), cornerRadius: 0, maxWidth: 2000)
        #expect(map.neighbor(of: 0, toward: .right) == 1)
        #expect(map.neighbor(of: 1, toward: .down) == 2)
        #expect(map.neighbor(of: 2, toward: .up) == 1)
        #expect(map.neighbor(of: 2, toward: .left) == 0)
        #expect(map.neighbor(of: 0, toward: .left) == nil)
        #expect(map.neighbor(of: 0, toward: .up) == nil)
    }

    @Test func `A capsule centres in the visible area`() {
        #expect(SwitcherLayout.centred(CGSize(width: 400, height: 128), in: CGRect(x: 0, y: 25, width: 1512, height: 900))
                == CGPoint(x: 556, y: 411))
    }
}
