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

    @Test func `A strip's column swaps down its middle, goes before or after either side, and stacks at the top and bottom`() {
        let column = rect(0, 0, 100, 500)
        #expect(DropZone(scrollingAt: CGPoint(x: 50, y: 250), in: column) == .swap)
        #expect(DropZone(scrollingAt: CGPoint(x: 70, y: 250), in: column) == .split(.right))
        #expect(DropZone(scrollingAt: CGPoint(x: 95, y: 110), in: column) == .split(.right))
        #expect(DropZone(scrollingAt: CGPoint(x: 30, y: 250), in: column) == .split(.left))
        #expect(DropZone(scrollingAt: CGPoint(x: 90, y: 50), in: column) == .split(.up))
        #expect(DropZone(scrollingAt: CGPoint(x: 10, y: 480), in: column) == .split(.down))
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

    @Test func `A swap ends fullscreen and focuses the dropped window`() {
        var ws = three()
        ws.focus(1)
        ws.toggleFullscreen()
        let dropped = ws.drop(1, onto: 3, .swap)
        #expect(dropped)
        #expect(shape(ws.root) == "h[3 v[2 1]]")
        #expect(ws.fullscreenWindows.isEmpty)
        #expect(ws.focused == 1)
    }

    @Test func `Zone from the layout`() {
        let ws = three()
        let layout = ws.layout()
        #expect(layout.frames[3] == rect(500, 300, 500, 300))
        #expect(ws.dropZone(at: CGPoint(x: 750, y: 590), onto: 3, in: layout) == .split(.down))
        #expect(ws.dropZone(at: CGPoint(x: 750, y: 450), onto: 3, in: layout) == .swap)
        #expect(ws.dropZone(at: CGPoint(x: 750, y: 450), onto: 9, in: layout) == nil)
    }

    @Test func `A split lands where the tree puts it once the window has left its place`() {
        // The tile under the pointer is not what is split: taking 1 out first gives 3 the whole width.
        var ws = three()
        let dropped = ws.drop(1, onto: 3, .split(.down))
        #expect(dropped)
        #expect(ws.layout().frames[1] == rect(0, 450, 1000, 150))
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

struct StripDropTests {
    /// Four 500-wide columns in 1000 with the gutters either side, 2 and 3 in view, 1 and 4 parked as slivers.
    private func four() -> Workspace {
        var ws = Workspace(bounds: rect(-Workspace.peek, 0, 1000 + 2 * Workspace.peek, 600), algorithm: .scrolling)
        ws.columnWidth = 0.5
        for id in 1...4 { ws.insert(WindowID(id)) }
        ws.focus(2)
        return ws
    }

    @Test func `A column in view is measured on the part that shows`() {
        let ws = four(), layout = ws.layout()
        #expect(ws.dropZone(at: CGPoint(x: 900, y: 300), onto: 3, in: layout) == .split(.right))
        #expect(ws.dropZone(at: CGPoint(x: 600, y: 300), onto: 3, in: layout) == .split(.left))
        #expect(ws.dropZone(at: CGPoint(x: 600, y: 20), onto: 3, in: layout) == .split(.up))
    }

    @Test func `A parked sliver or the gutter goes beside the nearest column in view`() {
        let ws = four(), layout = ws.layout()
        #expect(ws.edgeDrop(at: CGPoint(x: 1010, y: 300), in: layout, excluding: 9)! == (3, .split(.right)))
        #expect(ws.edgeDrop(at: CGPoint(x: -10, y: 300), in: layout, excluding: 9)! == (2, .split(.left)))
        #expect(ws.edgeDrop(at: CGPoint(x: 700, y: 300), in: layout, excluding: 9) == nil, "over a column in view")
    }

    @Test func `Dropped past the right sliver, a window comes in between the last column in view and the parked one`() {
        var ws = four()
        let edge = ws.edgeDrop(at: CGPoint(x: 1010, y: 300), in: ws.layout(), excluding: 9)!
        var other = workspace(1, algorithm: .scrolling)
        other.insert(9)
        let received = ws.receive(9, from: &other, onto: edge.target, edge.zone)
        #expect(received)
        #expect(ws.windows == [1, 2, 3, 9, 4])
        #expect(other.windows == [1])
    }

    @Test func `A window from another tree goes straight to its place, the strip scrolling only as that needs`() {
        var ws = four()
        ws.focus(3)
        var other = workspace(1)
        other.insert(9)
        let received = ws.receive(9, from: &other, onto: 2, .split(.right))
        #expect(received)
        #expect(ws.windows == [1, 2, 9, 3, 4])
        #expect(ws.focused == 9)
        // Put in beside the focused 3 first, it would have scrolled 2 out of view.
        let layout = ws.layout()
        #expect(layout.frames[2] == rect(0, 0, 500, 600))
        #expect(layout.frames[9] == rect(500, 0, 500, 600))
    }

    @Test func `A column from another strip keeps its width`() {
        var ws = four()
        var other = workspace(1, algorithm: .scrolling)
        other.insert(9)
        other.columnWidths[9] = 0.7
        let received = ws.receive(9, from: &other, onto: 3, .split(.left))
        #expect(received)
        #expect(ws.windows == [1, 2, 9, 3, 4])
        #expect(ws.columnWidths[9] == 0.7)
    }

    @Test func `Swapped with a window of another tree, each takes the other's place and size`() {
        var ws = four()
        ws.columnWidths[3] = 0.8
        var other = workspace(2, algorithm: .scrolling)
        other.insert(9)
        other.columnWidths[9] = 0.3
        let received = ws.receive(9, from: &other, onto: 3, .swap)
        #expect(received)
        #expect(ws.windows == [1, 2, 9, 4])
        #expect(ws.columnWidths[9] == 0.8)
        #expect(ws.focused == 9)
        #expect(other.windows == [1, 2, 3])
        #expect(other.columnWidths[3] == 0.3)
    }

    @Test func `Nothing comes in that is not in the tree it comes from, is here already, or onto a stranger`() {
        var ws = four()
        var other = workspace(1)
        let missing = ws.receive(9, from: &other, onto: 2, .swap)
        #expect(!missing)
        other.insert(9)
        let stranger = ws.receive(9, from: &other, onto: 7, .split(.left))
        #expect(!stranger)
        #expect(other.windows == [1, 9])
        #expect(ws.windows == [1, 2, 3, 4])
    }

    @Test func `Without a target, it comes in as a new window does`() {
        var ws = Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling)
        var other = workspace(1)
        other.insert(9)
        let received = ws.receive(9, from: &other, onto: nil, .swap)
        #expect(received)
        #expect(ws.windows == [9])
        #expect(other.windows == [1])
    }

    /// Five 500-wide columns as `four` has them, 3 and 4 in view.
    private func five() -> Workspace {
        var ws = Workspace(bounds: rect(-Workspace.peek, 0, 1000 + 2 * Workspace.peek, 600), algorithm: .scrolling)
        ws.columnWidth = 0.5
        for id in 1...5 { ws.insert(WindowID(id)) }
        ws.focus(3)
        return ws
    }

    @Test func `A column a drop takes one out left of is kept where it showed, under the pointer`() {
        var ws = five()
        #expect(ws.columnStart(of: 3) == 0)
        #expect(ws.columnStart(of: 4) == 500)
        let dropped = ws.drop(3, onto: 4, .split(.up))
        #expect(dropped)
        #expect(ws.columnStart(of: 4)! < 500, "taking 3's column out moves 4 left, and 5 in under the pointer")
        ws.scroll(columnOf: 4, to: 500)
        #expect(ws.columnStart(of: 4) == 500)
        let layout = ws.layout()
        #expect(layout.frames[3] == rect(500, 0, 500, 300))
        #expect(layout.frames[4] == rect(500, 300, 500, 300))
        #expect(layout.frames[2] == rect(0, 0, 500, 600))
    }

    @Test func `A column is kept where it showed only as far as the strip scrolls, the focused column whole`() {
        var ws = four()
        let dropped = ws.drop(2, onto: 3, .split(.up))
        #expect(dropped)
        ws.scroll(columnOf: 3, to: 500)
        #expect(ws.columnStart(of: 3) == 475, "the strip goes no further than its start, the first column in the gutter")
        var other = five()
        let dropped2 = other.drop(3, onto: 4, .split(.up))
        #expect(dropped2)
        other.scroll(columnOf: 4, to: 900)
        #expect(other.columnStart(of: 4) == 500, "the focused column shows whole")
        #expect(Workspace(bounds: rect(0, 0, 1000, 600)).columnStart(of: 1) == nil, "no strip")
    }

    @Test func `A drop shown keeps the column where it showed past the strip's start, till the strip is let go`() {
        var ws = four()
        ws.focus(1)
        let x = ws.columnStart(of: 2)!
        #expect(x == 475)
        let dropped = ws.drop(1, onto: 2, .split(.up))
        #expect(dropped)
        ws.scroll(columnOf: 2, to: x, pastEnds: true)
        #expect(ws.keepsScroll)
        #expect(ws.columnStart(of: 2) == 475, "the column stays under the pointer, a whole column past the strip's start")
        ws.keepsScroll = false
        #expect(ws.columnStart(of: 2) == -25, "let go, the strip goes back within its start, the column in the gutter")
        var near = four()
        let start = near.columnStart(of: 3)!
        #expect(start == 500)
        let dropped2 = near.drop(2, onto: 3, .split(.up))
        #expect(dropped2)
        near.scroll(columnOf: 3, to: start, pastEnds: true)
        #expect(!near.keepsScroll, "only the gutter past the start, where the drop lands")
        #expect(near.columnStart(of: 3) == 475)
    }

    @Test func `Past the strip's ends only for more than an end column reaching into its gutter`() {
        var ws = four()
        let x = ws.columnStart(of: 3)!
        #expect(x == 500)
        let dropped = ws.drop(4, onto: 3, .split(.up))
        #expect(dropped)
        ws.scroll(columnOf: 3, to: x, pastEnds: true)
        #expect(!ws.keepsScroll, "3 at 500 is only short of reaching into the right gutter, where the drop lands")
        #expect(ws.layout().frames[3]?.minX == 525)
        var far = four()
        far.focus(4)
        let start = far.columnStart(of: 3)!
        #expect(start == 25)
        let dropped2 = far.drop(4, onto: 3, .split(.up))
        #expect(dropped2)
        far.scroll(columnOf: 3, to: start, pastEnds: true)
        #expect(far.keepsScroll, "kept where it showed, a whole column past the end")
        #expect(far.layout().frames[3]?.minX == 25)
    }
}

struct DropHitTests {
    /// 1 and 2 side by side in 1000x600 with 10-point gaps: 1 at x 10...495, 2 at 505...990, y 10...590.
    private func pair() -> Workspace { workspace(2, gaps: Gaps(all: 10)) }

    @Test func `Over a tile, its zone`() {
        let ws = pair(), layout = ws.layout()
        #expect(layout.frames[2] == rect(505, 10, 485, 580))
        #expect(ws.dropHit(at: CGPoint(x: 750, y: 300), in: layout, excluding: 1) == .tile(2, .swap))
        #expect(ws.dropHit(at: CGPoint(x: 980, y: 300), in: layout, excluding: 1) == .tile(2, .split(.right)))
    }

    @Test func `Over its own place, the dragged window is home`() {
        let ws = pair(), layout = ws.layout()
        #expect(ws.dropHit(at: CGPoint(x: 200, y: 300), in: layout, excluding: 1) == .own)
    }

    @Test func `In a gap, the nearest tile counts, its own place too`() {
        let ws = pair(), layout = ws.layout()
        #expect(ws.dropHit(at: CGPoint(x: 502, y: 300), in: layout, excluding: 1) == .tile(2, .split(.left)))
        #expect(ws.dropHit(at: CGPoint(x: 497, y: 300), in: layout, excluding: 1) == .own)
    }

    @Test func `Over the menu bar or an outer gap, the tile along that edge`() {
        let ws = pair(), layout = ws.layout()
        #expect(ws.dropHit(at: CGPoint(x: 900, y: -20), in: layout, excluding: 1) == .tile(2, .split(.up)))
        #expect(ws.dropHit(at: CGPoint(x: 995, y: 300), in: layout, excluding: 1) == .tile(2, .split(.right)))
    }

    @Test func `With nothing else in the tree, nothing to drop onto`() {
        let empty = Workspace(bounds: rect(0, 0, 1000, 600))
        #expect(empty.dropHit(at: CGPoint(x: 500, y: 300), in: empty.layout(), excluding: 1) == .none)
        let alone = workspace(1)
        #expect(alone.dropHit(at: CGPoint(x: 500, y: 300), in: alone.layout(), excluding: 1) == .own)
    }
}
