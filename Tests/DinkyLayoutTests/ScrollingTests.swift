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

    @Test func `Never scrolls to a clicked column at once, as before`() {
        var held = strip(4), plain = strip(4)
        held.focus(2, holdingScroll: true)
        plain.focus(2)
        #expect(held == plain)
        #expect(!held.holdsScroll)
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
