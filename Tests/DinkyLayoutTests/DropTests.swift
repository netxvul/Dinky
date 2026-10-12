import CoreGraphics
import Testing
@testable import DinkyLayout

struct DropZoneTests {
    private let tile = rect(0, 0, 100, 100)

    @Test func `Middle swaps`() {
        #expect(DropZone(at: CGPoint(x: 50, y: 50), in: tile) == .swap)
        #expect(DropZone(at: CGPoint(x: 30, y: 70), in: tile) == .swap)
    }

    @Test func `Edges split toward their side`() {
        #expect(DropZone(at: CGPoint(x: 5, y: 50), in: tile) == .split(.left))
        #expect(DropZone(at: CGPoint(x: 95, y: 50), in: tile) == .split(.right))
        #expect(DropZone(at: CGPoint(x: 50, y: 5), in: tile) == .split(.up))
        #expect(DropZone(at: CGPoint(x: 50, y: 95), in: tile) == .split(.down))
    }

    @Test func `Corners divide along the diagonals`() {
        #expect(DropZone(at: CGPoint(x: 10, y: 20), in: tile) == .split(.left))
        #expect(DropZone(at: CGPoint(x: 20, y: 10), in: tile) == .split(.up))
        #expect(DropZone(at: CGPoint(x: 90, y: 85), in: tile) == .split(.right))
    }

    @Test func `A thin tile divides along its own diagonals`() {
        let wide = rect(0, 0, 400, 100)
        #expect(DropZone(at: CGPoint(x: 20, y: 90), in: wide) == .split(.left))
        #expect(DropZone(at: CGPoint(x: 150, y: 95), in: wide) == .split(.down))
    }

    @Test func `Preview is the half on the zone's side, a gap apart`() {
        let r = rect(0, 0, 100, 50)
        #expect(DropZone.swap.preview(of: r, gap: 10) == r)
        #expect(DropZone.split(.left).preview(of: r, gap: 10) == rect(0, 0, 45, 50))
        #expect(DropZone.split(.right).preview(of: r, gap: 10) == rect(55, 0, 45, 50))
        #expect(DropZone.split(.up).preview(of: r, gap: 0) == rect(0, 0, 100, 25))
        #expect(DropZone.split(.down).preview(of: r, gap: 0) == rect(0, 25, 100, 25))
    }
}

/// Three windows in 1000x600: 1 on the left, 2 above 3 on the right.
private func three() -> Workspace { workspace(3) }

struct DropTests {
    @Test func `Three starts as one beside a column`() {
        #expect(shape(three().root) == "h[1 v[2 3]]")
    }

    @Test func `Swap zone swaps`() {
        var ws = three()
        let dropped = ws.drop(1, onto: 3, .swap)
        #expect(dropped)
        #expect(shape(ws.root) == "h[3 v[2 1]]")
    }

    @Test func `Dropping below a tile splits it`() {
        var ws = three()
        let dropped = ws.drop(1, onto: 3, .split(.down))
        #expect(dropped)
        #expect(shape(ws.root) == "v[2 3 1]")
        assertRatios(ws.root.ratios, [0.5, 0.25, 0.25])
        #expect(ws.focused == 1)
    }

    @Test func `Dropping left of a tile splits it`() {
        var ws = three()
        let dropped = ws.drop(3, onto: 1, .split(.left))
        #expect(dropped)
        #expect(shape(ws.root) == "h[3 1 2]")
        assertRatios(ws.root.ratios, [0.25, 0.25, 0.5])
    }

    @Test func `Dropping across the axis nests a container`() {
        var ws = three()
        let dropped = ws.drop(2, onto: 1, .split(.up))
        #expect(dropped)
        #expect(shape(ws.root) == "h[v[2 1] 3]")
    }

    @Test func `Dropping onto a sibling turns the pair`() {
        var ws = workspace(2)
        let dropped = ws.drop(1, onto: 2, .split(.down))
        #expect(dropped)
        #expect(shape(ws.root) == "v[2 1]")
        var other = workspace(2)
        let dropped2 = other.drop(1, onto: 2, .split(.right))
        #expect(dropped2)
        #expect(shape(other.root) == "h[2 1]")
    }

    @Test func `Nothing to do onto itself or a stranger`() {
        var ws = three()
        let dropped = ws.drop(1, onto: 1, .split(.left))
        #expect(!dropped)
        let dropped2 = ws.drop(1, onto: 9, .split(.left))
        #expect(!dropped2)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
    }

    @Test func `Inside an accordion a split nests tiles`() {
        var ws = workspace(3, algorithm: .dwindle(.accordion))
        #expect(shape(ws.root) == "ah[1 2 3]")
        let dropped = ws.drop(1, onto: 3, .split(.right))
        #expect(dropped)
        #expect(shape(ws.root) == "ah[2 h[3 1]]")
    }

    @Test func `A drop ends fullscreen`() {
        var ws = three()
        ws.focus(1)
        ws.toggleFullscreen()
        let dropped = ws.drop(1, onto: 3, .split(.down))
        #expect(dropped)
        #expect(ws.fullscreenWindows.isEmpty)
    }

    @Test func `Zone and preview from the layout`() {
        let ws = three()
        let layout = ws.layout()
        #expect(layout.frames[3] == rect(500, 300, 500, 300))
        #expect(ws.dropZone(at: CGPoint(x: 750, y: 590), onto: 3, in: layout) == .split(.down))
        #expect(ws.dropZone(at: CGPoint(x: 750, y: 450), onto: 3, in: layout) == .swap)
        #expect(ws.dropZone(at: CGPoint(x: 750, y: 450), onto: 9, in: layout) == nil)
        #expect(ws.dropPreview(onto: 3, .split(.down), in: layout) == rect(500, 450, 500, 150))
        #expect(ws.dropPreview(onto: 3, .swap, in: layout) == rect(500, 300, 500, 300))
    }

    @Test func `The fixed template only swaps`() {
        var ws = workspace(4, algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        let layout = ws.layout()
        let frame = layout.frames[2]!
        #expect(ws.dropZone(at: CGPoint(x: frame.minX + 1, y: frame.midY), onto: 2, in: layout) == .swap)
        let dropped = ws.drop(1, onto: 2, .split(.left))
        #expect(dropped)
        #expect(ws.isFixedTree)
        #expect(ws.layout().frames[1] == frame)
    }

    @Test func `Scrolling left and right make a column`() {
        var ws = workspace(3, algorithm: .scrolling)
        #expect(shape(ws.root) == "h[1 2 3]")
        let dropped = ws.drop(1, onto: 3, .split(.right))
        #expect(dropped)
        #expect(shape(ws.root) == "h[2 3 1]")
        let dropped2 = ws.drop(1, onto: 2, .split(.left))
        #expect(dropped2)
        #expect(shape(ws.root) == "h[1 2 3]")
    }

    @Test func `Scrolling up and down join the column at its width`() {
        var ws = workspace(3, algorithm: .scrolling)
        ws.columnWidths[3] = 0.8
        let dropped = ws.drop(1, onto: 3, .split(.down))
        #expect(dropped)
        #expect(shape(ws.root) == "h[2 v[3 1]]")
        #expect(ws.columnWidths[1] == 0.8)
    }
}
