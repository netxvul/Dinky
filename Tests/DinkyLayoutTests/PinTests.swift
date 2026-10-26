import CoreGraphics
import Testing
@testable import DinkyLayout

/// A scrolling workspace on a 1000 by 600 screen with windows 1...n inserted in order, so n is focused, each column a
/// quarter of the screen wide.
private func strip(_ n: Int, width: Double = 0.25, gaps: Gaps = .zero, walls: Set<Direction> = []) -> Workspace {
    var ws = Workspace(bounds: rect(0, 0, 1000, 600), gaps: gaps, algorithm: .scrolling)
    ws.columnWidth = width
    ws.walls = walls
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// `ws` with window `id`'s column pinned to `side`.
private func pinned(_ ws: Workspace, _ id: WindowID, _ side: PinSide) -> Workspace {
    var ws = ws
    ws.focus(id)
    do { let r = ws.pin(side); #expect(r == .changed) }
    return ws
}

/// The strip's columns as their windows, left to right.
private func columns(_ ws: Workspace) -> [[WindowID]] { ws.root.children.map(\.windows) }

/// Widths of each window as the strip lays it out.
private func widths(_ ws: Workspace) -> [WindowID: CGFloat] { ws.tiledLayout().frames.mapValues(\.width) }

/// Runs `body` and checks no pin mark was dropped for a column moved off its end meanwhile.
private func settling(_ body: () -> Void) {
    let before = Workspace.pinsSettled
    body()
    #expect(Workspace.pinsSettled == before, "a pinned column left its end")
}

struct PinGeometryTests {
    @Test func `A pinned column sits at its side from the outer gap and the band starts a gap past it`() {
        let gaps = Gaps(horizontal: 10, vertical: 10, top: 8, bottom: 8, left: 8, right: 8)
        let ws = pinned(strip(5, gaps: gaps), 1, .left)
        let frames = ws.tiledLayout().frames
        #expect(frames[1]!.minX == 8, "from the outer gap")
        #expect(frames[1]!.width == ((1000 - 16) * 0.25).rounded() - 5, "its share of the inset less half a gap")
        #expect(ws.stripInset.minX == frames[1]!.maxX + 10, "the band a gap past it")
        #expect(columns(ws) == [[1], [2], [3], [4], [5]])
    }

    @Test func `No gutter on a pinned side, the other side keeps its own while the band overflows`() {
        let ws = pinned(strip(6), 1, .left)
        #expect(ws.stripArea.minX == ws.stripInset.minX)
        #expect(ws.stripArea.maxX == ws.stripInset.maxX - Workspace.peek)
        var start = ws
        start.focus(2)
        #expect(start.tiledLayout().frames[2]!.minX == start.stripInset.minX, "the band's first column at its start")
    }

    @Test func `Pinning leaves the other columns' widths alone`() {
        var ws = strip(5)
        ws.focus(3)
        let before = widths(ws)
        let after = widths(pinned(ws, 1, .left))
        for id: WindowID in [2, 3, 4, 5] { #expect(after[id] == before[id]) }
    }

    @Test func `A lone band column fills the band, and columns that fit centre in it`() {
        let lone = pinned(strip(2), 1, .left)
        #expect(lone.tiledLayout().frames[2] == lone.stripInset)
        let fit = pinned(strip(3, width: 0.2), 1, .right)
        let frames = fit.tiledLayout().frames, band = fit.stripInset
        let used = frames[3]!.maxX - frames[2]!.minX
        #expect(abs((frames[2]!.minX - band.minX) - (band.maxX - frames[3]!.maxX)) <= 1, "centred in the band")
        #expect(used < band.width)
    }

    @Test func `Pins come first in the stacking, then the band from its focused column`() {
        var ws = pinned(pinned(strip(5), 1, .left), 5, .right)
        ws.focus(3)
        #expect(Array(ws.tiledLayout().order.prefix(2)) == [1, 5])
        #expect(ws.tiledLayout().order[2] == 3)
    }
}

struct PinScrollTests {
    @Test func `Pinning shows the band whole, the window focus goes back to in view`() {
        var ws = strip(6, width: 0.5)
        ws.focus(4)
        #expect(ws.pin(.left) == .changed)
        let back = try! #require(ws.bandFocus)
        #expect(ws.isInView(back))
        let frame = ws.tiledLayout().frames[back]!
        #expect(frame.minX >= ws.stripInset.minX - 1)
    }

    @Test func `Focusing a pin scrolls nothing`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(6)
        let shown = ws.shownOffset
        ws.focus(1)
        #expect(ws.shownOffset == shown)
        #expect(ws.focused == 1)
    }

    @Test func `Column centring centres within the band`() {
        var ws = pinned(strip(8), 1, .left)
        ws.columnCentring = .always
        ws.focus(5)
        let frame = ws.tiledLayout().frames[5]!, band = ws.stripArea
        #expect(abs(frame.midX - band.midX) <= 1)
    }

    @Test func `Parked columns tuck under the pin on its side, the other side peeks as ever`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(8)
        let frames = ws.layout().frames
        #expect(frames[2]!.maxX == Workspace.tuck && frames[3]!.maxX == Workspace.tuck, "parked past the screen")
        #expect(frames[4]!.maxX <= ws.pinRect(0).maxX, "still sliding, under the pin")
        var other = ws
        other.focus(2)
        let right = other.layout().frames
        #expect(1000 - right[5]!.minX > Workspace.peek, "the nearest on the unpinned side shows more than a sliver")
        #expect(right[8]!.minX == 1000 - Workspace.tuck)
    }

    @Test func `A band window under a pin is out of view, the pin always in it`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(4)
        ws.focus(8)
        #expect(ws.isInView(1))
        #expect(!ws.isInView(2))
        #expect(ws.isInView(8))
    }

    @Test func `Columns around a pin leave out the other pin, and a band column's neighbours stop at the band`() {
        let ws = pinned(pinned(strip(5), 1, .left), 5, .right)
        let around = ws.columns(around: 3)
        #expect(around.left == [[2]] && around.right == [[4]])
        let pin = ws.columns(around: 1)
        #expect(pin.own == [1] && pin.left.isEmpty && pin.right == [[2], [3], [4]])
    }

    @Test func `Fingers scroll the band only and never snap to a pin`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(5)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        ws.scrollFreely(by: -5000)
        let snapped = ws.endFreeScroll()
        #expect(snapped == 2, "the band's first column, not the pin")
    }

    @Test func `Free scrolling from a pin hands focus to the snapped column`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(1)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        ws.scrollFreely(by: 300)
        let snapped = ws.endFreeScroll()
        #expect(snapped != nil && snapped != 1)
        #expect(ws.focused == snapped)
    }
}

struct PinFullscreenTests {
    @Test func `A band column fullscreen fills the band, the pin staying`() {
        var ws = pinned(strip(5), 1, .left)
        ws.focus(3)
        ws.toggleFullscreen()
        let frames = ws.layout().frames
        #expect(frames[3]!.minX >= ws.stripInset.minX - 1)
        #expect(frames[1] == ws.pinRect(0))
    }

    @Test func `A pin fullscreen covers the screen inside the outer gaps`() {
        var ws = pinned(strip(5, gaps: Gaps(horizontal: 10, vertical: 10, top: 8, bottom: 8, left: 8, right: 8)), 1, .left)
        ws.toggleFullscreen()
        #expect(ws.layout().frames[1] == rect(8, 8, 984, 584))
        #expect(ws.layout().order.first == 1)
    }

    @Test func `With a pin, fullscreen does not fill over it`() {
        var ws = pinned(strip(5), 1, .left)
        ws.pushedFullscreenFills = true
        ws.focus(3)
        ws.toggleFullscreen()
        #expect(ws.layout().frames[3]!.minX >= ws.stripInset.minX - 1)
    }
}

struct PinFocusTests {
    @Test func `From the band's first column left is the pin, and from the pin right is back where focus was`() {
        var ws = pinned(strip(6), 1, .left)
        ws.focus(4)
        ws.focus(2)
        do { let r = ws.focus(.left); #expect(r) }
        #expect(ws.focused == 1)
        do { let r = ws.focus(.right); #expect(r) }
        #expect(ws.focused == 2, "the band window focused last")
    }

    @Test func `Outwards from a pin there is nothing`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.focus(.left); #expect(!r) }
        #expect(ws.focused == 1)
    }

    @Test func `With no band window focused yet, inwards from a pin is the band column nearest it`() {
        var ws = pinned(strip(4), 4, .right)
        ws.bandFocus = nil
        ws.focus(4)
        do { let r = ws.focus(.left); #expect(r) }
        #expect(ws.focused == 3)
    }
}

struct PinRoomTests {
    @Test func `A column as wide as the screen does not pin`() {
        var ws = strip(3, width: 1)
        ws.focus(1)
        if case .refused = ws.pin(.left) {}  else { Issue.record("pinned a column leaving the band no room") }
        #expect(ws.pins.isEmpty)
    }

    @Test func `A pin cannot grow past the band's minimum, nor cycle there`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.resizeColumn(by: 600); #expect(!r) }
        #expect(ws.width(ofColumn: 0) == 0.25)
        do { let r = ws.cycleWidth(through: [0.9, 0.5]); #expect(r) }
        #expect(ws.width(ofColumn: 0) == 0.5, "the step too wide passed over")
    }

    @Test func `Pinning is idempotent, toggling unpins`() {
        var ws = pinned(strip(4), 2, .left)
        do { let r = ws.pin(.left); #expect(r == .unchanged) }
        do { let r = ws.pin(.left, toggle: true); #expect(r == .changed) }
        #expect(ws.pins.isEmpty)
        #expect(columns(ws) == [[1], [2], [3], [4]])
    }

    @Test func `A rule's pin takes only a free side`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(3)
        if case .refused = ws.pin(.left, freeSideOnly: true) {} else { Issue.record("took a pinned side") }
        #expect(ws.pins[.left] == 1)
    }
}

struct PinOriginTests {
    @Test func `Unpinned, a column goes back between the columns it was pinned from`() {
        var ws = pinned(strip(5), 3, .right)
        #expect(columns(ws) == [[1], [2], [4], [5], [3]])
        do { let r = ws.unpin(.right); #expect(r == .changed) }
        #expect(columns(ws) == [[1], [2], [3], [4], [5]])
    }

    @Test func `With its neighbours gone, it goes back to the band's end beside where it was pinned`() {
        var ws = pinned(strip(3), 2, .left)
        ws.remove(1)
        ws.remove(3)
        ws.insert(9)
        do { let r = ws.unpin(.left); #expect(r == .changed) }
        #expect(columns(ws) == [[2], [9]])
    }

    @Test func `Pinning a taken side sends the old pin back where it came from`() {
        var ws = pinned(strip(5), 2, .left)
        ws = pinned(ws, 4, .left)
        #expect(columns(ws) == [[4], [1], [2], [3], [5]])
        #expect(ws.pins[.left] == 4)
    }

    @Test func `Pinning the other side's pin moves it across`() {
        var ws = pinned(strip(4), 2, .left)
        do { let r = ws.pin(.right); #expect(r == .changed) }
        #expect(columns(ws) == [[1], [3], [4], [2]])
        #expect(ws.pins == [.right: 2])
        do { let r = ws.unpin(); #expect(r == .changed) }
        #expect(columns(ws) == [[1], [2], [3], [4]])
    }
}

struct PinTreeTests {
    @Test func `A new window opens in the band, right of the band window focused last while a pin has focus`() {
        var ws = pinned(strip(5), 5, .right)
        ws.focus(2)
        ws.focus(5)
        ws.insert(9)
        #expect(columns(ws) == [[1], [2], [9], [3], [4], [5]])
        #expect(ws.pins[.right] == 5)
    }

    @Test func `Closing a focused pin focuses the band window focused last`() {
        var ws = pinned(strip(5), 1, .left)
        ws.focus(3)
        ws.focus(1)
        ws.remove(1)
        #expect(ws.pins.isEmpty)
        #expect(ws.focused == 3)
    }

    @Test func `Closing the band's last column focuses its band neighbour, not the pin`() {
        var ws = pinned(strip(4), 4, .right)
        ws.focus(3)
        ws.remove(3)
        #expect(ws.focused == 2)
    }

    @Test func `A window of a pinned stack closing keeps the column pinned`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.joinInStrip(.left); #expect(r) }
        #expect(columns(ws) == [[1, 2], [3], [4]])
        settling { ws.remove(1) }
        #expect(ws.pins[.left] == 2)
    }

    @Test func `Moves leave pins where they are`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.moveInStrip(.right); #expect(!r) }
        ws.focus(2)
        do { let r = ws.moveInStrip(.left); #expect(!r, "the band's first column does not swap into the pin") }
        settling { do { let r = ws.moveInStrip(.right); #expect(r) } }
        #expect(columns(ws) == [[1], [3], [2], [4]])
    }

    @Test func `A window of a pinned stack moving inwards becomes the band's first column`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(2)
        _ = ws.joinInStrip(.left)
        ws.focus(2)
        settling { do { let r = ws.moveInStrip(.right); #expect(r) } }
        #expect(columns(ws) == [[1], [2], [3], [4]])
        #expect(ws.pins[.left] == 1)
    }

    @Test func `Joining into a pin stacks there at its width, joining out of a lone pin unpins`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(2)
        settling { do { let r = ws.joinInStrip(.left); #expect(r) } }
        #expect(ws.width(ofColumn: 0) == 0.25)
        var lone = pinned(strip(4), 1, .left)
        lone.focus(1)
        do { let r = lone.joinInStrip(.right); #expect(r) }
        #expect(lone.pins.isEmpty)
    }

    @Test func `Swapping onto a pin hands the dropped window its slot`() {
        var ws = pinned(strip(4), 1, .left)
        settling { do { let r = ws.drop(3, onto: 1, .swap); #expect(r) } }
        #expect(columns(ws) == [[3], [2], [1], [4]])
        #expect(ws.pins[.left] == 3)
    }

    @Test func `Dropped beside a pin, a window goes into the band`() {
        var ws = pinned(strip(4), 1, .left)
        settling { do { let r = ws.drop(4, onto: 1, .split(.left)); #expect(r) } }
        #expect(columns(ws).first == [1])
        #expect(ws.pins[.left] == 1)
    }

    @Test func `Flattened, a pinned column stays whole at its end`() {
        var ws = pinned(strip(4), 1, .left)
        ws.focus(2)
        _ = ws.joinInStrip(.left)
        settling { ws.flatten() }
        #expect(columns(ws).first == [1, 2])
        #expect(ws.pins[.left] != nil)
    }

    @Test func `Marks sleep outside the scrolling layout and wake with it`() {
        var ws = pinned(strip(4), 4, .right)
        ws.setAlgorithm(.dwindle(.tiles))
        #expect(ws.pinSide(of: 4) == nil)
        ws.setAlgorithm(.scrolling)
        #expect(ws.pinSide(of: 4) == .right)
        #expect(columns(ws).last == [4])
    }
}

struct PinVisualTests {
    @Test func `The miniature draws a pin in place over the band, band columns under it parked`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(8)
        let mini = Miniature(screen: ws.bounds, height: 60, workspace: ws)
        #expect(mini.tiles.last?.id == 1, "drawn last, over the band")
        #expect(!mini.tiles.map(\.id).contains(2), "under the pin, out of view")
        #expect(mini.parkedLeft >= 1)
    }

    @Test func `A long scroll's shortcut leaves pins where they are`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(2)
        let starts = ws.stripFrames
        ws.focus(8)
        let targets = ws.stripFrames
        if let shortcut = ws.scrollShortcut(from: starts, to: targets) {
            #expect(shortcut.starts[1] == starts[1] && shortcut.targets[1] == targets[1])
        }
        #expect(starts[1] == targets[1], "the pin does not move")
    }
}

struct PinSurvivalTests {
    @Test func `A pin minimized or floated comes back pinned while its side is free`() {
        var ws = pinned(strip(4), 2, .left)
        ws.depart(2)
        #expect(ws.pins.isEmpty && ws.departedPins[.left] == 2)
        ws.arrive(2)
        #expect(ws.pins[.left] == 2)
        #expect(columns(ws).first == [2])
    }

    @Test func `One that comes back to a side another pin took stays in the band`() {
        var ws = pinned(strip(4), 2, .left)
        ws.depart(2)
        ws = pinned(ws, 3, .left)
        ws.arrive(2)
        #expect(ws.pins[.left] == 3)
        #expect(ws.contains(2) && ws.pinSide(of: 2) == nil)
        #expect(ws.departedPins.isEmpty)
    }

    @Test func `Closed, a departed pin is forgotten`() {
        var ws = pinned(strip(4), 2, .left)
        ws.depart(2)
        ws.arrive(2)
        ws.remove(2)
        #expect(ws.pins.isEmpty && ws.departedPins.isEmpty)
    }

    @Test func `On a narrower display, pins that leave the band too little room are let go`() {
        var ws = pinned(pinned(strip(4, width: 0.35), 1, .left), 4, .right)
        ws.bounds = rect(0, 0, 1000, 600)
        ws.minimumSizes[2] = CGSize(width: 500, height: 100)
        ws.fitPins()
        #expect(ws.pins.count < 2)
    }
}

struct FocusPinTests {
    @Test func `focus-pin jumps to a pin without scrolling, and again goes back to the band`() {
        var ws = pinned(strip(8), 1, .left)
        ws.focus(7)
        let shown = ws.shownOffset
        #expect(ws.focusPin(.left) == 1)
        #expect(ws.shownOffset == shown)
        #expect(ws.focusPin(.left) == 7)
        #expect(ws.focusPin(.right) == nil, "nothing pinned right")
    }
}
