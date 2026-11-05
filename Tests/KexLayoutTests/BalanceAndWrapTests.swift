import CoreGraphics
import Testing
@testable import KexLayout

struct BalanceSizesTests {
    @Test func `Every container gets equal ratios`() {
        var ws = workspace(3)  // h[1 v[2 3]]
        ws.focus(3)
        ws.resize(by: 100)
        ws.focus(1)
        ws.resize(by: 200)
        ws.balanceSizes()
        assertRatios(ws.root.ratios, [0.5, 0.5])
        guard case .container(let inner) = ws.root.children[1] else { Issue.record("expected a container"); return }
        assertRatios(inner.ratios, [0.5, 0.5])
    }

    @Test func `Keeps shape and focus`() {
        var ws = workspace(4)
        ws.focus(2)
        ws.resize(by: 150)
        let before = shape(ws.root)
        ws.balanceSizes()
        #expect(shape(ws.root) == before)
        #expect(ws.focused == 2)
    }

    @Test func `Three siblings get a third each`() {
        var ws = workspace(0)
        for id: WindowID in 1...3 { ws.root.insert(.window(id), at: Int(id) - 1) }
        ws.focus(2)
        ws.resize(by: 300)
        ws.balanceSizes()
        assertRatios(ws.root.ratios, [1.0 / 3, 1.0 / 3, 1.0 / 3])
    }
}

struct InnerGapAxesTests {
    @Test func `Horizontal and vertical inner gaps apply to their axis`() {
        let gaps = Gaps(horizontal: 20, vertical: 10, top: 0, bottom: 0, left: 0, right: 0)
        let frames = workspace(3, bounds: rect(0, 0, 1020, 610), gaps: gaps).layout().frames  // h[1 v[2 3]]
        #expect(frames[1] == rect(0, 0, 500, 610))
        #expect(frames[2] == rect(520, 0, 500, 300))
        #expect(frames[3] == rect(520, 310, 500, 300))
    }
}

struct WrapAroundTests {
    @Test func `Edge window follows the tree`() {
        var ws = workspace(3)  // h[1 v[2 3]]
        #expect(ws.edgeWindow(.left) == 1)
        ws.focus(2)
        #expect(ws.edgeWindow(.right) == 2, "most recent child across the axis")
        #expect(ws.edgeWindow(.down) == 3, "root runs across: its most recent child, then the bottom")
        ws.focus(1)
        #expect(ws.edgeWindow(.down) == 1)
        #expect(workspace(0).edgeWindow(.left) == nil)
    }

    @Test func `Focus wraps within the workspace`() {
        var ws = workspace(3)
        ws.focus(3)
        #expect(ws.focus(.right) == false)
        #expect(ws.focus(.right, wrapping: true) == true)
        #expect(ws.focused == 1)
        ws.focus(3)
        #expect(ws.focus(.down, wrapping: true) == true)
        #expect(ws.focused == 2)
    }

    @Test func `Wrapping with one window does nothing`() {
        var ws = workspace(1)
        #expect(ws.focus(.left, wrapping: true) == false)
        #expect(ws.focused == 1)
    }
}

struct SwapByIDTests {
    @Test func `Swap two windows keeps tiles and focus`() {
        var ws = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600))
        ws.insert(1); ws.insert(2); ws.insert(3)
        ws.focus(2)
        let before = ws.layout().frames
        #expect(ws.swap(1, 3) == true)
        let after = ws.layout().frames
        #expect(after[1] == before[3])
        #expect(after[3] == before[1])
        #expect(after[2] == before[2])
        #expect(ws.focused == 2)
        #expect(ws.swap(1, 1) == false)
        #expect(ws.swap(1, 99) == false)
    }
}
