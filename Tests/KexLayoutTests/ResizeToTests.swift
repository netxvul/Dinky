import CoreGraphics
import Testing
@testable import KexLayout

/// Four windows in 1000x600 as a 2x2 grid: h[v[1 3] v[2 4]].
private func grid() -> Workspace {
    var ws = workspace(2)
    ws.focus(1)
    ws.insert(3)
    ws.focus(2)
    ws.insert(4)
    return ws
}

struct ResizeToTests {
    @Test func `Right edge drag takes from the right neighbour only`() {
        var ws = workspace(3, bounds: rect(0, 0, 900, 300)) // h[1 2 3], 300 each
        #expect(ws.resize(1, to: CGSize(width: 450, height: 300), moving: [.right]) == true)
        #expect(ws.layout().frames[1] == rect(0, 0, 450, 300))
        #expect(ws.layout().frames[2] == rect(450, 0, 150, 300))
        #expect(ws.layout().frames[3] == rect(600, 0, 300, 300))
    }

    @Test func `Left edge drag takes from the left neighbour`() {
        var ws = workspace(3, bounds: rect(0, 0, 900, 300))
        ws.resize(2, to: CGSize(width: 400, height: 300), moving: [.left])
        #expect(ws.layout().frames[1] == rect(0, 0, 200, 300))
        #expect(ws.layout().frames[2] == rect(200, 0, 400, 300))
        #expect(ws.layout().frames[3] == rect(600, 0, 300, 300))
    }

    @Test func `Unknown edge splits between both neighbours`() {
        var ws = workspace(3, bounds: rect(0, 0, 900, 300))
        ws.resize(2, to: CGSize(width: 400, height: 300))
        #expect(ws.layout().frames[1] == rect(0, 0, 250, 300))
        #expect(ws.layout().frames[2] == rect(250, 0, 400, 300))
    }

    @Test func `Corner drag changes both axes`() {
        var ws = grid()
        ws.resize(1, to: CGSize(width: 600, height: 400), moving: [.right, .down])
        #expect(shape(ws.root) == "h[v[1 3] v[2 4]]")
        #expect(ws.layout().frames[1] == rect(0, 0, 600, 400))
        #expect(ws.layout().frames[3] == rect(0, 400, 600, 200))
        #expect(ws.layout().frames[2] == rect(600, 0, 400, 300))
    }

    @Test func `Drag beyond the minimum ratio clamps`() {
        var ws = workspace(2)
        ws.resize(1, to: CGSize(width: 990, height: 600), moving: [.right])
        assertRatios(ws.root.ratios, [0.9, 0.1])
        #expect(ws.resize(1, to: CGSize(width: 995, height: 600), moving: [.right]) == false)
    }

    @Test func `Drag stops at the neighbours minimum size`() {
        var ws = workspace(2)
        ws.minimumSizes[2] = CGSize(width: 300, height: 0)
        ws.resize(1, to: CGSize(width: 900, height: 600), moving: [.right])
        #expect(ws.layout().frames[1] == rect(0, 0, 700, 600))
    }

    @Test func `Nested column resizes through its parent`() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.resize(3, to: CGSize(width: 600, height: 300), moving: [.left])
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        assertRatios(ws.root.ratios, [0.4, 0.6])
        assertRatios(ws.root.container(at: [1]).ratios, [0.5, 0.5])
        #expect(ws.layout().frames[2] == rect(400, 0, 600, 300))
    }

    @Test func `Edge without a neighbour looks further up`() {
        var ws = grid()
        // 3 is the last of its column; its bottom edge has no neighbour, and nothing above runs vertically.
        #expect(ws.resize(3, to: CGSize(width: 500, height: 400), moving: [.down]) == false)
        #expect(ws.resize(3, to: CGSize(width: 500, height: 400), moving: [.up]) == true)
        #expect(ws.layout().frames[1] == rect(0, 0, 500, 200))
    }

    @Test func `Window alone along the axis does nothing`() {
        var ws = workspace(2)
        let before = ws
        #expect(ws.resize(1, to: CGSize(width: 500, height: 400), moving: [.down]) == false)
        #expect(ws.resize(1, to: CGSize(width: 500, height: 400), moving: [.up]) == false)
        #expect(ws == before)
        var one = workspace(1)
        #expect(one.resize(1, to: CGSize(width: 700, height: 400)) == false)
    }

    @Test func `Fixed layout drag includes empty cells in its extent`() {
        var horizontal = workspace(1, bounds: rect(0, 0, 1000, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .columns))
        #expect(horizontal.resize(1, to: CGSize(width: 600, height: 900), moving: [.right]) == true)
        #expect(horizontal.layout().frames[1]?.width == 600)

        var vertical = workspace(1, bounds: rect(0, 0, 1000, 900), algorithm: .fixed(rows: 3, columns: 1, expand: .rows))
        #expect(vertical.resize(1, to: CGSize(width: 1000, height: 400), moving: [.down]) == true)
        #expect(vertical.layout().frames[1]?.height == 400)
    }

    @Test func `Layout reproduces the requested size with gaps`() {
        var ws = grid()
        ws.gaps = Gaps(all: 10)
        ws.resize(4, to: CGSize(width: 537, height: 213), moving: [.left, .up])
        let frame = ws.layout().frames[4]!
        #expect(abs(frame.width - 537) <= 1)
        #expect(abs(frame.height - 213) <= 1)
        #expect(abs(frame.maxX - 990) <= 1)
        #expect(abs(frame.maxY - 590) <= 1)
    }

    @Test func `Accordion child resizes its accordion`() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.focus(2)
        ws.setMode(.accordion)
        #expect(shape(ws.root) == "h[1 av[2 3]]")
        #expect(ws.resize(2, to: CGSize(width: 600, height: 570), moving: [.left]) == true)
        assertRatios(ws.root.ratios, [0.4, 0.6])
        #expect(ws.layout().frames[3]?.width == 600)
        #expect(ws.resize(2, to: CGSize(width: 600, height: 300), moving: [.down]) == false)
    }

    @Test func `Fullscreen does nothing`() {
        var ws = workspace(2)
        ws.toggleFullscreen()
        #expect(ws.resize(2, to: CGSize(width: 300, height: 600), moving: [.left]) == false)
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }
}
