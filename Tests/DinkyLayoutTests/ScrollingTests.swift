import CoreGraphics
import Testing
@testable import DinkyLayout

/// The gutter parked windows show in, either side of the columns.
private let peek = Workspace.peek

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
        #expect(ws.layout().frames[1] == rect(10, 0, 490, 600))
        #expect(ws.layout().frames[2] == rect(500, 0, 490, 600))
    }

    @Test func `Inner and outer gaps match on both sides`() {
        let ws = strip(2, width: 0.49, gaps: Gaps(all: 10))
        #expect(ws.layout().frames[1] == rect(15, 10, 480, 580))
        #expect(ws.layout().frames[2] == rect(505, 10, 480, 580))
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
        #expect(layout.frames[1]!.minX == -peek)
        #expect(layout.frames[4]!.minX == 500)
        #expect(layout.order == [2, 1, 3, 4])
    }

    @Test func `At a wall scrolled out windows hide wholly behind the column in view nearest it`() {
        var ws = strip(4, gaps: Gaps(all: 10), walls: [.left, .right])
        ws.focus(2)
        var frames = ws.layout().frames
        #expect(frames[2]!.minX == -10)
        #expect(frames[1] == frames[2], "none of it in the outer gap")
        #expect(frames[4] == frames[3])
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
        #expect(frames[1] == frames[2], "not between 2 and 3")
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
        #expect(lefts(ws) == [0, 500])
    }

    @Test func `The strip stays the root with one column left`() {
        var ws = strip(2)
        ws.join(.left)
        #expect(shape(ws.root) == "h[v[1 2]]")
        #expect(ws.layout().frames[1] == rect(-peek, 0, 1000 + 2 * peek, 300))
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
        #expect(ws.tiledLayout().frames[2]!.width == 600)
        #expect(ws.resize(by: 100, along: .vertical) == false, "a lone window has no stack")
        ws.join(.left)
        #expect(ws.resize(by: 60, along: .vertical) == true)
        #expect(ws.tiledLayout().frames[2]!.height == 360)
    }

    @Test func `A lone column cannot be resized out of sight`() {
        var ws = strip(1)
        #expect(ws.resize(by: 100) == false)
        ws.insert(2)
        #expect(ws.tiledLayout().frames[1]!.width == 500)
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
        #expect(lefts(ws) == [0, 500])
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

    @Test func `At a wall the pushed neighbours keep their size behind it`() {
        let ws = fullscreen(walls: [.left, .right])
        let frames = ws.layout().frames
        #expect(frames[2] == ws.bounds)
        for id: WindowID in [1, 3, 4] {
            #expect(frames[id]!.width == 525, "their width without gutters")
            #expect(ws.bounds.contains(frames[id]!))
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
