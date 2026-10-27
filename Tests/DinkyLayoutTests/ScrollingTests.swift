import CoreGraphics
import Testing
@testable import DinkyLayout

/// The gutter parked windows show in, either side of the columns.
private let peek = Workspace.peek

/// How far inside the column in view a window hiding behind it at a wall keeps.
private let reach = Workspace.shadowReach

/// A scrolling workspace with windows 1...n inserted in order, so n is focused and in view. Its columns go
/// between 0 and 1000, inside the gutters, when it has no gaps or walls.
private func strip(_ n: Int, width: Double = 0.5, gaps: Gaps = .zero, walls: Set<Direction> = []) -> Workspace {
    var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), gaps: gaps, algorithm: .scrolling)
    ws.columnWidth = width
    ws.walls = walls
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// Left edges of the windows as the strip lays them out, on screen or not.
private func lefts(_ ws: Workspace) -> [CGFloat] {
    let frames = ws.tiledLayout().frames
    return ws.windows.map { frames[$0]!.minX }
}

struct ScrollingGeometryTests {
    @Test func `A lone column fills the screen`() {
        #expect(strip(1).layout().frames[1] == rect(-peek, 0, 1000 + 2 * peek, 600))
    }

    @Test func `Columns that fit are centred`() {
        let ws = strip(2, width: 0.49)
        #expect(ws.layout().frames[1] == rect(-15, 0, 515, 600))
        #expect(ws.layout().frames[2] == rect(500, 0, 515, 600))
    }

    @Test func `Inner and outer gaps match on both sides`() {
        let ws = strip(2, width: 0.49, gaps: Gaps(all: 10))
        #expect(ws.layout().frames[1] == rect(-5, 10, 500, 580))
        #expect(ws.layout().frames[2] == rect(505, 10, 500, 580))
    }

    @Test func `Columns that fit keep no gutters, only the outer gaps`() {
        let ws = strip(2, gaps: Gaps(all: 10))
        #expect(ws.stripArea == rect(-peek + 10, 10, 1030, 580))
        #expect(ws.layout().frames[1] == rect(-peek + 10, 10, 510, 580))
        #expect(ws.layout().frames[2] == rect(505, 10, 510, 580), "an inner gap between, the outer gap at the edge")
    }

    @Test func `Columns that do not fit keep the gutters they park in`() {
        let ws = strip(3, gaps: Gaps(all: 10))
        #expect(ws.stripArea == rect(5, 10, 990, 580), "half an inner gap clear of each gutter")
    }

    @Test func `A wall leaves no gutter whether the columns fit or not`() {
        #expect(strip(2, gaps: Gaps(all: 10), walls: [.left]).layout().frames == strip(2, gaps: Gaps(all: 10)).layout().frames)
        #expect(strip(3, gaps: Gaps(all: 10), walls: [.left]).stripArea == rect(-peek + 10, 10, 1010, 580))
    }

    @Test func `A new column opens right of the focused one and scrolls into view`() {
        var ws = strip(3)
        #expect(lefts(ws) == [-475, 25, 525], "the last column reaches into the empty gutter")
        ws.focus(1)
        ws.insert(4)
        #expect(ws.windows == [1, 4, 2, 3])
        #expect(lefts(ws) == [-25, 475, 975, 1475])
    }

    @Test func `Focusing scrolls as little as shows the column`() {
        var ws = strip(4)
        #expect(lefts(ws) == [-975, -475, 25, 525])
        ws.focus(.left)
        #expect(lefts(ws) == [-975, -475, 25, 525], "already in view")
        ws.focus(.left)
        #expect(lefts(ws) == [-500, 0, 500, 1000])
        ws.focus(.right)
        #expect(lefts(ws) == [-500, 0, 500, 1000], "already in view")
    }

    @Test func `Scrolled out windows hang off the edge with a sliver showing`() {
        var ws = strip(4)
        ws.focus(2)
        let frames = ws.layout().frames
        #expect(frames[1]!.maxX == 0, "peek showing, in the left gutter")
        #expect(frames[2]!.minX == 0)
        #expect(frames[4]!.minX == 1000, "peek showing, in the right gutter")
    }

    @Test func `Columns keep an inner gap from the slivers`() {
        var ws = strip(4, gaps: Gaps(all: 10))
        ws.focus(2)
        let frames = ws.layout().frames
        #expect(frames[1]!.maxX == 0)
        #expect(frames[2]!.minX == 10)
        #expect(frames[3]!.maxX == 990)
        #expect(frames[4]!.minX == 1000)
    }

    @Test func `The columns in view stay a gap from their neighbours, slack or not`() {
        var ws = strip(3, width: 0.49, gaps: Gaps(all: 10))
        var frames = ws.layout().frames
        #expect(frames[1]!.maxX == 40, "the slack widens the sliver")
        #expect(frames[2]!.minX == 50)
        #expect(frames[3]!.maxX == 1015, "the end column reaches the outer gap")
        ws.focus(1)
        frames = ws.layout().frames
        #expect(frames[1]!.minX == -15)
        #expect(frames[3]!.minX - frames[2]!.maxX == 10)
    }

    @Test func `At a wall scrolled out windows stay on screen behind the ones in view`() {
        var ws = strip(4, walls: [.left, .right])
        ws.focus(2)
        let layout = ws.layout()
        #expect(layout.frames[2]!.minX == -peek, "no gutter at a wall")
        #expect(layout.frames[1] == layout.frames[2]!.insetBy(dx: reach, dy: reach))
        #expect(layout.frames[4] == layout.frames[3]!.insetBy(dx: reach, dy: reach))
        #expect(layout.order == [2, 1, 3, 4])
    }

    @Test func `At a wall scrolled out windows hide wholly behind the column in view nearest it`() {
        var ws = strip(4, gaps: Gaps(all: 10), walls: [.left, .right])
        ws.focus(2)
        var frames = ws.layout().frames
        #expect(frames[2]!.minX == -15 && frames[3]!.maxX == 1015, "out to the outer gaps, over the half gaps")
        #expect(frames[1] == frames[2]!.insetBy(dx: reach, dy: reach), "neither it nor its shadow past the column")
        #expect(frames[4] == frames[3]!.insetBy(dx: reach, dy: reach))
        ws.minimumSizes[1] = CGSize(width: 600, height: 0)
        frames = ws.layout().frames
        #expect(frames[1]!.minX == frames[2]!.minX && frames[1]!.width == 600, "grows away from the wall")
    }

    @Test func `At a wall scrolled out windows hide behind a column of several too`() {
        var ws = strip(5, gaps: Gaps(all: 10), walls: [.left, .right])
        ws.focus(3)
        ws.join(.left)
        #expect(shape(ws.root) == "h[1 v[2 3] 4 5]")
        let frames = ws.layout().frames
        #expect(frames[1] == frames[2]!.insetBy(dx: reach, dy: reach), "not between 2 and 3")
    }

    @Test func `At a wall the column in view nearest it reaches out to the outer gap`() {
        var ws = strip(3, gaps: Gaps(all: 10), walls: [.left])
        var frames = ws.layout().frames
        #expect(frames[3]!.maxX == 1015, "the end column reaches into the empty gutter")
        #expect(frames[2] == rect(-15, 10, 520, 580), "not the gutter and half a gap short of it")
        #expect(frames[1] == frames[2]!.insetBy(dx: reach, dy: reach))
        ws = strip(3, gaps: Gaps(all: 10), walls: [.right])
        ws.focus(1)
        frames = ws.layout().frames
        #expect(frames[1]!.minX == -15)
        #expect(frames[2] == rect(495, 10, 520, 580))
        #expect(frames[3] == frames[2]!.insetBy(dx: reach, dy: reach))
    }

    @Test func `At a wall a column in view keeps its width beside a column's worth of room`() {
        var ws = strip(3, gaps: Gaps(all: 10), walls: [.left])
        ws.setWidth(ofColumn: 2, 0.8)
        #expect(ws.layout().frames[3] == rect(212, 10, 803, 580))
    }

    @Test func `The focused column stays in view when a column left of it closes`() {
        var ws = strip(5)
        ws.focus(3)
        #expect(ws.isInView(3))
        ws.remove(1)
        #expect(ws.isInView(3))
        #expect(lefts(ws) == [-500, 0, 500, 1000])
    }

    @Test func `The focused column stays in view when the display narrows`() {
        var ws = strip(4)
        ws.focus(2)
        ws.bounds = rect(-peek, 0, 500 + 2 * peek, 600)
        #expect(ws.isInView(2))
    }

    @Test func `The focused column stays in view when a column left of it grows to its minimum`() {
        var ws = strip(3)
        ws.minimumSizes[1] = CGSize(width: 900, height: 0)
        #expect(ws.isInView(3))
    }

    @Test func `Partly visible columns stay where the strip puts them`() {
        var ws = strip(3, width: 0.4)
        ws.focus(1)
        #expect(ws.layout().frames[3]!.minX == 775)
        #expect(!ws.isInView(3))
        #expect(ws.isInView(2))
    }

    @Test func `A column grows to its windows minimum width`() {
        var ws = strip(2)
        ws.minimumSizes[1] = CGSize(width: 700, height: 0)
        ws.focus(1)
        #expect(ws.layout().frames[1]!.width == 700)
        #expect(lefts(ws) == [-25, 675])
    }

    @Test func `Closing the last column scrolls back`() {
        var ws = strip(3)
        ws.remove(3)
        #expect(ws.focused == 2)
        #expect(lefts(ws) == [-peek, 500], "the two left fit, so out to the screen edges")
    }

    @Test func `The strip stays the root with one column left`() {
        var ws = strip(2)
        ws.join(.left)
        #expect(shape(ws.root) == "h[v[1 2]]")
        #expect(ws.layout().frames[1] == rect(-peek, 0, 1000 + 2 * peek, 300))
    }
}

struct ScrollingCentringTests {
    /// The middle of the focused window as the strip lays it out: 500 is the middle of the screen.
    private func middle(_ ws: Workspace) -> CGFloat { ws.tiledLayout().frames[ws.focused!]!.midX }

    @Test func `Always centres the focused column, end columns too`() {
        var ws = strip(4)
        ws.columnCentring = .always
        ws.focus(4)
        #expect(lefts(ws) == [-1250, -750, -250, 250], "the screen bare right of the last column")
        ws.focus(.left)
        #expect(lefts(ws) == [-750, -250, 250, 750], "in view, but centred all the same")
        ws.focus(1)
        #expect(lefts(ws) == [250, 750, 1250, 1750], "the screen bare left of the first column")
    }

    @Test func `Always leaves columns that all fit centred as a whole`() {
        var ws = strip(2, width: 0.49)
        ws.columnCentring = .always
        ws.focus(1)
        #expect(ws.layout().frames[1] == rect(-15, 0, 515, 600))
        #expect(ws.layout().frames[2] == rect(500, 0, 515, 600))
    }

    @Test func `Always fill centres the focused column, but takes an end column only to the edge`() {
        var ws = strip(4)
        ws.columnCentring = .alwaysFill
        ws.focus(4)
        #expect(lefts(ws) == [-975, -475, 25, 525], "out to the right edge, the column before it filling the rest")
        ws.focus(.left)
        #expect(lefts(ws) == [-750, -250, 250, 750])
        ws.focus(.left)
        #expect(lefts(ws) == [-250, 250, 750, 1250], "centred, half the first column showing")
        ws.focus(.left)
        #expect(lefts(ws) == [-25, 475, 975, 1475], "out to the left edge, as never leaves it")
    }

    @Test func `Always fill shows the first and last columns as never does`() {
        for gaps in [Gaps.zero, Gaps(all: 10)] {
            var fill = strip(4, gaps: gaps), never = strip(4, gaps: gaps)
            fill.columnCentring = .alwaysFill
            for id: WindowID in [1, 4] {
                fill.focus(id)
                never.focus(id)
                #expect(fill.layout().frames == never.layout().frames)
            }
        }
    }

    @Test func `Always fill keeps the display filled next to the ends too`() {
        var ws = strip(5, width: 0.3)
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        #expect(lefts(ws) == [-25, 275, 575, 875, 1175], "centring the second column would bare the left edge")
        ws.focus(3)
        #expect(middle(ws) == 500)
        ws.focus(4)
        #expect(lefts(ws) == [-475, -175, 125, 425, 725], "nor the right")
    }

    @Test func `Always fill fills the display again when the last column closes`() {
        var ws = strip(4)
        ws.columnCentring = .alwaysFill
        ws.focus(3)
        #expect(lefts(ws) == [-750, -250, 250, 750])
        ws.remove(4)
        #expect(ws.focused == 3)
        #expect(lefts(ws) == [-475, 25, 525], "out to the right edge, where always would leave it bare")
    }

    @Test func `On overflow centres a column only when it did not all show`() {
        var ws = strip(5, width: 0.3)
        ws.columnCentring = .onOverflow
        let start = lefts(ws)
        ws.focus(.left)
        #expect(lefts(ws) == start, "already in view")
        ws.focus(1)
        #expect(middle(ws) == 500, "out of view, so to the middle")
        #expect(lefts(ws) == [350, 650, 950, 1250, 1550])
        ws.focus(.right)
        #expect(lefts(ws) == [350, 650, 950, 1250, 1550], "already in view")
        ws.focus(5)
        #expect(middle(ws) == 500)
    }

    @Test func `Never scrolls as little as before`() {
        var ws = strip(4)
        ws.focus(1)
        #expect(lefts(ws) == [-25, 475, 975, 1475], "the first column reaches into the empty gutter")
    }
}

struct ScrollingWallAlignTests {
    /// The outer-gap edges of `strip` with gaps of 10.
    private let edges = (left: CGFloat(-15), right: CGFloat(1015))

    /// The widest stretch between the outer gaps that no window covers.
    private func bare(_ ws: Workspace) -> CGFloat {
        let spans = ws.layout().frames.values.map { (max($0.minX, edges.left), min($0.maxX, edges.right)) }
            .filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var reached = edges.left, widest: CGFloat = 0
        for (minX, maxX) in spans {
            widest = max(widest, minX - reached)
            reached = max(reached, maxX)
        }
        return max(widest, edges.right - reached)
    }

    /// Whether a window of the strip, where it has them before parking, is part past a wall of `ws`.
    private func straddles(_ ws: Workspace) -> Bool {
        ws.stripFrames.values.contains { frame in
            ws.walls.contains(.right) && frame.minX < edges.right - 0.5 && frame.maxX > edges.right + 0.5
                || ws.walls.contains(.left) && frame.minX < edges.left - 0.5 && frame.maxX > edges.left + 0.5
        }
    }

    @Test func `Centred at a wall, the column beside it lines up with the wall`() {
        var ws = strip(4, gaps: Gaps(all: 10), walls: [.right])
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        let frames = ws.layout().frames
        #expect(frames[3] == rect(515, 10, 500, 580), "whole, out to the outer gap at the wall")
        #expect(frames[2] == rect(10, 10, 495, 580), "the focused column whole on the far half")
        #expect(frames[4] == frames[3]!.insetBy(dx: reach, dy: reach), "the column beyond hidden behind it")
        #expect(bare(ws) <= 10, "no room bare by more than a gap")
    }

    @Test func `At a left wall the column beside it lines up with the wall too`() {
        var ws = strip(4, gaps: Gaps(all: 10), walls: [.left])
        ws.columnCentring = .alwaysFill
        ws.focus(3)
        let frames = ws.layout().frames
        #expect(frames[2] == rect(-15, 10, 500, 580), "whole, out to the outer gap at the wall")
        #expect(frames[3] == rect(495, 10, 495, 580))
        #expect(bare(ws) <= 10)
    }

    @Test func `A focused column too wide to show its neighbour whole ends at the wall`() {
        var ws = strip(4, gaps: Gaps(all: 10), walls: [.right])
        ws.columnCentring = .alwaysFill
        ws.setWidth(ofColumn: 1, 0.75)
        ws.focus(2)
        let frames = ws.layout().frames
        #expect(frames[2]!.maxX == 1015, "the focused column out to the wall")
        #expect(frames[3] == frames[2]!.insetBy(dx: reach, dy: reach), "its neighbour wholly beyond, hidden")
    }

    @Test func `Scrolling as little as shows a column lines it up with a wall too`() {
        var ws = strip(5, width: 0.4, gaps: Gaps(all: 10), walls: [.right])
        for id: WindowID in [4, 3, 2] {
            ws.focus(id)
            #expect(!straddles(ws), "focus \(id)")
            #expect(ws.layout().frames.values.map(\.maxX).max() == 1015, "focus \(id)")
        }
    }

    @Test func `Without walls the strip centres as before`() {
        var ws = strip(4)
        ws.columnCentring = .alwaysFill
        ws.focus(3)
        #expect(lefts(ws) == [-750, -250, 250, 750])
        ws.focus(2)
        #expect(lefts(ws) == [-250, 250, 750, 1250])
        ws.columnCentring = .always
        ws.focus(4)
        #expect(lefts(ws) == [-1250, -750, -250, 250])
        let area = ws.stripArea, spans = ws.columnSpans(in: area)
        #expect(ws.wallAligned(123, spans: spans, in: area) == 123)
    }

    @Test func `Scrolled freely at a wall the strip follows the fingers, and rests lined up`() {
        var ws = strip(4, gaps: Gaps(all: 10), walls: [.right])
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        ws.beginFreeScroll()
        let held = lefts(ws)
        ws.scrollFreely(by: 37)
        #expect(lefts(ws) == held.map { $0 - 37 }, "no lining up while held")
        ws.endFreeScroll()
        #expect(!straddles(ws))
    }

    @Test func `A display coming beside a strip lines it up where it shows`() {
        var ws = strip(4, gaps: Gaps(all: 10))
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        #expect(!straddles(ws))
        ws.walls = [.right]
        #expect(straddles(ws), "centred as it was, a column now part past the wall")
        ws.alignToWalls()
        #expect(!straddles(ws))
        let frame = ws.layout().frames[2]!
        #expect(frame.minX >= edges.left && frame.maxX <= edges.right, "the focused column still whole")
    }

    @Test func `Lining up with walls leaves a strip scrolled freely alone`() {
        var ws = strip(4, gaps: Gaps(all: 10))
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        ws.walls = [.right]
        ws.beginFreeScroll()
        let held = lefts(ws)
        ws.alignToWalls()
        #expect(lefts(ws) == held)
    }

    @Test func `Lining up again changes nothing`() {
        var ws = strip(4, gaps: Gaps(all: 10))
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        ws.walls = [.right]
        ws.alignToWalls()
        let once = ws.layout()
        ws.alignToWalls()
        #expect(ws.layout() == once)
    }

    @Test func `An area an odd number of points wide lines up at the wall all the same`() {
        // FlipGo beside the built-in display: 1243 points between the outer gaps, two half-width columns one over.
        var ws = Workspace(bounds: rect(1800, -144, 1280, 1570), gaps: Gaps(all: 8), algorithm: .scrolling)
        ws.columnWidth = 0.5
        ws.walls = [.left]
        ws.columnCentring = .alwaysFill
        for id in 0..<5 { ws.insert(WindowID(id + 1)) }
        for id: WindowID in [1, 2, 3, 4, 5, 4, 3, 2, 1] {
            ws.focus(id)
            let frames = ws.layout().frames
            #expect(frames.values.allSatisfy { $0.minX >= 1800 }, "focus \(id): nothing past the wall")
            let nearest = frames.values.map(\.minX).min()!
            #expect(nearest - 1808 <= 8, "focus \(id): no more than a gap bare at the wall")
        }
    }

    @Test func `The built-in display lines up at its wall too`() {
        // The built-in display with the external one right of it: 1784 points between the outer gaps.
        var ws = Workspace(bounds: rect(0, 39, 1800, 1066), gaps: Gaps(all: 8), algorithm: .scrolling)
        ws.columnWidth = 0.5
        ws.walls = [.right]
        ws.columnCentring = .alwaysFill
        for id in 0..<5 { ws.insert(WindowID(id + 1)) }
        for id: WindowID in [1, 2, 3, 4, 5, 4, 3, 2, 1] {
            ws.focus(id)
            let frames = ws.layout().frames
            #expect(frames.values.allSatisfy { $0.maxX <= 1800 }, "focus \(id): nothing past the wall")
            let nearest = frames.values.map(\.maxX).max()!
            #expect(1792 - nearest <= 8, "focus \(id): no more than a gap bare at the wall")
        }
    }

    @Test func `Next to the strip's start, a wide neighbour at the wall goes past it`() {
        // The built-in display, Claude's column at 80% beside the focused second column: lined up, the first column
        // reaches into the gutter at the strip's start, and the focused one reaches the wall over what is left.
        for share in [0.6, 0.7, 0.8] {
            var ws = Workspace(bounds: rect(0, 39, 1800, 1066), gaps: Gaps(all: 8), algorithm: .scrolling)
            ws.columnWidth = 0.5
            ws.walls = [.right]
            ws.columnCentring = .alwaysFill
            for id in 0..<5 { ws.insert(WindowID(id + 1)) }
            ws.setWidth(ofColumn: 2, share)
            ws.focus(2)
            let layout = ws.layout(), frames = layout.frames
            #expect(frames.values.allSatisfy { $0.maxX <= 1800 }, "\(share): nothing past the wall")
            #expect(1792 - frames.values.map(\.maxX).max()! <= 8, "\(share): no more than a gap bare at the wall")
            #expect(frames[2]!.minX >= 8 && frames[2]!.maxX <= 1792, "\(share): the focused column whole")
            #expect(ws.layout() == layout && ws.layout() == layout, "\(share): the same however often laid out")
        }
    }

    @Test func `Next to the strip's start, a neighbour going past the wall leaves no more room than is reached over`() {
        // The first column such that, lined up past the wall, the straddler leaves a little less than the narrowest
        // column on screen, but with the half gap the column in view keeps beside it a little more: that column
        // reaches over it all the same, as both measure the room as a column's span is measured.
        for share in [0.6, 0.7, 0.8] {
            var ws = Workspace(bounds: rect(0, 39, 1800, 1066), gaps: Gaps(all: 8), algorithm: .scrolling)
            ws.columnWidth = 0.5
            ws.walls = [.right]
            ws.columnCentring = .alwaysFill
            for id in 0..<5 { ws.insert(WindowID(id + 1)) }
            ws.setWidth(ofColumn: 0, 0.412)
            ws.setWidth(ofColumn: 2, share)
            ws.focus(2)
            let frames = ws.layout().frames.values.filter { $0.minX >= 0 && $0.maxX <= 1800 }
            #expect(1792 - frames.map(\.maxX).max()! <= 8, "\(share): no more than a gap bare at the wall")
        }
    }

    /// The external display beside the built-in one, its wall at the left, the strip's last column focused.
    private func flipGo(shares: [Double]) -> Workspace {
        var ws = Workspace(bounds: rect(1800, -294, 1280, 1570), gaps: Gaps(all: 8), algorithm: .scrolling)
        ws.columnWidth = 0.5
        ws.walls = [.left]
        ws.columnCentring = .alwaysFill
        for id in 0..<shares.count { ws.insert(WindowID(id + 1)) }
        for (i, share) in shares.enumerated() { ws.setWidth(ofColumn: i, share) }
        ws.focus(WindowID(shares.count))
        return ws
    }

    @Test func `At the strip's end a column part past the wall stays flush at it, under the column in view`() {
        let ws = flipGo(shares: [0.5, 0.5, 0.5, 0.5, 0.57])
        let layout = ws.layout(), frames = layout.frames
        #expect(frames[4]!.minX == 1800, "the curtain held at the wall, as the strip holds a window that reaches it")
        #expect(frames[4]!.maxX <= frames[5]!.maxX - reach, "its far edge and shadow under the focused column")
        #expect(layout.order.firstIndex(of: 5)! < layout.order.firstIndex(of: 4)!, "behind the focused column")
        #expect(frames.values.map(\.minX).min()! - 1800 <= 8, "no room bare at the wall")
        #expect(frames[3] == frames[5]!.insetBy(dx: reach, dy: reach), "one wholly past the wall hidden as before")
        #expect(ws.layout() == layout, "the same laid out again")
    }

    @Test func `At the strip's end a column part past the wall hides behind a column of several, not as a curtain`() {
        // The focused end column holds two windows one above the other: a curtain under it would show in the gap
        // between them, so the neighbour part past the wall hides behind the bigger one instead.
        var ws = flipGo(shares: [0.5, 0.5, 0.5, 0.5, 0.57])
        ws.insert(6)
        ws.focus(6)
        let joined = ws.join(.left)
        #expect(joined && ws.stripColumns.last == [5, 6])
        let frames = ws.layout().frames
        let cover = [frames[5]!, frames[6]!].max { $0.width * $0.height < $1.width * $1.height }!
        #expect(cover.contains(frames[4]!), "hidden inside the bigger window of the column, \(frames[4]!) in \(cover)")
        let between = CGRect(x: frames[5]!.minX, y: frames[5]!.maxY, width: frames[5]!.width,
                             height: frames[6]!.minY - frames[5]!.maxY)
        #expect(!frames[4]!.intersects(between.insetBy(dx: 0, dy: 0.5)), "nothing in the gap between them")
    }

    /// The built-in display, its wall at the right, `n` columns of half its width, `focused` focused.
    private func builtIn(_ n: Int, focused: WindowID, walls: Set<Direction> = [.right]) -> Workspace {
        var ws = Workspace(bounds: rect(0, 0, 1800, 1169), gaps: Gaps(all: 8), algorithm: .scrolling)
        ws.columnWidth = 0.5
        ws.walls = walls
        ws.columnCentring = .alwaysFill
        for id in 1...n { ws.insert(WindowID(id)) }
        ws.focus(focused)
        return ws
    }

    @Test func `The cover at a wall is the column in view there, where windows hide behind it`() {
        let ws = builtIn(7, focused: 3)
        #expect(ws.wallCovers(ws.stripFrames) == [4], "5, 6 and 7 hide behind 4")
    }

    @Test func `The cover at a wall is the column a curtain hangs under`() {
        // The external display's left wall, the strip's end there: 4 part past the wall hangs as a curtain under 5.
        let ws = flipGo(shares: [0.5, 0.5, 0.5, 0.5, 0.57])
        #expect(ws.layout().frames[4]!.minX == 1800, "4 a curtain at the wall")
        #expect(ws.wallCovers(ws.stripFrames) == [5])
    }

    @Test func `Nothing parked at a wall, no cover`() {
        let ws = builtIn(2, focused: 1)
        #expect(ws.wallCovers(ws.stripFrames).isEmpty)
        var left = builtIn(7, focused: 6)
        left.walls = [.right]
        #expect(left.wallCovers(left.stripFrames).isEmpty, "parked off the left edge, which is no wall")
    }

    @Test func `Between two walls each has its cover, the left one's first`() {
        let ws = builtIn(7, focused: 4, walls: [.left, .right])
        let frames = ws.layout().frames
        let covers = ws.wallCovers(ws.stripFrames)
        #expect(covers.count == 2)
        #expect(covers.first.map { frames[$0]!.minX < 900 } == true, "the left wall's first")
        #expect(covers.last.map { frames[$0]!.maxX > 900 } == true)
    }

    @Test func `A pinned side has no cover`() {
        var ws = builtIn(7, focused: 7)
        _ = ws.pin(.right)
        #expect(ws.pinnedIndex(.right) != nil)
        ws.focus(3)
        #expect(ws.wallCovers(ws.stripFrames).isEmpty, "the pin is put in front by its own ordering")
    }

    @Test func `At a wall the column in view goes up over the ones hiding behind it`() {
        var ws = Workspace(bounds: rect(0, 0, 1800, 1169), gaps: Gaps(all: 8), algorithm: .scrolling)
        ws.columnWidth = 0.5
        ws.walls = [.right]
        ws.columnCentring = .alwaysFill
        for id in 1...7 { ws.insert(WindowID(id)) }
        ws.focus(3)
        let layout = ws.layout(), frames = layout.frames
        #expect(frames[4]!.minX > frames[3]!.maxX && frames[4]!.maxX <= 1800, "4 in view at the wall")
        let hiding: [WindowID] = [5, 6, 7]
        #expect(hiding.allSatisfy { frames[4]!.contains(frames[$0]!) }, "5, 6 and 7 hide behind it")
        // As a let-go left them, the focus then still on 5, of the same app: 4 under two of those hiding behind it.
        let current: [WindowID] = [3, 5, 6, 4, 7, 2, 1]
        let raises = layout.raises(current: current)
        #expect(raises.last == 4, "4 ends on top of its pile")
        #expect(layout.raises(current: layout.order).isEmpty, "nothing once in order")
    }

    @Test func `Scrolled past a wall a window stays held at it, then hides once, without a jump`() {
        // A point at a time across the strip while fingers hold it: each window crossing the wall keeps its size held
        // at the wall, then changes size once, as it goes wholly past and hides behind the column in view.
        var ws = flipGo(shares: [0.5, 0.5, 0.5, 0.5, 0.57])
        ws.beginFreeScroll()
        ws.scrollFreely(by: -100_000)
        var last: [WindowID: CGRect] = [:], resized: [WindowID: Int] = [:]
        while ws.shownOffset < 1860, ws.scrollFreely(by: 1) != 0 {
            let strip = ws.stripFrames
            for (id, frame) in ws.layout().frames {
                if frame.size == strip[id]!.size, strip[id]!.minX < 1800 - 0.5 {
                    #expect(frame.minX == 1800, "\(id) at \(ws.shownOffset): held at the wall")
                }
                if let was = last[id] {
                    if was.size != frame.size { resized[id, default: 0] += 1 }
                    if was.size == frame.size, frame.size == strip[id]!.size {
                        #expect(abs(was.minX - frame.minX) <= 2, "\(id) at \(ws.shownOffset): no jump")
                    }
                }
                last[id] = frame
            }
        }
        for id: WindowID in [1, 2, 3] { #expect(resized[id] == 1, "\(id) changes size once crossing the wall") }
    }

    @Test func `Glided past a wall a window hiding there changes size once at most behind each column`() {
        // A let-go's glide, a step at a time between where the strip was and where it rests, at whole points as the
        // animator writes them: a window hiding behind the column in view at the wall keeps one size behind it, sized
        // by where that column rests, as the column changes its own on the way: kept no bigger than the column is, it
        // changes once at most there.
        for (from, to): (WindowID, WindowID) in [(6, 3), (7, 4), (3, 6), (4, 7)] {
            var ws = Workspace(bounds: rect(0, 0, 1800, 1169), gaps: Gaps(all: 8), algorithm: .scrolling)
            ws.columnWidth = 0.5
            ws.walls = [.right]
            ws.columnCentring = .alwaysFill
            for id in 1...7 { ws.insert(WindowID(id)) }
            ws.setWidth(ofColumn: 4, 0.8)
            ws.focus(from)
            let starts = ws.stripFrames
            ws.focus(to)
            let targets = ws.stripFrames
            var last: [WindowID: (cover: WindowID?, size: CGSize)] = [:], resized: [WindowID: Int] = [:]
            let steps = 400
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let frames = targets.merging(starts) { target, start in
                    CGRect(x: (start.minX + (target.minX - start.minX) * t).rounded(), y: target.minY,
                           width: (start.width + (target.width - start.width) * t).rounded(), height: target.height)
                }
                let placed = ws.placeStrip(frames, resting: targets)
                // The column in view nearest the wall, which those hiding there hide behind.
                let cover = frames.filter { $0.value.minX >= -1 && $0.value.maxX <= 1801 }
                    .max { $0.value.maxX < $1.value.maxX }?.key
                for (id, frame) in placed {
                    // Hiding: smaller than its tile, behind the column in view at the wall.
                    let hiding = frame.width < frames[id]!.width - 1
                    if hiding, let was = last[id], was.cover == cover, was.size != frame.size {
                        resized[id, default: 0] += 1
                    }
                    last[id] = hiding ? (cover, frame.size) : nil
                }
                if step == steps { #expect(placed == ws.layout().frames, "\(from) to \(to): rests as laid out") }
            }
            #expect(resized.values.allSatisfy { $0 <= 1 }, "\(from) to \(to): \(resized)")
        }
    }

    @Test func `A column part past the wall too wide to curtain under the column in view hides behind it`() {
        let ws = flipGo(shares: [0.5, 0.6, 0.25, 0.57])
        let frames = ws.layout().frames
        #expect(frames[3]!.minX >= 1808, "the column in view nearest the wall")
        #expect(frames[2]!.minX >= frames[3]!.minX && frames[2]!.maxX <= frames[3]!.maxX, "hidden behind it, not flush")
    }

    @Test func `At a wall a nudge let go keeps the focused column, as without one`() {
        for walls: Set<Direction> in [[.right], []] {
            for (delta, settles): (CGFloat, WindowID) in [(37, 2), (-37, 2), (300, 3)] {
                var ws = strip(4, gaps: Gaps(all: 10), walls: walls)
                ws.columnCentring = .alwaysFill
                ws.focus(2)
                let rested = ws.layout()
                ws.beginFreeScroll()
                ws.scrollFreely(by: delta)
                #expect(ws.endFreeScroll() == settles, "walls \(walls), \(delta) pt")
                if settles == 2 { #expect(ws.layout() == rested, "walls \(walls), \(delta) pt: back where it rested") }
            }
        }
    }

    @Test func `Between two walls focusing the same column again changes nothing`() {
        var ws = strip(6, gaps: Gaps(all: 10), walls: [.left, .right])
        for (i, share) in [0.5, 0.4, 0.25, 0.6, 0.33, 0.4].enumerated() { ws.setWidth(ofColumn: i, share) }
        ws.focus(1)
        ws.focus(3)
        let once = ws.layout()
        ws.focus(3)
        #expect(ws.layout() == once)
    }

    @Test func `Pinning the focused column leaves the band lined up with a wall`() {
        var ws = strip(4, width: 0.4, gaps: Gaps(all: 10), walls: [.right])
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        ws.pin(.left)
        #expect(ws.focused == 2 && ws.bandFocus == 3, "the pin focused, focus in the band gone back beside it")
        #expect(bare(ws) <= 10, "the band lined up with the wall from the window focus went back to")
    }

    @Test func `Between two walls nothing straddles either at rest`() {
        var ws = strip(5, gaps: Gaps(all: 10), walls: [.left, .right])
        ws.columnCentring = .alwaysFill
        for id: WindowID in [1, 2, 3, 4, 5] {
            ws.focus(id)
            #expect(!straddles(ws), "focus \(id)")
            let frame = ws.layout().frames[id]!
            #expect(frame.minX >= edges.left && frame.maxX <= edges.right, "focus \(id) whole")
        }
    }
}

struct ScrollingClickHoldTests {
    /// The middle of the focused window as the strip lays it out: 500 is the middle of the screen.
    private func middle(_ ws: Workspace) -> CGFloat { ws.tiledLayout().frames[ws.focused!]!.midX }

    /// Four columns, the last focused and centred, so the third shows half of itself at the left edge, to 250.
    private func centredStrip() -> Workspace {
        var ws = strip(4)
        ws.columnCentring = .always
        ws.focus(4)
        return ws
    }

    @Test func `A click holds the strip still, then centres the window it focused`() {
        var ws = centredStrip()
        ws.focus(3, holdingScroll: true)
        #expect(ws.focused == 3)
        #expect(ws.holdsScroll)
        #expect(lefts(ws) == [-1250, -750, -250, 250], "where it was pressed")
        #expect(ws.layout().frames[3] == rect(-250, 0, 500, 600))
        ws.revealFocus()
        #expect(!ws.holdsScroll)
        #expect(lefts(ws) == [-750, -250, 250, 750])
    }

    @Test func `A press on a half-shown column held still is over its own tile`() {
        let press = CGPoint(x: 100, y: 300)
        var held = centredStrip(), scrolled = centredStrip()
        held.focus(3, holdingScroll: true)
        scrolled.focus(3)
        #expect(held.dropHit(at: press, in: held.layout(), excluding: 3) == .own)
        #expect(scrolled.dropHit(at: press, in: scrolled.layout(), excluding: 3) != .own, "centred from under the press")
    }

    @Test func `A click holds the strip where it shows, not where it last scrolled to`() {
        var ws = centredStrip()
        ws.minimumSizes[1] = CGSize(width: 900, height: 0)
        let shown = lefts(ws)
        ws.focus(3, holdingScroll: true)
        #expect(lefts(ws) == shown, "the first column grew, which scrolled the focused one on")
    }

    @Test func `On overflow, a held click centres only a column that did not all show`() {
        var ws = strip(5, width: 0.3)
        ws.columnCentring = .onOverflow
        let start = lefts(ws)
        ws.focus(4, holdingScroll: true)
        ws.revealFocus()
        #expect(lefts(ws) == start, "in view, so left where it is")
        ws.focus(1, holdingScroll: true)
        #expect(lefts(ws) == start, "held where it was pressed")
        ws.revealFocus()
        #expect(middle(ws) == 500)
    }

    @Test func `Always fill holds a click still too, then takes an end column to the edge`() {
        var ws = strip(4)
        ws.columnCentring = .alwaysFill
        ws.focus(2)
        ws.focus(1, holdingScroll: true)
        #expect(ws.holdsScroll)
        #expect(lefts(ws) == [-250, 250, 750, 1250], "where it was pressed")
        ws.revealFocus()
        #expect(lefts(ws) == [-25, 475, 975, 1475])
    }

    @Test func `Focus moved another way scrolls as ever and lets the hold go`() {
        var ws = centredStrip()
        ws.focus(3, holdingScroll: true)
        ws.focus(2)
        #expect(!ws.holdsScroll)
        #expect(middle(ws) == 500)
    }

    @Test func `A drop back beside where a held click left it leaves it where it is, once revealed`() {
        var held = centredStrip()
        held.focus(3, holdingScroll: true)
        var dropped = held
        let moved = dropped.drop(3, onto: 4, .split(.left))
        #expect(moved)
        #expect(lefts(dropped) == [-750, -250, 250, 750], "the drop focuses it, and so centres it")
        #expect(held.layout().frames != dropped.layout().frames, "held, the strip has not scrolled yet")
        var asIs = held
        asIs.revealFocus()
        #expect(asIs.layout().frames == dropped.layout().frames)
    }

    @Test func `Never holds a clicked column where it shows too, till the click lets go`() {
        var held = strip(4), plain = strip(4)
        let before = held.layout().frames
        held.focus(2, holdingScroll: true)
        plain.focus(2)
        #expect(held.holdsScroll)
        #expect(held.layout().frames == before, "the tree stays where the screen shows it while the button is down")
        held.revealFocus()
        #expect(held.layout().frames == plain.layout().frames, "let go, it scrolls as a plain focus does")
    }

    @Test func `Beside a pin a clicked column partly in view is held too`() throws {
        var ws = strip(5)
        ws.focus(1)
        do { let r = ws.pin(.left); #expect(r == .changed) }
        ws.focus(5)
        let before = ws.layout().frames
        // Window 4's column shows only in part, its left part under the pin.
        let shown = try #require(before[4])
        try #require(shown.minX < ws.bandRect.minX && shown.maxX > ws.bandRect.minX)
        var held = ws, plain = ws
        held.focus(4, holdingScroll: true)
        plain.focus(4)
        try #require(plain.layout().frames != before, "focusing it would scroll")
        #expect(held.holdsScroll)
        #expect(held.layout().frames == before)
        held.revealFocus()
        #expect(held.layout().frames == plain.layout().frames)
    }

    @Test func `Revealing with no click held changes nothing`() {
        var ws = strip(4)
        ws.minimumSizes[1] = CGSize(width: 900, height: 0)
        let before = ws
        ws.revealFocus()
        #expect(ws == before, "a reveal would have taken the scroll the layout shows")
    }
}

struct ScrollingCommandTests {
    @Test func `Move swaps a lone window's column with its neighbour, width and all`() {
        var ws = strip(3)
        ws.focus(1)
        #expect(ws.resize(by: 100) == true)
        #expect(ws.move(.right) == true)
        #expect(ws.windows == [2, 1, 3])
        #expect(ws.tiledLayout().frames[1]!.width == 600)
        var single = strip(1)
        #expect(single.move(.right) == false)
    }

    @Test func `Move left or right takes a window out of a shared column`() {
        var ws = strip(3)
        ws.focus(2)
        ws.join(.left)
        #expect(shape(ws.root) == "h[v[1 2] 3]")
        #expect(ws.move(.right) == true)
        #expect(shape(ws.root) == "h[1 2 3]")
        ws.join(.left)
        #expect(ws.move(.left) == true)
        #expect(shape(ws.root) == "h[2 1 3]")
    }

    @Test func `Move up and down stay within the column`() {
        var ws = strip(2)
        ws.join(.left)
        #expect(ws.move(.up) == true)
        #expect(shape(ws.root) == "h[v[2 1]]")
        #expect(ws.move(.up) == false)
        #expect(shape(ws.root) == "h[v[2 1]]")
        var lone = strip(2)
        #expect(lone.move(.down) == false)
    }

    @Test func `Join takes the width of the column it joins`() {
        var ws = strip(3)
        ws.focus(3)
        #expect(ws.resize(by: 200) == true)
        ws.focus(2)
        #expect(ws.join(.right) == true)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        #expect(ws.tiledLayout().frames[2]!.width == 700)
    }

    @Test func `Resizing width changes the column, height the stack`() {
        var ws = strip(2)
        #expect(ws.resize(by: 100, along: .horizontal) == true)
        #expect(ws.tiledLayout().frames[2]!.width == 595, "a share of the screen it fitted, then of the gutters' less")
        #expect(ws.resize(by: 100, along: .vertical) == false, "a lone window has no stack")
        ws.join(.left)
        #expect(ws.resize(by: 60, along: .vertical) == true)
        #expect(ws.tiledLayout().frames[2]!.height == 360)
    }

    @Test func `A lone column cannot be resized out of sight`() {
        var ws = strip(1)
        #expect(ws.resize(by: 100) == false)
        ws.insert(2)
        #expect(ws.tiledLayout().frames[1]!.width == 525)
    }

    @Test func `Dragging an edge sets the column width`() {
        var ws = strip(2)
        #expect(ws.resize(2, to: CGSize(width: 400, height: 600), moving: [.left]) == true)
        #expect(ws.tiledLayout().frames[2]!.width == 400)
    }

    @Test func `Balance resets every column to the default width`() {
        var ws = strip(2)
        ws.resize(by: 200)
        ws.balanceSizes()
        #expect(lefts(ws) == [-peek, 500])
    }

    @Test func `Flatten gives every window a column of its own`() {
        var ws = strip(3)
        ws.join(.left)
        ws.flatten()
        #expect(shape(ws.root) == "h[1 2 3]")
    }

    @Test func `Layout commands leave the strip alone`() {
        var ws = strip(2)
        ws.setMode(.accordion)
        ws.setOrientation(.vertical)
        #expect(shape(ws.root) == "h[1 2]")
        ws.join(.left)
        ws.setMode(.accordion)
        #expect(shape(ws.root) == "h[av[1 2]]")
    }

    @Test func `Switching to scrolling keeps the windows in order`() {
        var ws = workspace(3)
        ws.columnWidth = 0.5
        ws.setAlgorithm(.scrolling)
        #expect(shape(ws.root) == "h[1 2 3]")
        #expect(lefts(ws) == [-425, 50, 525], "columns 475 wide between the gutters")
    }
}

struct ScrollingGlideTests {
    @Test func `A window placed where the strip has it stops at a wall`() {
        let off = rect(-900, 0, 500, 600), wide = rect(-900, 0, 2000, 600)
        #expect(strip(2).keptOffWalls(off) == off, "no wall, it hangs off the screen")
        let left = strip(2, walls: [.left])
        #expect(left.keptOffWalls(off) == rect(-peek, 0, 500, 600))
        #expect(left.keptOffWalls(rect(900, 0, 500, 600)).minX == 900, "no wall on the right")
        let both = strip(2, walls: [.left, .right])
        #expect(both.keptOffWalls(rect(900, 0, 500, 600)) == rect(1000 + peek - 500, 0, 500, 600))
        #expect(both.keptOffWalls(wide).minX == -peek, "wider than the screen, it stays at the left wall")
    }

    @Test func `Placing the strip frames gives the layout`() {
        for walls: Set<Direction> in [[], [.left], [.left, .right]] {
            var ws = strip(10, walls: walls)
            ws.focus(4)
            #expect(ws.placeStrip(ws.stripFrames) == ws.layout().frames, "walls \(walls)")
        }
    }

    @Test func `Halfway through a long scroll the columns between are on screen where the strip has them`() {
        var ws = strip(10)
        let from = ws.stripFrames
        ws.focus(1)
        let to = ws.stripFrames
        let halfway = from.mapValues { $0 }.merging(to) { a, b in
            rect((a.minX + b.minX) / 2, a.minY, a.width, a.height)
        }
        let placed = ws.placeStrip(halfway)
        let passing = (2...9).map(WindowID.init).filter { id in
            placed[id] == halfway[id] && placed[id]!.minX >= ws.bounds.minX && placed[id]!.maxX <= ws.bounds.maxX
        }
        #expect(!passing.isEmpty)
        // Not every window lands parked against one edge or the other, as gliding the parked frames would have it.
        #expect(Set((1...10).map { placed[WindowID($0)]!.minX }).count > 2)
    }
}

struct ScrollingFullscreenTests {
    /// `strip(n)` with window 2 focused and fullscreen.
    private func fullscreen(_ n: Int = 4, gaps: Gaps = .zero, walls: Set<Direction> = [],
                            focusChange: FullscreenFocus = .exit) -> Workspace {
        var ws = strip(n, gaps: gaps, walls: walls)
        ws.fullscreenFocus = focusChange
        ws.focus(2)
        ws.toggleFullscreen()
        return ws
    }

    @Test func `Fullscreen widens its column and pushes the neighbours off`() {
        let ws = fullscreen(gaps: Gaps(all: 10))
        let frames = ws.layout().frames
        #expect(frames[2] == ws.stripArea.insetBy(dx: 5, dy: 0), "clear of the gutters")
        #expect(frames[2]!.minX - frames[1]!.maxX == 10, "a gap either side")
        #expect(frames[1]!.maxX == ws.bounds.minX + peek)
        #expect(frames[3]!.minX == ws.bounds.maxX - peek)
        #expect(frames[3]!.minX - frames[2]!.maxX == 10)
        #expect(frames[1]!.width == 490, "neighbours keep their width")
        #expect(!ws.isInView(1) && !ws.isInView(3) && ws.isInView(2))
        #expect(ws.layout().order.first == 2)
    }

    @Test func `Filling, a pushing fullscreen window covers the gutters and its neighbours' peeks`() {
        var ws = fullscreen(gaps: Gaps(all: 10))
        ws.pushedFullscreenFills = true
        let frames = ws.layout().frames
        #expect(frames[2] == Gaps(all: 10).inset(ws.bounds), "where the system's Fill puts it")
        #expect(frames[1]!.maxX == ws.bounds.minX + peek, "the neighbours park as before, under it")
        #expect(frames[3]!.minX == ws.bounds.maxX - peek)
        // Only the focused window's column fills; ending fullscreen puts the strip back as before.
        ws.toggleFullscreen()
        ws.pushedFullscreenFills = false
        var plain = strip(4, gaps: Gaps(all: 10))
        plain.focus(2)
        #expect(ws.layout().frames == plain.layout().frames)
    }

    @Test func `A window shown fullscreen or not lays the strip out so, whatever the tree says`() {
        let full = fullscreen(gaps: Gaps(all: 10))
        var plain = strip(4, gaps: Gaps(all: 10))
        plain.focus(2)
        // Still being filled, or put back, by something else: the others go around where it is going.
        #expect(plain.showing(2, fullscreen: true).layout().frames == full.layout().frames)
        #expect(full.showing(2, fullscreen: false).layout().frames == plain.layout().frames)
        #expect(full.showing(2, fullscreen: true).layout().frames == full.layout().frames)
    }

    @Test func `Fullscreen at an end of the strip reaches through the empty gutter there`() {
        var ws = strip(4, gaps: Gaps(all: 10))
        ws.fullscreenFocus = .follow
        ws.focus(1)
        ws.toggleFullscreen()
        let inset = Gaps(all: 10).inset(ws.bounds)
        var frame = ws.layout().frames[1]!
        #expect(frame.minX == inset.minX, "no gutter left of the first column")
        #expect(frame.maxX == ws.stripArea.maxX - 5, "a gap from the gutter its neighbour parks in")
        ws.focus(4)
        frame = ws.layout().frames[4]!
        #expect(frame.maxX == inset.maxX && frame.minX == ws.stripArea.minX + 5)
    }

    @Test func `Ending fullscreen puts the strip back where it was`() {
        var ws = strip(4)
        ws.focus(2)
        let before = ws.layout()
        ws.toggleFullscreen()
        #expect(ws.layout() != before)
        ws.toggleFullscreen()
        #expect(ws.layout() == before)
    }

    @Test func `Over covers the columns where they are`() {
        var ws = strip(4)
        ws.fullscreenPushesStrip = false
        ws.focus(2)
        let before = ws.layout().frames
        ws.toggleFullscreen()
        let frames = ws.layout().frames
        #expect(frames[2] == ws.bounds)
        #expect(frames[1] == before[1] && frames[3] == before[3])
    }

    @Test func `Focusing a neighbour with exit ends fullscreen and scrolls to it`() {
        var ws = fullscreen()
        ws.focus(.right)
        #expect(ws.fullscreenWindows.isEmpty)
        #expect(ws.isInView(3) && ws.isInView(2))
    }

    @Test func `With follow the neighbour takes over the screen`() {
        var ws = fullscreen(focusChange: .follow)
        ws.focus(.right)
        let frames = ws.layout().frames
        #expect(frames[3] == ws.stripArea)
        #expect(frames[2]!.width == 500 && !ws.isInView(2), "back to its width, off screen")
    }

    @Test func `With keep every fullscreen column is as wide as the screen`() {
        var ws = fullscreen(focusChange: .keep)
        ws.focus(.right)
        #expect(ws.layout().frames[3] == ws.stripArea)
        ws.focus(.left)
        #expect(ws.layout().frames[2] == ws.stripArea)
        #expect(ws.stripFrames[3]!.width == ws.stripArea.width)
    }

    @Test func `A new window with follow opens fullscreen`() {
        var ws = fullscreen(focusChange: .follow)
        ws.insert(9)
        #expect(ws.windows == [1, 2, 9, 3, 4])
        #expect(ws.layout().frames[9] == ws.stripArea)
        #expect(!ws.isInView(2))
    }

    @Test func `The other windows of the column stay their width behind it`() {
        var ws = strip(4)
        ws.focus(2)
        ws.join(.right)
        let before = ws.layout().frames[3]!
        ws.toggleFullscreen()
        let frames = ws.layout().frames
        #expect(frames[2] == ws.stripArea)
        #expect(frames[3]!.size == before.size)
        #expect(frames[3]!.minX == ws.stripArea.minX)
    }

    @Test func `At a wall the pushed neighbours keep their width behind it and their shadows inside it`() {
        let ws = fullscreen(walls: [.left, .right])
        let frames = ws.layout().frames
        #expect(frames[2] == ws.bounds)
        for id: WindowID in [1, 3, 4] {
            #expect(frames[id]!.width == 525, "their width without gutters")
            #expect(frames[2]!.insetBy(dx: reach, dy: reach).contains(frames[id]!), "not as tall as the fullscreen window")
        }
    }

    @Test func `A pushing strip parks frame by frame as the layout does`() {
        for walls: Set<Direction> in [[], [.left], [.left, .right]] {
            let ws = fullscreen(6, walls: walls)
            #expect(ws.placeStrip(ws.stripFrames) == ws.layout().frames, "walls \(walls)")
        }
    }
}

struct ScrollingTuckTests {
    private let tuck = Workspace.tuck

    /// The columns off each edge, nearest the screen first.
    private func parked(_ ws: Workspace) -> (left: [WindowID], right: [WindowID]) {
        let strip = ws.stripFrames
        let left = ws.windows.filter { strip[$0]!.minX < ws.bounds.minX - 1 }
        let right = ws.windows.filter { strip[$0]!.maxX > ws.bounds.maxX + 1 }
        return (left.reversed(), right)
    }

    @Test func `Only the nearest column off each edge peeks, the ones beyond tuck under it`() {
        var ws = strip(8)
        ws.focus(4)
        let frames = ws.layout().frames, (left, right) = parked(ws)
        #expect(left.count >= 2 && right.count >= 2)
        #expect(frames[left[0]]!.maxX == ws.bounds.minX + peek)
        for id in left.dropFirst() { #expect(frames[id]!.maxX == ws.bounds.minX + tuck) }
        #expect(frames[right[0]]!.minX == ws.bounds.maxX - peek)
        for id in right.dropFirst() { #expect(frames[id]!.minX == ws.bounds.maxX - tuck) }
        let order = ws.layout().order
        for id in left.dropFirst() { #expect(order.firstIndex(of: left[0])! < order.firstIndex(of: id)!, "under the peek") }
    }

    @Test func `Scrolling moves every window continuously, a tucked one always under the column in front`() {
        for gaps in [Gaps.zero, Gaps(all: 8)] {
            var ws = strip(9, gaps: gaps)
            ws.focus(1)
            let strip = ws.stripFrames
            var last: [WindowID: CGRect]?
            for dx in stride(from: 0, through: -4000, by: -1) {
                let placed = ws.placeStrip(strip.mapValues { $0.offsetBy(dx: CGFloat(dx), dy: 0) })
                for id in ws.windows {
                    let frame = placed[id]!
                    #expect(frame.maxX - ws.bounds.minX >= 1 && ws.bounds.maxX - frame.minX >= 1, "never wholly off")
                    if let before = last?[id] { #expect(abs(frame.minX - before.minX) <= 1, "\(id) jumped at \(dx)") }
                }
                // Off the left edge, a column showing less than the peek has its edge, and so its shadow, under a
                // column nearer the screen, which stacks above it.
                for (i, behind) in ws.windows.enumerated() {
                    let shows = placed[behind]!.maxX - ws.bounds.minX
                    guard placed[behind]!.minX < ws.bounds.minX, shows < peek else { continue }
                    let front = ws.windows[(i + 1)...].map { placed[$0]!.maxX }.max()!
                    #expect(front - placed[behind]!.maxX >= 22.5, "\(behind) at \(dx)")
                }
                for (i, behind) in ws.windows.enumerated() {
                    let shows = ws.bounds.maxX - placed[behind]!.minX
                    guard placed[behind]!.maxX > ws.bounds.maxX, shows < peek else { continue }
                    let front = ws.windows[..<i].map { placed[$0]!.minX }.min()!
                    #expect(placed[behind]!.minX - front >= 22.5, "\(behind) at \(dx)")
                }
                last = placed
            }
        }
    }

    @Test func `On a long glide a column never tucks under one stacked below it`() {
        for gaps in [Gaps.zero, Gaps(all: 8)] {
            var ws = strip(9, gaps: gaps)
            ws.focus(1)
            let start = ws.stripFrames
            ws.focus(9)
            let end = ws.stripFrames, rank = Dictionary(uniqueKeysWithValues: ws.layout().order.enumerated().map { ($1, $0) })
            for step in 0...200 {
                let t = CGFloat(step) / 200
                let frames = start.mapValues { $0 }.merging(end) { a, b in a.offsetBy(dx: ((b.minX - a.minX) * t).rounded(), dy: 0) }
                let placed = ws.placeStrip(frames)
                for (i, behind) in ws.windows.enumerated() {
                    let left = placed[behind]!.minX < ws.bounds.minX, right = placed[behind]!.maxX > ws.bounds.maxX
                    let shows = left ? placed[behind]!.maxX - ws.bounds.minX : ws.bounds.maxX - placed[behind]!.minX
                    guard left || right, shows < peek else { continue }
                    let nearer = left ? Array(ws.windows[(i + 1)...]) : Array(ws.windows[..<i])
                    let covers = nearer.contains { id in
                        rank[id]! < rank[behind]! && (left ? placed[id]!.maxX - placed[behind]!.maxX : placed[behind]!.minX - placed[id]!.minX) >= 22
                    }
                    #expect(covers, "\(behind) at \(t) has nothing stacked above it covering its edge")
                }
            }
        }
    }

    @Test func `A window that would not stay tucked parks at the peek`() {
        var ws = strip(8)
        ws.focus(4)
        let far = parked(ws).left[1]
        ws.untuckable = [far]
        #expect(ws.layout().frames[far]!.maxX == ws.bounds.minX + peek)
    }

    @Test func `Off the left edge a window is placed by the width it came out at`() {
        var ws = strip(8)
        ws.focus(4)
        let far = parked(ws).left[1]
        let width = ws.layout().frames[far]!.width
        ws.observedWidths[far] = width - 7
        #expect(ws.layout().frames[far]!.minX + width - 7 == ws.bounds.minX + tuck)
        ws.observedWidths[far] = width - 300
        #expect(ws.layout().frames[far]!.minX + width - Workspace.snapAllowance == ws.bounds.minX + tuck,
                "a width far off is stale, not snapped")
    }

    @Test func `A pushing fullscreen window's outer neighbours tuck`() {
        var ws = strip(6)
        ws.focus(3)
        ws.toggleFullscreen()
        let frames = ws.layout().frames
        #expect(frames[2]!.maxX == ws.bounds.minX + peek)
        #expect(frames[1]!.maxX == ws.bounds.minX + tuck)
        #expect(frames[4]!.minX == ws.bounds.maxX - peek)
        #expect(frames[5]!.minX == ws.bounds.maxX - tuck && frames[6]!.minX == ws.bounds.maxX - tuck)
    }

    @Test func `A pile is put in order under every window of its front column`() {
        var ws = strip(6, gaps: Gaps(all: 8))
        ws.focus(3)
        ws.join(.left)
        #expect(shape(ws.root) == "h[1 v[2 3] 4 5 6]")
        ws.focus(5)
        let layout = ws.layout(), (left, _) = parked(ws)
        #expect(left == [2, 3, 1] || left == [3, 2, 1], "the column of 2 and 3 peeks, 1 tucks under it")
        #expect(layout.frames[1]!.maxX == ws.bounds.minX + Workspace.tuck)
        // The front column's front window is on top of the pile, but 1 is over its other window.
        let front = layout.order.first { [2, 3].contains($0) }!, other: WindowID = front == 2 ? 3 : 2
        let current = layout.order.filter { $0 != 1 && $0 != other } + [1, other]
        let raises = layout.raises(current: current)
        #expect(!raises.isEmpty && raises.allSatisfy { [2, 3].contains($0) })
    }

    @Test func `A window placed by a narrower width is grouped by where it shows`() {
        var ws = strip(6, gaps: Gaps(all: 8))
        ws.focus(4)
        ws.focus(3)
        let (left, _) = parked(ws), lead = left[0], width = ws.layout().frames[lead]!.width
        #expect(left.count >= 2)
        ws.observedWidths[lead] = width - 14
        let layout = ws.layout()
        #expect(layout.frames[lead]!.maxX > layout.frames[3]!.minX, "its written frame reaches past the gap")
        // The column in view is on top, the lead under a tucked window: the lead is raised, nothing in view.
        let current = layout.order.filter { !left.contains($0) } + left.dropFirst() + [lead]
        #expect(layout.raises(current: current) == [lead])
    }

    @Test func `Each edge's pile is put in order on its own, raising only its peek`() {
        var ws = strip(8)
        ws.focus(4)
        let layout = ws.layout(), (left, right) = parked(ws)
        #expect(layout.raises(current: layout.order).isEmpty)
        // The left peek fell under a tucked window; the right pile is fine.
        var current = layout.order.filter { $0 != left[0] }
        current.insert(left[0], at: current.firstIndex(of: left[1])! + 1)
        #expect(layout.raises(current: current) == [left[0]])
        // Both piles out of order: each raises its own peek, even with the front window on top.
        current = layout.order.filter { $0 != left[0] && $0 != right[0] } + [left[0], right[0]]
        #expect(Set(layout.raises(current: current)) == [left[0], right[0]])
    }
}

struct ScrollingFreeScrollTests {
    @Test func `Fingers scroll the strip freely, no further than its ends`() {
        var ws = strip(4)
        #expect(lefts(ws) == [-975, -475, 25, 525])
        #expect(ws.beginFreeScroll() == true)
        #expect(ws.isScrollingFreely)
        #expect(lefts(ws) == [-975, -475, 25, 525], "from where it showed")
        #expect(ws.scrollFreely(by: -300) == -300)
        #expect(lefts(ws) == [-675, -175, 325, 825], "the focused column half off, not scrolled back to")
        #expect(ws.focused == 4 && ws.layout().order.first == 4, "focus stays put till the fingers let go")
        #expect(ws.scrollFreely(by: -2000) == -650)
        #expect(lefts(ws) == [-25, 475, 975, 1475], "the first column reaching into the gutter, as at the start")
        #expect(ws.scrollFreely(by: 5000) == 950)
        #expect(lefts(ws) == [-975, -475, 25, 525])
    }

    @Test func `Let go, the column showing nearest the middle takes focus, scrolled as little as shows it`() {
        var ws = strip(4, width: 0.8)
        #expect(lefts(ws) == [-2175, -1375, -575, 225])
        ws.beginFreeScroll()
        ws.scrollFreely(by: -500)
        #expect(lefts(ws) == [-1675, -875, -75, 725])
        #expect(ws.endFreeScroll() == 3)
        #expect(ws.focused == 3 && !ws.isScrollingFreely)
        #expect(lefts(ws) == [-1600, -800, 0, 800])
    }

    @Test func `Let go at an end of the strip, the column there takes focus`() {
        var ws = strip(4)
        ws.beginFreeScroll()
        ws.scrollFreely(by: -2000)
        #expect(lefts(ws) == [-25, 475, 975, 1475])
        #expect(ws.endFreeScroll() == 1, "the second shows nearer the middle, but the middle cannot reach the first")
        #expect(lefts(ws) == [-25, 475, 975, 1475])
        var near = strip(4)
        near.beginFreeScroll()
        near.scrollFreely(by: -900)
        #expect(near.endFreeScroll() == 2, "short of the start, the column nearest the middle")
    }

    @Test func `A fling carries the strip on before it lets go, no further than its ends`() {
        var ws = strip(8)
        ws.beginFreeScroll()
        ws.scrollFreely(by: -100)
        #expect(ws.endFreeScroll(momentum: -1000) == 5)
        #expect(lefts(ws) == [-1875, -1375, -875, -375, 125, 625, 1125, 1625])
        var far = strip(8)
        far.beginFreeScroll()
        #expect(far.endFreeScroll(momentum: -10_000) == 1)
        #expect(lefts(far)[0] == -25)
    }

    @Test func `Centring, the strip scrolls freely as far as centres an end column, and let go centres the column`() {
        var ws = strip(4)
        ws.columnCentring = .always
        ws.focus(4)
        #expect(lefts(ws) == [-1250, -750, -250, 250])
        ws.beginFreeScroll()
        #expect(ws.scrollFreely(by: -3000) == -1500)
        #expect(lefts(ws) == [250, 750, 1250, 1750], "the screen bare left of the first column")
        ws.scrollFreely(by: 700)
        #expect(lefts(ws) == [-450, 50, 550, 1050])
        #expect(ws.endFreeScroll() == 2)
        #expect(lefts(ws) == [-250, 250, 750, 1250])
    }

    @Test func `Always fill, the strip scrolls freely only as far as takes an end column to the edge`() {
        var ws = strip(4)
        ws.columnCentring = .alwaysFill
        ws.focus(4)
        ws.beginFreeScroll()
        #expect(ws.scrollFreely(by: -3000) == -950)
        #expect(lefts(ws) == [-25, 475, 975, 1475])
    }

    @Test func `On overflow, let go, a column that did not all show is centred, one that did left where it is`() {
        var ws = strip(4, width: 0.8)
        ws.columnCentring = .onOverflow
        ws.beginFreeScroll()
        ws.scrollFreely(by: -500)
        #expect(ws.endFreeScroll() == 3)
        #expect(lefts(ws) == [-1500, -700, 100, 900], "centred")
        ws.beginFreeScroll()
        ws.scrollFreely(by: 50)
        #expect(ws.endFreeScroll() == 3)
        #expect(lefts(ws) == [-1550, -750, 50, 850], "it all showed, so left where the fingers left it")
    }

    @Test func `Let go on a column of several, its most recently focused window takes focus`() {
        var ws = strip(5)
        ws.focus(3)
        ws.join(.left)
        ws.focus(2)
        ws.setMode(.accordion)
        #expect(shape(ws.root) == "h[1 av[2 3] 4 5]")
        ws.focus(5)
        ws.beginFreeScroll()
        ws.scrollFreely(by: -600)
        #expect(ws.endFreeScroll() == 2, "the one the accordion shows on top, not the column's last")
    }

    @Test func `Cancelled, the strip goes back where it showed, focus unchanged`() {
        var ws = strip(5)
        ws.focus(3)
        let before = ws.layout()
        ws.beginFreeScroll()
        ws.scrollFreely(by: 700)
        #expect(ws.layout() != before)
        ws.cancelFreeScroll()
        #expect(!ws.isScrollingFreely)
        #expect(ws.focused == 3)
        #expect(ws.layout() == before)
    }

    @Test func `A focus change while scrolling freely ends it, scrolling to focus as ever`() {
        var ws = strip(5)
        ws.focus(3)
        ws.beginFreeScroll()
        ws.scrollFreely(by: 400)
        ws.insert(9)
        #expect(!ws.isScrollingFreely)
        #expect(ws.isInView(9))
        #expect(ws.endFreeScroll() == nil)
    }

    @Test func `Fullscreen while scrolling freely puts the strip back as it was, nothing focused`() {
        var ws = strip(4)
        ws.focus(2)
        let before = ws.layout()
        ws.beginFreeScroll()
        ws.scrollFreely(by: 300)
        ws.toggleFullscreen()
        #expect(ws.endFreeScroll() == nil)
        #expect(!ws.isScrollingFreely)
        ws.toggleFullscreen()
        #expect(ws.layout() == before)
    }

    @Test func `Fingers that cannot scroll the strip leave it alone`() {
        #expect(!strip(1).canScrollFreely, "a lone column")
        #expect(!strip(2).canScrollFreely, "columns that all fit")
        #expect(!strip(2, width: 0.49).canScrollFreely)
        #expect(!workspace(3).canScrollFreely, "no strip")
        var full = strip(4)
        full.focus(2)
        full.toggleFullscreen()
        #expect(full.beginFreeScroll() == false)
        var kept = strip(4)
        kept.keepsScroll = true
        #expect(!kept.canScrollFreely, "a drop shown holds it")
        var ws = strip(4)
        let before = ws
        #expect(ws.scrollFreely(by: -300) == 0)
        #expect(ws.endFreeScroll() == nil)
        ws.cancelFreeScroll()
        #expect(ws == before)
    }

    @Test func `A strip a click holds still scrolls freely from where it shows, and holds no more`() {
        var ws = strip(4)
        ws.columnCentring = .always
        ws.focus(4)
        ws.focus(3, holdingScroll: true)
        #expect(ws.beginFreeScroll() == true)
        #expect(!ws.holdsScroll)
        #expect(lefts(ws) == [-1250, -750, -250, 250], "where it was pressed, not centred on 3")
    }

    @Test func `Scrolled freely, every window moves continuously and the strip parks as the layout does`() {
        for gaps in [Gaps.zero, Gaps(all: 8)] {
            var ws = strip(9, gaps: gaps)
            ws.focus(1)
            ws.beginFreeScroll()
            var last: [WindowID: CGRect]?
            for _ in 0..<4000 {
                ws.scrollFreely(by: 1)
                let placed = ws.layout().frames
                #expect(ws.placeStrip(ws.stripFrames) == placed)
                for id in ws.windows {
                    if let before = last?[id] { #expect(abs(placed[id]!.minX - before.minX) <= 1, "\(id) jumped") }
                }
                last = placed
            }
        }
    }

    @Test func `At walls nothing scrolled freely leaves the screen`() {
        var ws = strip(6, walls: [.left, .right])
        ws.focus(1)
        ws.beginFreeScroll()
        for _ in 0..<2000 {
            ws.scrollFreely(by: 1)
            for frame in ws.layout().frames.values {
                #expect(frame.minX >= ws.bounds.minX && frame.maxX <= ws.bounds.maxX)
            }
        }
    }

    @Test func `Scrolled freely, no column reaches over to a wall, so none changes width under the fingers`() {
        var ws = strip(3, gaps: Gaps(all: 10), walls: [.left])
        #expect(ws.layout().frames[2] == rect(-15, 10, 520, 580), "at rest it reaches out to the outer gap")
        ws.beginFreeScroll()
        #expect(ws.layout().frames[2] == rect(10, 10, 495, 580), "its own width, the room left bare")
        ws.scrollFreely(by: -40)
        #expect(ws.layout().frames[2] == rect(50, 10, 495, 580))
    }
}
