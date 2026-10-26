import CoreGraphics
import Testing
@testable import DinkyLayout

/// Gaps with an inner gap of 10 and outer gaps of 8 all round.
private let spaced = Gaps(horizontal: 10, vertical: 10, top: 8, bottom: 8, left: 8, right: 8)

/// A scrolling workspace on a 1000 by 600 screen with windows 1...n inserted in order, so n is focused, each column's
/// share `width`, a quarter by default: of the strip's area, which loses its gutters' room once columns overflow.
private func strip(_ n: Int, width: Double = 0.25, gaps: Gaps = .zero, walls: Set<Direction> = []) -> Workspace {
    var ws = Workspace(bounds: rect(0, 0, 1000, 600), gaps: gaps, algorithm: .scrolling)
    ws.columnWidth = width
    ws.walls = walls
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// `ws` with window `id`'s column pinned to `side`.
private func pinned(_ ws: Workspace, _ id: WindowID, _ side: PinSide,
                    sourceLocation: SourceLocation = #_sourceLocation) throws -> Workspace {
    var ws = ws
    ws.focus(id)
    let change = ws.pin(side)
    try #require(change == .changed, sourceLocation: sourceLocation)
    return ws
}

/// The strip's frames, before parking.
private func frames(_ ws: Workspace) -> [WindowID: CGRect] { ws.tiledLayout().frames }

/// Checks each pin mark names a window of its end column, as every edit must leave it, so no settle is needed; and,
/// given `pins`, that they are the marks.
private func marked(_ ws: Workspace, pins: [PinSide: WindowID]? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    if let pins { #expect(ws.pins == pins, sourceLocation: sourceLocation) }
    var settled = ws
    do { let r = settled.settlePins(); #expect(r == 0, "a pinned column left its end", sourceLocation: sourceLocation) }
    for side in ws.pins.keys { #expect(ws.pinnedIndex(side) != nil, sourceLocation: sourceLocation) }
}

struct PinGeometryTests {
    @Test func `A pin sits from the outer gap at its share less half a gap, the band a whole gap past it`() throws {
        var ws = try pinned(strip(5, gaps: spaced), 1, .left)
        #expect(ws.pinRect(0) == rect(8, 8, 241, 584))
        ws.focus(2)
        #expect(frames(ws)[2]!.minX == 259, "8 + 241 + 10")
        #expect(shape(ws.root) == "h[1 2 3 4 5]")
    }

    @Test func `Every band column scrolled to the pin keeps a whole gap from it, the one past it under it`() throws {
        var ws = try pinned(strip(8, gaps: spaced), 1, .left)
        let pin = ws.pinRect(0)
        ws.focus(8)
        ws.focus(4)
        let shown = frames(ws)
        #expect(shown[4]!.minX == pin.maxX + 10, "a middle column scrolled to the band's start")
        #expect(shown[3]!.maxX <= pin.maxX, "its neighbour ends under the pin")
    }

    @Test func `A lone band column and a pushed one keep a whole gap from the pin`() throws {
        let lone = try pinned(strip(2, gaps: spaced), 1, .left)
        #expect(frames(lone)[2]!.minX == lone.pinRect(0).maxX + 10)
        #expect(frames(lone)[2]!.maxX == 992)
        var pushed = try pinned(strip(5, gaps: spaced), 1, .left)
        pushed.focus(3)
        pushed.toggleFullscreen()
        #expect(pushed.layout().frames[3]!.minX == pushed.pinRect(0).maxX + 10)
    }

    @Test func `A right pin with outer and inner gaps`() throws {
        let ws = try pinned(strip(5, gaps: spaced), 5, .right)
        #expect(ws.pinRect(4) == rect(751, 8, 241, 584))
        #expect(ws.columnStart(of: 5) == 751)
    }

    @Test func `With an odd inner gap either pin is exactly one gap from the band`() throws {
        let odd = Gaps(horizontal: 9, vertical: 9, top: 8, bottom: 8, left: 8, right: 8)
        var right = try pinned(strip(5, gaps: odd), 5, .right)
        right.focus(4)
        #expect(right.pinRect(4).minX - frames(right)[4]!.maxX == 9)
        var left = try pinned(strip(5, gaps: odd), 1, .left)
        left.focus(2)
        #expect(frames(left)[2]!.minX - left.pinRect(0).maxX == 9)
    }

    @Test func `At a wall on a pinned side the band's start column does not reach out under the pin`() throws {
        var ws = strip(8, width: 0.5, gaps: spaced, walls: [.left])
        ws.columnWidths[1] = 0.25
        ws = try pinned(ws, 1, .left)
        ws.focus(8)
        ws.focus(4)
        #expect(frames(ws)[4]!.minX == ws.pinRect(0).maxX + 10)
    }

    @Test func `With an odd inner gap a pin's frame is whole points`() throws {
        let odd = Gaps(horizontal: 9, vertical: 9, top: 8, bottom: 8, left: 8, right: 8)
        let ws = try pinned(strip(5, gaps: odd), 1, .left)
        let pin = ws.pinRect(0)
        #expect(pin.minX == pin.minX.rounded() && pin.width == pin.width.rounded())
        #expect(ws.stripInset.minX == ws.stripInset.minX.rounded())
    }

    @Test func `No gutter on a pinned side, the other side keeps its own while the band overflows`() throws {
        let ws = try pinned(strip(6), 1, .left)
        #expect(ws.stripArea.minX == ws.stripInset.minX)
        #expect(ws.stripArea.maxX == ws.stripInset.maxX - Workspace.peek)
    }

    @Test func `Pinning leaves the other columns' widths alone`() throws {
        var ws = strip(5)
        ws.focus(3)
        let before = frames(ws).mapValues(\.width)
        let after = try frames(pinned(ws, 1, .left)).mapValues(\.width)
        for id: WindowID in [2, 3, 4, 5] { #expect(after[id] == before[id]) }
    }

    @Test func `A band column wider than the band is as wide as the band`() throws {
        var ws = try pinned(strip(3, width: 0.25), 1, .left)
        ws.focus(2)
        do { let r = ws.cycleWidth(through: [0.9]); #expect(r) }
        #expect(frames(ws)[2]!.width == ws.stripArea.width)
    }

    @Test func `A lone band column fills the band, and columns that fit centre in it`() throws {
        let lone = try pinned(strip(2), 1, .left)
        #expect(frames(lone)[2] == rect(250, 0, 750, 600))
        let fit = try pinned(strip(3, width: 0.2), 1, .right)
        #expect(frames(fit)[2] == rect(200, 0, 200, 600))
        #expect(frames(fit)[3] == rect(400, 0, 200, 600))
    }

    @Test func `A pinned stack splits its rect at full height`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        #expect(shape(ws.root) == "h[v[1 2] 3 4]")
        let pin = ws.pinRect(0), shown = frames(ws)
        #expect(pin.contains(shown[1]!) && pin.contains(shown[2]!))
        #expect(shown[1]!.minY == 0 && shown[2]!.maxY == 600)
        marked(ws)
    }

    @Test func `Pins come first in the stacking, then the band from its focused column`() throws {
        var ws = try pinned(pinned(strip(5), 1, .left), 5, .right)
        ws.focus(3)
        #expect(ws.tiledLayout().order == [1, 5, 3, 2, 4])
    }

    @Test func `While a pin has focus the band stacks from the band window focused last`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(6)
        ws.focus(1)
        #expect(ws.tiledLayout().order == [1, 6, 5, 7, 4, 8, 3, 2])
    }
}

struct PinScrollTests {
    @Test func `Pinning shows the band whole, the window focus goes back to in view`() throws {
        var ws = strip(6, width: 0.5)
        ws.focus(4)
        do { let r = ws.pin(.left); #expect(r == .changed) }
        let back = try #require(ws.bandFocus)
        #expect(ws.isInView(back))
        #expect(frames(ws)[back]!.minX >= ws.stripInset.minX)
    }

    @Test func `Focusing a pin scrolls nothing`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(6)
        let shown = ws.shownOffset
        ws.focus(1)
        #expect(ws.shownOffset == shown)
    }

    @Test func `Column centring centres within the band`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.columnCentring = .always
        ws.focus(5)
        #expect(abs(frames(ws)[5]!.midX - ws.stripArea.midX) <= 1)
    }

    @Test func `Parked columns tuck under the pin on its side, the other side as without a pin`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(8)
        let left = ws.layout().frames
        #expect(left[2]!.maxX == Workspace.tuck && left[3]!.maxX == Workspace.tuck)
        ws.focus(2)
        let right = ws.layout().frames
        #expect(right[6]!.minX == 987, "behind the nearest, it shows less than a peek")
        #expect(right[8]!.minX == 1000 - Workspace.tuck)
    }

    @Test func `An untuckable window parks at a peek even beside a pin`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.untuckable = [2]
        ws.focus(8)
        #expect(ws.layout().frames[2]!.maxX == Workspace.peek)
    }

    @Test func `At a wall, columns scrolled past a pin hide behind it`() throws {
        var left = try pinned(strip(8, walls: [.left]), 1, .left)
        left.focus(8)
        let pin = left.pinRect(0), hidden = left.layout().frames
        #expect(pin.contains(hidden[2]!) && pin.contains(hidden[3]!))
        var right = try pinned(strip(8, walls: [.right]), 8, .right)
        right.focus(1)
        let rightPin = right.pinRect(7), behind = right.layout().frames
        #expect(rightPin.contains(behind[6]!) && rightPin.contains(behind[7]!))
    }

    @Test func `A band window under a pin is out of view, the pin always in it`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(8)
        ws.focus(4)
        let under = frames(ws)[3]!
        #expect(under.minX >= 0 && under.maxX <= 1000, "on the screen")
        #expect(!ws.isInView(3))
        #expect(ws.isInView(1) && ws.isInView(4))
        var right = try pinned(strip(8), 8, .right)
        right.focus(1)
        right.focus(5)
        #expect(!right.isInView(6) && right.isInView(8))
    }

    @Test func `Columns around a pin leave out the other pin, and a band column's neighbours stop at the band`() throws {
        let ws = try pinned(pinned(strip(5), 1, .left), 5, .right)
        let around = ws.columns(around: 3)
        #expect(around.left == [[2]] && around.right == [[4]])
        let pin = ws.columns(around: 1)
        #expect(pin.own == [1] && pin.left.isEmpty && pin.right == [[2], [3], [4]])
    }

    @Test func `Fingers scroll the band only and never snap to a pin`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(5)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        ws.scrollFreely(by: -5000)
        do { let r = ws.endFreeScroll(); #expect(r == 2) }
    }

    @Test func `Free scrolling from a pin hands focus to the snapped column`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(1)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        ws.scrollFreely(by: 300)
        let snapped = ws.endFreeScroll()
        #expect(snapped != nil && snapped != 1)
        #expect(ws.focused == snapped)
    }

    @Test func `A strip of only pins does not scroll`() throws {
        var ws = strip(2, width: 0.3)
        ws.columnWidths[1] = 0.45
        ws = try pinned(pinned(ws, 1, .left), 2, .right)
        #expect(ws.pinSpan(0) > ws.stripInset.width, "the left pin wider than the band")
        #expect(!ws.canScrollFreely)
    }
}

struct PinFullscreenTests {
    @Test func `A band column fullscreen fills the band, the pin staying`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.focus(3)
        ws.toggleFullscreen()
        let shown = ws.layout().frames
        #expect(shown[3] == rect(250, 0, 725, 600))
        #expect(shown[1] == ws.pinRect(0))
    }

    @Test func `A pin fullscreen covers the screen inside the outer gaps, the band columns' widths left alone`() throws {
        var ws = try pinned(strip(3, gaps: spaced), 1, .left)
        ws.focus(3)
        let before = frames(ws).mapValues(\.width)
        ws.focus(1)
        ws.toggleFullscreen()
        #expect(ws.layout().frames[1] == rect(8, 8, 984, 584))
        #expect(ws.layout().order.first == 1)
        for id: WindowID in [2, 3] { #expect(frames(ws)[id]!.width == before[id]) }
    }

    @Test func `With a pin, fullscreen does not fill over it`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.pushedFullscreenFills = true
        ws.focus(3)
        ws.toggleFullscreen()
        #expect(ws.layout().frames[3] == rect(250, 0, 725, 600))
    }
}

struct PinFocusTests {
    @Test func `From the band's first column left is the pin, and from the pin right is back where focus was`() throws {
        var ws = try pinned(strip(6), 1, .left)
        ws.focus(5)
        ws.focus(1)
        do { let r = ws.focus(.right); #expect(r) }
        #expect(ws.focused == 5, "the band window focused last, not the band's first")
        ws.focus(2)
        do { let r = ws.focus(.left); #expect(r) }
        #expect(ws.focused == 1)
    }

    @Test func `Outwards from a pin there is nothing, or with wrapping the far end`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.focus(.left); #expect(!r) }
        do { let r = ws.focus(.left, wrapping: true); #expect(r) }
        #expect(ws.focused == 4)
    }

    @Test func `With nothing focused in the band yet, inwards from a pin is the band column nearest it`() throws {
        var ws = try pinned(strip(4), 4, .right)
        ws.remove(try #require(ws.bandFocus))
        ws.focus(4)
        do { let r = ws.focus(.left); #expect(r) }
        #expect(ws.focused == 2)
    }

    @Test func `With an empty band, inwards from one pin is the other`() throws {
        var ws = try pinned(pinned(strip(2, width: 0.3), 1, .left), 2, .right)
        ws.focus(1)
        do { let r = ws.focus(.right); #expect(r) }
        #expect(ws.focused == 2)
    }

    @Test func `Within a pinned accordion focus moves between its windows first`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.setLayout(.accordion, .horizontal)
        ws.focus(1)
        do { let r = ws.focus(.right); #expect(r) }
        #expect(ws.focused == 2)
        marked(ws)
    }

    @Test func `focus-pin jumps to a pin without scrolling, and again goes back to the band`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(7)
        let shown = ws.shownOffset
        do { let r = ws.focusPin(.left); #expect(r == 1) }
        #expect(ws.shownOffset == shown)
        do { let r = ws.focusPin(.left); #expect(r == 7) }
        do { let r = ws.focusPin(.right); #expect(r == nil, "nothing pinned right") }
    }
}

struct PinRoomTests {
    @Test func `A column as wide as the screen does not pin`() {
        var ws = strip(3, width: 1)
        ws.focus(1)
        if case .refused = ws.pin(.left) {} else { Issue.record("pinned a column leaving the band no room") }
        #expect(ws.pins.isEmpty)
    }

    @Test func `The band keeps a quarter of the screen`() {
        var ws = strip(3, width: 0.75)
        ws.focus(1)
        do { let r = ws.pin(.left); #expect(r == .changed) }
        var wider = strip(3, width: 0.76)
        wider.focus(1)
        if case .refused = wider.pin(.left) {} else { Issue.record("pinned past a quarter") }
    }

    @Test func `A band window wider than the band does not stop a pin, it hangs past the band under it`() throws {
        var ws = strip(4)
        ws.minimumSizes[3] = CGSize(width: 800, height: 100)
        ws.focus(1)
        #expect(ws.pin(.left) == .changed)
        ws.focus(3)
        let layout = ws.layout()
        #expect(layout.frames[3]!.width >= 800 && layout.frames[3]!.width > ws.stripInset.width)
        #expect(layout.order.first == 1, "the pin stacks in front")
    }

    @Test func `A pin cannot grow past the band's minimum, nor cycle or resize there, but can always shrink`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.resizeColumn(by: 600); #expect(!r) }
        #expect(ws.width(ofColumn: 0) == 0.25)
        do { let r = ws.cycleWidth(through: [0.9, 0.5]); #expect(r) }
        #expect(ws.width(ofColumn: 0) == 0.5, "the step too wide passed over")
        do { let r = ws.resize(1, to: CGSize(width: 900, height: 600)); #expect(!r) }
        #expect(ws.width(ofColumn: 0) == 0.5)
        ws.minimumSizes[3] = CGSize(width: 700, height: 100)
        do { let r = ws.resizeColumn(by: -100); #expect(r, "shrinking gives the band room back") }
    }

    @Test func `With no pins, room is never checked`() {
        var ws = strip(3)
        ws.minimumSizes[2] = CGSize(width: 1100, height: 100)
        ws.focus(3)
        do { let r = ws.resizeColumn(by: 50); #expect(r) }
        do { let r = ws.cycleWidth(through: [0.5]); #expect(r) }
    }

    @Test func `A band column as wide as the band shrinks from the width it shows`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.33), 1, .left), 4, .right)
        ws.focus(2)
        do { let r = ws.cycleWidth(through: [0.49]); #expect(r) }
        let wide = frames(ws)[2]!.width
        do { let r = ws.resizeColumn(by: -50); #expect(r) }
        #expect(frames(ws)[2]!.width < wide)
    }

    @Test func `Balanced, pins keep their widths where the band would lose its room`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.35), 1, .left), 4, .right)
        ws.columnWidth = 0.45
        ws.balanceSizes()
        #expect(ws.width(ofColumn: 0) == 0.35 && ws.width(ofColumn: 3) == 0.35)
        #expect(ws.width(ofColumn: 1) == 0.45)
    }

    @Test func `Pinning is idempotent, toggling unpins`() throws {
        var ws = try pinned(strip(4), 2, .left)
        do { let r = ws.pin(.left); #expect(r == .unchanged) }
        do { let r = ws.pin(.left, toggle: true); #expect(r == .changed) }
        #expect(ws.pins.isEmpty)
        #expect(shape(ws.root) == "h[1 2 3 4]")
    }

    @Test func `A rule's pin takes only a free side, never moves or unpins a pin`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(3)
        if case .refused = ws.pin(.left, freeSideOnly: true) {} else { Issue.record("took a pinned side") }
        do { let r = ws.pin(.right, freeSideOnly: true, window: 1); #expect(r == .unchanged, "not moved across") }
        do { let r = ws.pin(.left, toggle: true, freeSideOnly: true, window: 1); #expect(r == .unchanged, "not toggled off") }
        #expect(ws.pins == [.left: 1])
    }
}

struct PinOriginTests {
    @Test func `Unpinned, a column goes back between the columns it was pinned from`() throws {
        var ws = try pinned(strip(5), 3, .right)
        #expect(shape(ws.root) == "h[1 2 4 5 3]")
        do { let r = ws.unpin(.right); #expect(r == .changed) }
        #expect(shape(ws.root) == "h[1 2 3 4 5]")
    }

    @Test func `With its neighbours gone, it goes back to the band's end beside where it was pinned`() throws {
        var ws = try pinned(strip(3), 2, .left)
        ws.remove(1)
        ws.remove(3)
        ws.insert(9)
        do { let r = ws.unpin(.left); #expect(r == .changed) }
        #expect(shape(ws.root) == "h[2 9]")
    }

    @Test func `A neighbour replaced, as by a tab, still marks where it goes back`() throws {
        var ws = try pinned(strip(5), 3, .right)
        ws.replace(2, with: 9)
        ws.remove(4)
        do { let r = ws.unpin(.right); #expect(r == .changed) }
        #expect(shape(ws.root) == "h[1 9 3 5]")
    }

    @Test func `Pinning a taken side sends the old pin back where it came from`() throws {
        let ws = try pinned(pinned(strip(5), 2, .left), 4, .left)
        #expect(shape(ws.root) == "h[4 1 2 3 5]")
        #expect(ws.pins == [.left: 4])
    }

    @Test func `Pinning the other side's pin moves it across`() throws {
        var ws = try pinned(strip(4), 2, .left)
        do { let r = ws.pin(.right); #expect(r == .changed) }
        #expect(shape(ws.root) == "h[1 3 4 2]")
        #expect(ws.pins == [.right: 2])
        do { let r = ws.unpin(); #expect(r == .changed) }
        #expect(shape(ws.root) == "h[1 2 3 4]")
    }
}

struct PinTreeTests {
    @Test func `A new window opens in the band, right of the band window focused last while a pin has focus`() throws {
        var ws = try pinned(strip(5), 5, .right)
        ws.focus(2)
        ws.focus(5)
        ws.insert(9)
        #expect(shape(ws.root) == "h[1 2 9 3 4 5]")
        marked(ws)
    }

    @Test func `Closing a focused pin focuses the band window focused last`() throws {
        var left = try pinned(strip(5), 1, .left)
        left.focus(3)
        left.focus(1)
        left.remove(1)
        #expect(left.pins.isEmpty && left.focused == 3)
        var right = try pinned(strip(5), 5, .right)
        right.focus(2)
        right.focus(5)
        right.remove(5)
        #expect(right.focused == 2)
    }

    @Test func `Closing a focused right pin with no band window focused yet focuses the band column nearest it`() throws {
        var ws = try pinned(strip(4), 4, .right)
        ws.remove(try #require(ws.bandFocus))
        ws.focus(4)
        ws.remove(4)
        #expect(ws.focused == 2)
    }

    @Test func `Closing the band's last column focuses its band neighbour, not the pin`() throws {
        var ws = try pinned(strip(4), 4, .right)
        ws.focus(3)
        ws.remove(3)
        #expect(ws.focused == 2)
    }

    @Test func `A window of a pinned stack closing keeps the column pinned`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.remove(1)
        #expect(ws.pins[.left] == 2)
        marked(ws)
    }

    @Test func `Moves leave pins where they are`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.move(.right); #expect(!r) }
        ws.focus(2)
        do { let r = ws.move(.left); #expect(!r, "the band's first column does not swap into the pin") }
        do { let r = ws.move(.right); #expect(r) }
        #expect(shape(ws.root) == "h[1 3 2 4]")
        marked(ws, pins: [.left: 1])
    }

    @Test func `A window of a pinned stack moving inwards becomes the band's first column`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.focus(2)
        do { let r = ws.move(.right); #expect(r) }
        #expect(shape(ws.root) == "h[1 2 3 4]")
        #expect(ws.pins[.left] == 1)
        marked(ws)
    }

    @Test func `Joining into a pin stacks there at its width, joining out of a lone pin unpins`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.4]); #expect(r) }
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        #expect(ws.width(ofColumn: 0) == 0.4)
        marked(ws, pins: [.left: 1])
        var lone = try pinned(strip(4), 1, .left)
        lone.focus(1)
        do { let r = lone.join(.right); #expect(r) }
        #expect(lone.pins.isEmpty)
    }

    @Test func `Swapping onto a pin hands the dropped window its slot and the pin's width`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.4]); #expect(r) }
        do { let r = ws.drop(3, onto: 1, .swap); #expect(r) }
        #expect(shape(ws.root) == "h[3 2 1 4]")
        #expect(ws.pins == [.left: 3])
        #expect(ws.width(ofColumn: 0) == 0.4 && ws.width(ofColumn: 2) == 0.25)
        #expect(ws.bandFocus.map { ws.pinSide(of: $0) == nil } ?? true)
        marked(ws, pins: [.left: 3])
    }

    @Test func `Swapping within a pinned stack keeps the pin's width`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.4]); #expect(r) }
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        do { let r = ws.drop(2, onto: 1, .swap); #expect(r) }
        #expect(ws.width(ofColumn: 0) == 0.4)
        marked(ws, pins: [.left: 2])
    }

    @Test func `Swapping a band window onto one joined into a pin keeps both widths and the mark`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.4]); #expect(r) }
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        do { let r = ws.drop(3, onto: 2, .swap); #expect(r) }
        #expect(ws.width(ofColumn: 0) == 0.4 && ws.width(ofColumn: 1) == 0.25)
        marked(ws, pins: [.left: 1])
    }

    @Test func `Dropped beside a pin, a window goes into the band`() throws {
        var ws = try pinned(strip(4), 1, .left)
        do { let r = ws.drop(4, onto: 1, .split(.left)); #expect(r) }
        #expect(shape(ws.root) == "h[1 4 2 3]")
        #expect(ws.pins[.left] == 1)
        marked(ws)
    }

    @Test func `Flattened, a pinned column stays whole at its end`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.flatten()
        #expect(shape(ws.root).hasPrefix("h[v[1 2]"))
        #expect(ws.pins[.left] != nil)
        marked(ws)
    }

    @Test func `Marks sleep outside the scrolling layout and wake with it, the pin a column of its own`() throws {
        var ws = try pinned(strip(4), 4, .right)
        ws.setAlgorithm(.dwindle(.tiles))
        #expect(ws.pinSide(of: 4) == nil)
        ws.focus(4)
        ws.insert(9)
        try #require(shape(ws.root).hasSuffix("v[4 9]]"), "the last child is 4's and 9's")
        ws.setAlgorithm(.scrolling)
        #expect(ws.pinSide(of: 4) == .right)
        #expect(ws.root.children.last == .window(4))
        #expect(ws.root.path(of: 9).map { ws.bandRange.contains($0[0]) } == true)
    }

    @Test func `A pinned window closed outside the scrolling layout leaves no mark`() throws {
        var ws = try pinned(strip(4), 4, .right)
        ws.setAlgorithm(.dwindle(.tiles))
        ws.remove(4)
        #expect(ws.pins.isEmpty)
        ws.insert(4)
        ws.setAlgorithm(.scrolling)
        #expect(ws.pins.isEmpty, "a new window with the old id is no pin")
    }

    @Test func `Back to scrolling on a narrower display, pins without room are let go`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.35), 1, .left), 4, .right)
        ws.setAlgorithm(.dwindle(.tiles))
        ws.minimumSizes[1] = CGSize(width: 450, height: 100)
        ws.setAlgorithm(.scrolling)
        #expect(ws.pinnedWindows.count < 2)
    }

    @Test func `Settling drops a mark off its end and a column marked for both sides keeps the left`() {
        var ws = strip(3)
        ws.pins = [.left: 2]
        do { let r = ws.settlePins(); #expect(r == 1) }
        #expect(ws.pins.isEmpty)
        var lone = strip(1)
        lone.pins = [.left: 1, .right: 1]
        lone.settlePins()
        #expect(lone.pins == [.left: 1])
    }
}

struct PinVisualTests {
    @Test func `The miniature draws a pin in place over the band, band columns under it parked`() throws {
        var ws = try pinned(strip(8), 1, .left)
        ws.focus(8)
        let mini = Miniature(screen: ws.bounds, height: 60, workspace: ws)
        #expect(mini.tiles.last?.id == 1, "drawn last, over the band")
        #expect(!mini.tiles.map(\.id).contains(2), "under the pin, out of view")
        #expect(mini.parkedLeft >= 1)
    }

    @Test func `The miniature parks a column under a pin by the band's middle, not the screen's`() throws {
        var left = strip(6, width: 0.3)
        left.columnWidths[1] = 0.5
        left = try pinned(left, 1, .left)
        left.focus(2)
        left.focus(3)
        let under = try #require(left.stripFrames[2])
        try #require(!left.isInView(2) && under.midX > left.bounds.midX && under.midX < left.bandRect.midX)
        let mini = Miniature(screen: left.bounds, height: 60, workspace: left)
        #expect(mini.parkedLeft == 1 && mini.parkedRight == 3)
        var right = strip(6, width: 0.3)
        right.columnWidths[6] = 0.5
        right = try pinned(right, 6, .right)
        right.focus(5)
        right.focus(4)
        let over = try #require(right.stripFrames[5])
        try #require(!right.isInView(5) && over.midX < right.bounds.midX && over.midX > right.bandRect.midX)
        let mirror = Miniature(screen: right.bounds, height: 60, workspace: right)
        #expect(mirror.parkedRight == 1 && mirror.parkedLeft == 3)
    }

    @Test func `A long scroll's shortcut leaves pins where they are`() throws {
        var ws = try pinned(strip(20), 1, .left)
        ws.focus(2)
        let starts = ws.stripFrames
        ws.focus(20)
        let targets = ws.stripFrames
        let shortcut = try #require(ws.scrollShortcut(from: starts, to: targets))
        #expect(shortcut.starts[1] == starts[1] && shortcut.targets[1] == targets[1])
    }
}

struct PinSurvivalTests {
    @Test func `A pin minimized or floated comes back pinned while its side is free`() throws {
        var ws = try pinned(strip(4), 2, .left)
        ws.depart(2)
        #expect(ws.pins.isEmpty && ws.departedPins[.left] == 2)
        ws.arrive(2)
        #expect(ws.pins[.left] == 2)
        #expect(ws.root.children.first == .window(2))
    }

    @Test func `It comes back at the width it had, so it fits beside the other pin`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.4]); #expect(r) }
        ws = try pinned(ws, 4, .right)
        ws.depart(1)
        ws.arrive(1)
        #expect(ws.pins[.left] == 1)
        #expect(ws.width(ofColumn: 0) == 0.4)
    }

    @Test func `One that comes back to a side another pin took stays in the band`() throws {
        var ws = try pinned(strip(4), 2, .left)
        ws.depart(2)
        ws = try pinned(ws, 3, .left)
        ws.arrive(2)
        #expect(ws.pins[.left] == 3)
        #expect(ws.contains(2) && ws.pinSide(of: 2) == nil)
        #expect(ws.departedPins.isEmpty)
    }

    @Test func `One that comes back while the strip is another layout is pinned as it scrolls again`() throws {
        var ws = try pinned(strip(4), 2, .left)
        ws.depart(2)
        ws.setAlgorithm(.dwindle(.tiles))
        ws.arrive(2)
        ws.setAlgorithm(.scrolling)
        #expect(ws.pins[.left] == 2)
    }

    @Test func `Closed, a departed pin is forgotten`() throws {
        var ws = try pinned(strip(4), 2, .left)
        ws.depart(2)
        ws.forgetPinned(2)
        #expect(ws.departedPins.isEmpty)
        ws.arrive(2)
        #expect(ws.pins.isEmpty)
    }

    @Test func `On a narrower display, pins that leave the band too little room are let go`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.35), 1, .left), 4, .right)
        ws.minimumSizes[1] = CGSize(width: 450, height: 100)
        ws.fitPins()
        #expect(ws.pinnedWindows.count < 2)
    }

    @Test func `Resizing a lone band column to a size changes nothing`() throws {
        var ws = try pinned(strip(2), 1, .left)
        do { let r = ws.resize(2, to: CGSize(width: 400, height: 600)); #expect(!r) }
    }
}

struct PinFitTests {
    @Test func `A pin's minimum learned after pinning narrows the pin pinned last, never unpinning it`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.3), 1, .left), 4, .right)
        ws.minimumSizes[1] = CGSize(width: 500, height: 100)
        try #require(!ws.bandHasRoom)
        ws.fitBand()
        #expect(ws.pins.count == 2)
        #expect(ws.width(ofColumn: 3) < 0.3, "the right pin, pinned last, narrowed")
        #expect(ws.bandHasRoom)
    }

    @Test func `A band window wider than the band narrows no pin`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.3), 1, .left), 4, .right)
        ws.minimumSizes[2] = CGSize(width: 600, height: 100)
        let before = ws
        ws.fitBand()
        #expect(ws == before)
    }

    @Test func `With nothing pinned, fitting the band changes nothing`() {
        var ws = strip(4)
        ws.minimumSizes[2] = CGSize(width: 1500, height: 100)
        let before = ws
        ws.fitBand()
        #expect(ws == before)
    }

    @Test func `Minimized and restored, a pin still unpins to where it was first pinned from`() throws {
        var ws = try pinned(strip(5), 2, .left)
        ws.depart(2)
        ws.focus(4)
        ws.arrive(2)
        #expect(ws.pins[.left] == 2)
        #expect(ws.unpin(.left) == .changed)
        #expect(shape(ws.root) == "h[1 2 3 4 5]")
    }
}

struct PinSwapRoomTests {
    @Test func `With the band already short, a swap within the band still goes through`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.minimumSizes[1] = CGSize(width: 800, height: 100)
        try #require(!ws.bandHasRoom)
        do { let r = ws.drop(4, onto: 3, .swap); #expect(r) }
        #expect(ws.pins == [.left: 1])
    }

    @Test func `A swap into a pin's slot that leaves the band less room is refused`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        let before = ws
        do { let r = ws.drop(2, onto: 1, .swap); #expect(!r) }
        #expect(ws == before)
    }

    @Test func `A swap from another Space into a pin's slot that leaves the band short is refused`() throws {
        var ws = try pinned(strip(4), 1, .left)
        var source = Workspace(bounds: rect(0, 0, 1000, 600), gaps: .zero, algorithm: .scrolling)
        source.insert(9)
        source.minimumSizes[9] = CGSize(width: 900, height: 100)
        do { let r = ws.receive(9, from: &source, onto: 1, .swap); #expect(!r) }
        #expect(ws.pins == [.left: 1] && ws.contains(1) && source.contains(9))
    }
}

struct PinDormantTests {
    @Test func `Minimized outside the scrolling layout, a pin is pinned again as it scrolls`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.4]); #expect(r) }
        ws.setAlgorithm(.dwindle(.tiles))
        ws.depart(1)
        #expect(ws.pins.isEmpty && ws.departedPins[.left] == 1)
        ws.arrive(1)
        ws.setAlgorithm(.scrolling)
        #expect(ws.pins[.left] == 1)
        #expect(ws.width(ofColumn: 0) == 0.4)
    }

    @Test func `Back outside the scrolling layout, a pin keeps its width and the other pin stays`() throws {
        var ws = try pinned(strip(4, width: 0.4), 1, .left)
        ws.focus(1)
        do { let r = ws.cycleWidth(through: [0.3]); #expect(r) }
        ws = try pinned(ws, 4, .right)
        try #require(ws.bandHasRoom)
        ws.depart(1)
        ws.setAlgorithm(.dwindle(.tiles))
        ws.arrive(1)
        ws.setAlgorithm(.scrolling)
        #expect(ws.pins == [.left: 1, .right: 4])
        #expect(ws.width(ofColumn: 0) == 0.3, "at the default 0.4 the band would be short and a pin let go")
    }

    @Test func `Fitting pins lets go of the one pinned last first`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.35), 4, .right), 1, .left)
        ws.minimumSizes[4] = CGSize(width: 450, height: 100)
        ws.fitPins()
        #expect(ws.pins == [.right: 4])
    }
}

struct PinRaiseTests {
    /// Each window of `ws` shown where its layout has it, front to back as the layout stacks them, apps by `pids`,
    /// with `over` put in front of all.
    private func stack(_ ws: Workspace, pids: [WindowID: Int32], over: [StackedWindow] = []) -> [StackedWindow] {
        let layout = ws.layout()
        return over + layout.order.map { StackedWindow(id: $0, layer: 0, frame: layout.frames[$0]!, pid: pids[$0] ?? 0) }
    }

    @Test func `A band window in front of a pin where they overlap has the pin raised`() throws {
        let ws = try pinned(strip(4), 1, .left)
        let band = StackedWindow(id: 2, layer: 0, frame: rect(100, 0, 300, 600), pid: 2)
        #expect(ws.pinsToRaise(stack: stack(ws, pids: [1: 1, 2: 2]).filter { $0.id != 2 }.prepending(band), candidates: []) == [1])
    }

    @Test func `The focused window of the pin's own app does not count, another app's does`() throws {
        let ws = try pinned(strip(4), 1, .left)
        let band = StackedWindow(id: 2, layer: 0, frame: rect(100, 0, 300, 600), pid: 1)
        let same = stack(ws, pids: [1: 1]).filter { $0.id != 2 }.prepending(band)
        #expect(ws.pinsToRaise(stack: same, candidates: [2]).isEmpty, "raised after the pin, it would cover it again")
        var other = band
        other.pid = 7
        let different = stack(ws, pids: [1: 1]).filter { $0.id != 2 }.prepending(other)
        #expect(ws.pinsToRaise(stack: different, candidates: [2]) == [1], "a Dia window under a Terminal pin")
    }

    @Test func `A pinned stack is raised whole, unless a window outside the tree is in use over any of it`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.focus(3)
        let layout = ws.layout()
        let lower = layout.frames[2]!
        let band = StackedWindow(id: 3, layer: 0, frame: lower.insetBy(dx: 10, dy: 10), pid: 3)
        let base = stack(ws, pids: [:]).filter { $0.id != 3 }
        #expect(Set(ws.pinsToRaise(stack: base.prepending(band), candidates: [])) == [1, 2], "the whole column")
        let floating = StackedWindow(id: 50, layer: 0, frame: layout.frames[1]!.insetBy(dx: 10, dy: 10), pid: 50)
        #expect(ws.pinsToRaise(stack: [floating, band] + base, candidates: []).isEmpty)
    }

    @Test func `Windows of an app beyond reach cover no pin, others still do`() throws {
        let ws = try pinned(strip(4), 1, .left)
        let band = StackedWindow(id: 2, layer: 0, frame: rect(100, 0, 300, 600), pid: 7)
        let shown = stack(ws, pids: [1: 1]).filter { $0.id != 2 }.prepending(band)
        #expect(ws.pinsToRaise(stack: shown, candidates: [], takingHold: true, beyondReach: [7]).isEmpty)
        #expect(ws.pinsToRaise(stack: shown, candidates: [], takingHold: true, beyondReach: [8]) == [1])
        let covering = StackedWindow(id: 3, layer: 0, frame: rect(100, 0, 300, 600), pid: 8)
        let base = stack(ws, pids: [1: 1]).filter { $0.id != 2 && $0.id != 3 }
        #expect(ws.pinsToRaise(stack: [band, covering] + base, candidates: [], beyondReach: [7]) == [1])
        let floating = StackedWindow(id: 50, layer: 0, frame: rect(10, 10, 100, 100), pid: 7)
        #expect(ws.pinsToRaise(stack: [floating, band, covering] + base, candidates: [], beyondReach: [7]).isEmpty,
                "a window of the front app outside the tree over the pin is in use")
    }

    @Test func `A pin's own app's window counts though that app is beyond reach`() throws {
        let ws = try pinned(strip(4), 1, .left)
        let layout = ws.layout()
        let pin = StackedWindow(id: 1, layer: 0, frame: layout.frames[1]!, pid: 7)
        let sliding = StackedWindow(id: 3, layer: 0, frame: rect(100, 0, 300, 600), pid: 7)
        #expect(ws.pinsToRaise(stack: [sliding, pin], candidates: [2], beyondReach: [7]) == [1])
    }

    @Test func `A sweep under one pin raises that pin only`() throws {
        var ws = try pinned(pinned(strip(5, width: 0.2), 1, .left), 5, .right)
        ws.focus(3)
        let shown = stack(ws, pids: [:])
        let raised = ws.pinsToRaise(stack: shown.filter { $0.id != 3 } .prepending(shown.first { $0.id == 3 }!),
                                    candidates: [], sweeping: [5: [3]])
        #expect(raised == [5])
    }
}

struct PinCleanupTests {
    @Test func `A band left short narrows a pin, never widening one already narrower than its floor`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.3), 1, .left), 4, .right)
        ws.focus(4)
        do { let r = ws.cycleWidth(through: [0.15]); #expect(r) }
        ws.minimumSizes[4] = CGSize(width: 300, height: 100)
        ws.minimumSizes[1] = CGSize(width: 650, height: 100)
        try #require(!ws.bandHasRoom)
        ws.fitBand()
        #expect(ws.width(ofColumn: 3) <= 0.15, "never wider than it was")
    }

    @Test func `A departed pin forgets a neighbour that closed, and follows one replaced by a tab`() throws {
        var ws = try pinned(strip(5), 3, .left)
        ws.depart(3)
        let origin = try #require(ws.departedOrigins[3])
        #expect(origin.before == 2 && origin.after == 4)
        ws.remove(2)
        ws.replace(4, with: 9)
        #expect(ws.departedOrigins[3]?.before == nil)
        #expect(ws.departedOrigins[3]?.after == 9)
    }
}

private extension Array {
    func prepending(_ element: Element) -> [Element] { [element] + self }
}

struct PinWideWindowTests {
    @Test func `A focused band window wider than the band shows from the band's start, the rest under a right pin`() throws {
        var ws = try pinned(strip(5), 5, .right)
        ws.minimumSizes[4] = CGSize(width: 900, height: 100)
        ws.focus(1)
        ws.focus(4)
        let frame = ws.layout().frames[4]!
        #expect(frame.minX == ws.stripArea.minX, "its title bar at the band's start, past the parked columns' peek")
        #expect(frame.maxX > ws.pinRect(4).minX, "the rest under the pin")
        #expect(ws.layout().order.first == 5, "the pin in front")
    }

    @Test func `With a left pin it shows from the band's start too, the rest past the screen's edge`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.minimumSizes[3] = CGSize(width: 900, height: 100)
        ws.focus(5)
        ws.focus(3)
        #expect(ws.layout().frames[3]!.minX == ws.stripArea.minX)
    }

    @Test func `Without a pin a column wider than the screen is still centred`() {
        var ws = strip(4)
        ws.minimumSizes[2] = CGSize(width: 1200, height: 100)
        ws.focus(2)
        let frame = ws.tiledLayout().frames[2]!
        #expect(abs(frame.midX - ws.stripArea.midX) <= 1)
    }
}

struct PinRingTests {
    @Test func `A lone pin and each window of a pinned stack get a ring, the band none`() throws {
        let lone = try pinned(strip(4), 1, .left)
        #expect(lone.ringedPins == [1])
        var stack = try pinned(strip(4), 1, .left)
        stack.focus(2)
        do { let r = stack.join(.left); #expect(r) }
        #expect(Set(stack.ringedPins) == [1, 2])
        #expect(strip(4).ringedPins.isEmpty)
    }

    @Test func `A pinned accordion rings only the window in front`() throws {
        var ws = try pinned(strip(4), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.setLayout(.accordion, nil)
        ws.focus(2)
        #expect(ws.ringedPins == [2])
        ws.focus(1)
        #expect(ws.ringedPins == [1])
    }

    @Test func `Both sides' pins get rings, none outside the scrolling layout`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.3), 1, .left), 4, .right)
        #expect(Set(ws.ringedPins) == [1, 4])
        ws.setAlgorithm(.dwindle(.tiles))
        #expect(ws.ringedPins.isEmpty)
    }

    @Test func `A window fullscreen over the strip hides the rings, a pinned one keeps its own`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.fullscreenPushesStrip = false
        ws.focus(3)
        ws.toggleFullscreen()
        #expect(ws.ringedPins.isEmpty)
        ws.toggleFullscreen()
        ws.focus(1)
        ws.toggleFullscreen()
        #expect(ws.ringedPins == [1])
    }
}

struct PinReviewTests {
    @Test func `A focused band window wider than the band at a wall hangs under the pin, not hidden behind it`() throws {
        var ws = try pinned(strip(4, walls: [.right]), 1, .left)
        ws.minimumSizes[3] = CGSize(width: 800, height: 100)
        ws.focus(3)
        let frame = try #require(ws.layout().frames[3])
        #expect(frame.maxX <= ws.bounds.maxX)
        #expect(frame.intersects(ws.bandRect))
        var mirror = try pinned(strip(4, walls: [.left]), 4, .right)
        mirror.minimumSizes[2] = CGSize(width: 800, height: 100)
        mirror.focus(2)
        let other = try #require(mirror.layout().frames[2])
        #expect(other.minX >= mirror.bounds.minX)
        #expect(other.intersects(mirror.bandRect))
    }

    @Test func `A lone band column beside a pin keeps its minimum width, ending at the wall`() throws {
        var ws = try pinned(strip(2, walls: [.right]), 1, .left)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        let frame = try #require(ws.layout().frames[2])
        #expect(frame.width >= 900)
        #expect(frame.maxX <= ws.bounds.maxX)
    }

    @Test func `With the band short through a pin's own minimum, a pin can shrink but not grow`() throws {
        var ws = try pinned(pinned(strip(4, width: 0.3), 1, .left), 4, .right)
        ws.minimumSizes[1] = CGSize(width: 500, height: 100)
        try #require(!ws.bandHasRoom)
        ws.focus(4)
        do { let r = ws.resizeColumn(by: -20); #expect(r) }
        #expect(!ws.bandHasRoom)
        do { let r = ws.resizeColumn(by: 20); #expect(!r) }
    }

    @Test func `A swap from a Space whose pin slot would leave its band short is refused, both trees as they were`() throws {
        var ws = strip(4)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        var source = Workspace(bounds: rect(0, 0, 1000, 600), gaps: .zero, algorithm: .scrolling)
        for id: WindowID in [9, 10, 11] { source.insert(id) }
        source.focus(9)
        try #require(source.pin(.left) == .changed)
        let (before, sourceBefore) = (ws, source)
        do { let r = ws.receive(9, from: &source, onto: 2, .swap); #expect(!r) }
        #expect(ws == before && source == sourceBefore)
    }

    @Test func `While held, a band window ahead of a pin raises it without overlapping, an own-app focused one does not`() throws {
        let ws = try pinned(strip(4), 1, .left)
        let layout = ws.layout()
        let pin = StackedWindow(id: 1, layer: 0, frame: layout.frames[1]!, pid: 1)
        let away = StackedWindow(id: 3, layer: 0, frame: rect(900, 0, 50, 600), pid: 3)
        #expect(ws.pinsToRaise(stack: [away, pin], candidates: [], takingHold: true) == [1])
        #expect(ws.pinsToRaise(stack: [away, pin], candidates: [3], takingHold: true) == [1], "another app's focused window")
        var own = away
        own.pid = 1
        #expect(ws.pinsToRaise(stack: [own, pin], candidates: [3], takingHold: true).isEmpty, "the pin's own app's")
    }
}

struct PinMiniatureWideTests {
    @Test func `The miniature shows a band column wider than the band, clipped to it`() throws {
        var ws = try pinned(strip(5), 5, .right)
        ws.minimumSizes[4] = CGSize(width: 900, height: 100)
        ws.focus(1)
        ws.focus(4)
        try #require(!ws.isInView(4))
        let mini = Miniature(screen: ws.bounds, height: 60, workspace: ws)
        #expect(mini.tiles.map(\.id).contains(4))
        #expect(mini.tiles.last?.id == 5, "the pin drawn over it")
    }
}

struct HeldTargetTests {
    @Test func `While held, the column a let-go would settle on follows the fingers, none when not held`() {
        var ws = strip(6)
        ws.focus(1)
        #expect(ws.heldTarget == nil)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        #expect(ws.heldTarget == 1)
        var seen: [WindowID] = []
        for _ in 0..<12 {
            ws.scrollFreely(by: 120)
            if let t = ws.heldTarget, seen.last != t { seen.append(t) }
        }
        #expect(seen.count >= 3 && seen == seen.sorted(), "one column after the next, left to right")
        ws.endFreeScroll()
        #expect(ws.heldTarget == nil)
    }

    @Test func `Beside a left pin it is always a band column, the first one at the end`() throws {
        var ws = try pinned(strip(6), 1, .left)
        ws.focus(6)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        var moves = 0
        while ws.scrollFreely(by: -150) != 0 {
            moves += 1
            let target = try #require(ws.heldTarget)
            #expect((2...6).contains(target))
        }
        #expect(moves >= 1)
        #expect(ws.heldTarget == 2)
    }

    @Test func `Beside a right pin it is always a band column, the last one at the end`() throws {
        var ws = try pinned(strip(6), 6, .right)
        ws.focus(1)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        var moves = 0
        while ws.scrollFreely(by: 150) != 0 {
            moves += 1
            let target = try #require(ws.heldTarget)
            #expect((1...5).contains(target))
        }
        #expect(moves >= 1)
        #expect(ws.heldTarget == 5)
    }

    @Test func `Taking hold from a focused pin settles on a band column`() throws {
        var ws = try pinned(strip(6), 1, .left)
        ws.focus(1)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        let target = try #require(ws.heldTarget)
        #expect(target != 1)
    }
}

struct PinHangingTests {
    @Test(arguments: [Gaps.zero, spaced])
    func `A lone band window wider than the band at a wall hangs under the pin, not hidden behind it`(gaps: Gaps) throws {
        var ws = try pinned(strip(2, gaps: gaps, walls: [.right]), 1, .left)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        let frame = try #require(ws.layout().frames[2])
        #expect(abs(frame.maxX - ws.bounds.maxX) <= 1)
        #expect(frame.intersects(ws.bandRect))
        #expect(!ws.pinRect(0).contains(frame))
        #expect(ws.hangsUnderPin(2))
    }

    @Test(arguments: [Gaps.zero, spaced])
    func `A focused wide band window at a wall hangs under the pin`(gaps: Gaps) throws {
        var ws = try pinned(strip(4, gaps: gaps, walls: [.right]), 1, .left)
        ws.minimumSizes[3] = CGSize(width: 800, height: 100)
        ws.focus(3)
        let frame = try #require(ws.layout().frames[3])
        #expect(frame.maxX <= ws.bounds.maxX + 1)
        #expect(frame.intersects(ws.bandRect))
        #expect(!ws.pinRect(0).contains(frame))
    }

    @Test(arguments: [Gaps.zero, spaced])
    func `Past a left wall beside a right pin it is held at the wall, whole`(gaps: Gaps) throws {
        var ws = try pinned(strip(4, gaps: gaps, walls: [.left]), 4, .right)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        ws.focus(2)
        // Not the column at rest beside the pin any more: only its frame says it spans the band.
        ws.focus(3)
        try #require(!ws.hangsUnderPin(2))
        var frames = ws.stripFrames
        let strip = try #require(frames[2])
        frames[2] = strip.offsetBy(dx: ws.bounds.minX - 150 - strip.minX, dy: 0)
        let placed = try #require(ws.placeStrip(frames)[2])
        #expect(abs(placed.minX - ws.bounds.minX) <= 1)
        #expect(placed.width == strip.width && placed.height == strip.height, "whole, not hidden behind a column")
        #expect(placed.intersection(ws.bandRect).width > 0)
    }

    @Test func `Hanging under a pin needs it shown from its start, not scrolled past`() throws {
        var ws = try pinned(strip(2), 1, .left)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        #expect(!ws.isInView(2))
        #expect(ws.hangsUnderPin(2))
        do { let r = ws.beginFreeScroll(); #expect(r) }
        ws.scrollFreely(by: 2000)
        #expect(!ws.hangsUnderPin(2))
    }

    @Test func `The band does not jump as fingers take hold or focus goes to the pin`() throws {
        var ws = try pinned(strip(4, width: 0.3), 1, .left)
        ws.minimumSizes[4] = CGSize(width: Double(ws.stripArea.width) + 10, height: 100)
        ws.focus(4)
        let shown = ws.layout().frames
        var held = ws
        do { let r = held.beginFreeScroll(); #expect(r) }
        #expect(held.layout().frames == shown)
        var pin = ws
        pin.focus(1)
        #expect(pin.layout().frames.filter { $0.key != 1 } == shown.filter { $0.key != 1 })
    }

    @Test func `The miniature shows a wide column clipped to the band, and one just wider than the area`() throws {
        var ws = try pinned(strip(5), 5, .right)
        ws.minimumSizes[4] = CGSize(width: 900, height: 100)
        ws.focus(1)
        ws.focus(4)
        let mini = Miniature(screen: ws.bounds, height: 60, workspace: ws)
        let tile = try #require(mini.tiles.first { $0.id == 4 })
        let scale = mini.size.width / ws.bounds.width
        let band = ws.bandRect
        #expect(tile.frame.minX >= (band.minX * scale).rounded() - 2 && tile.frame.maxX <= (band.maxX * scale).rounded() + 2)
        var edge = try pinned(strip(5), 5, .right)
        edge.minimumSizes[3] = CGSize(width: Double(edge.stripArea.width) + 5, height: 100)
        edge.focus(3)
        try #require(edge.hangsUnderPin(3))
        let card = Miniature(screen: edge.bounds, height: 60, workspace: edge)
        #expect(card.tiles.map(\.id).contains(3))
    }
}

struct PinRingPushTests {
    @Test func `In push mode the pins keep their rings while a band column fills the band`() throws {
        var ws = try pinned(strip(5), 1, .left)
        ws.focus(2)
        do { let r = ws.join(.left); #expect(r) }
        ws.focus(4)
        ws.toggleFullscreen()
        #expect(Set(ws.ringedPins) == [1, 2])
        ws.toggleFullscreen()
        ws.focus(1)
        ws.toggleFullscreen()
        #expect(ws.ringedPins == [1])
    }
}

struct PinLayerTests {
    @Test func `A band window above the pin's level never has it raised`() throws {
        let ws = try pinned(strip(4), 1, .left)
        let layout = ws.layout()
        let pin = StackedWindow(id: 1, layer: 0, frame: layout.frames[1]!, pid: 1)
        let away = StackedWindow(id: 3, layer: 3, frame: rect(900, 0, 50, 600), pid: 3)
        #expect(ws.pinsToRaise(stack: [away, pin], candidates: [], takingHold: true).isEmpty)
        #expect(ws.pinsToRaise(stack: [away, pin], candidates: [], sweeping: [1: [3]]).isEmpty)
        var low = away
        low.layer = 0
        #expect(ws.pinsToRaise(stack: [low, pin], candidates: [], takingHold: true) == [1])
        let over = StackedWindow(id: 3, layer: 3, frame: rect(100, 0, 300, 600), pid: 3)
        #expect(ws.pinsToRaise(stack: [over, pin], candidates: []).isEmpty)
    }
}

struct PinRaiseOrderTests {
    @Test func `A focused pin of the front app is raised last of its app's, after its other pin`() {
        let order = pinRaiseOrder(ownPins: [10, 20], fronts: [], front: 20, keepsFront: true, otherPins: [], restore: [])
        #expect(order == [10, 20])
    }

    @Test func `A focused pin listed first among its app's pins still goes last of them`() {
        #expect(pinRaiseOrder(ownPins: [20, 10], fronts: [], front: 20, keepsFront: true, otherPins: [], restore: []) == [10, 20])
        #expect(pinRaiseOrder(ownPins: [20, 10], fronts: [5], front: 20, keepsFront: true, otherPins: [30], restore: [40])
                == [10, 5, 20, 30, 40])
    }

    @Test func `The focused band window goes after its app's pins, before other apps' pins and the windows put back`() {
        let order = pinRaiseOrder(ownPins: [10], fronts: [5, 7], front: 7, keepsFront: true, otherPins: [30], restore: [40])
        #expect(order == [10, 5, 7, 30, 40])
        let none = pinRaiseOrder(ownPins: [], fronts: [], front: 7, keepsFront: false, otherPins: [30], restore: [])
        #expect(none == [30])
    }
}

struct StripTickerTests {
    @Test func `Fingers resting at an end, wiggling a fraction of a point from taking hold, never tick`() {
        var ws = strip(6, gaps: spaced)
        ws.focus(1)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        var ticker = StripTicker(target: ws.heldTarget, offset: ws.shownOffset, atEnd: ws.heldAtEnd)
        var ticks = 0
        for i in 0..<20 {
            ws.scrollFreely(by: i.isMultiple(of: 2) ? 0.6 : -0.6)
            if case .tick = ticker.moved(to: ws.heldTarget, offset: ws.shownOffset, at: Double(i), atEnd: ws.heldAtEnd) {
                ticks += 1
            }
        }
        #expect(ticks == 0)
    }

    @Test func `A first crossing ticks at once, by a point`() {
        var ticker = StripTicker(target: 1, offset: 119)
        #expect(ticker.moved(to: 1, offset: 119.5, at: 1) == .none)
        #expect(ticker.moved(to: 2, offset: 120.5, at: 2) == .tick(2))
    }

    @Test func `Jitter about a midpoint ticks once on the way over and never back`() {
        var ticker = StripTicker(target: 1, offset: 119.4)
        var ticks = 0
        for i in 0..<20 {
            let offset: CGFloat = i.isMultiple(of: 2) ? 120.6 : 119.4
            if case .tick = ticker.moved(to: offset > 120 ? 2 : 1, offset: offset, at: Double(i)) { ticks += 1 }
        }
        #expect(ticks == 1)
        #expect(ticker.moved(to: 1, offset: 100, at: 100) == .tick(1), "a real move back ticks")
    }

    @Test func `A stroke that crosses two columns inside the gap ticks the last once the gap ends`() {
        var ticker = StripTicker(target: 1, offset: 0)
        #expect(ticker.moved(to: 2, offset: 50, at: 1.000) == .tick(2))
        #expect(ticker.moved(to: 3, offset: 100, at: 1.020) == .later(1.055))
        #expect(ticker.moved(to: 3, offset: 100, at: 1.055) == .tick(3))
        #expect(ticker.moved(to: 3, offset: 101, at: 1.060) == .none)
    }

    @Test func `Over and back with real moves, the back inside the gap, ticks twice`() {
        var ticker = StripTicker(target: 1, offset: 0)
        #expect(ticker.moved(to: 2, offset: 50, at: 1.000) == .tick(2))
        #expect(ticker.moved(to: 1, offset: 30, at: 1.020) == .later(1.055))
        #expect(ticker.moved(to: 1, offset: 30, at: 1.055) == .tick(1))
    }
}

struct PinHangingMotionTests {
    /// Glides `ws` from focusing `from` to focusing `to` in ten steps, and checks the wide window `wide`, wherever its
    /// frame spans the band, half a gap allowed, is placed in the band at its height and held off the walls.
    private func glide(_ ws: inout Workspace, wide: WindowID, from: WindowID, to: WindowID,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        ws.focus(from)
        let start = ws.stripFrames
        ws.focus(to)
        let end = ws.stripFrames
        let band = ws.bandRect, half = ws.gaps.horizontal / 2
        var checked = 0
        for step in 1..<10 {
            let t = CGFloat(step) / 10
            var frames: [WindowID: CGRect] = [:]
            for (id, last) in end {
                let first = start[id] ?? last
                frames[id] = CGRect(x: first.minX + (last.minX - first.minX) * t, y: last.minY, width: last.width,
                                    height: last.height)
            }
            guard let frame = frames[wide], frame.minX <= band.minX + half + 1, frame.maxX >= band.maxX - half - 1
            else { continue }
            checked += 1
            let shown = ws.placeStrip(frames)[wide]!
            #expect(shown.intersection(band).width > 0 && shown.height == frame.height,
                    "in the band at its height: step \(step)", sourceLocation: sourceLocation)
            #expect(shown.minX >= ws.bounds.minX - 1 && shown.maxX <= ws.bounds.maxX + 1,
                    "held off the walls: step \(step)", sourceLocation: sourceLocation)
        }
        #expect(checked > 0, "some step spans the band", sourceLocation: sourceLocation)
    }

    @Test(arguments: [Gaps.zero, spaced])
    func `Gliding from one band column to the next, a wide window at a wall is never hidden behind the pin`(gaps: Gaps) throws {
        var ws = try pinned(strip(4, gaps: gaps, walls: [.right]), 1, .left)
        ws.minimumSizes[3] = CGSize(width: 800, height: 100)
        glide(&ws, wide: 3, from: 3, to: 4)
    }

    @Test(arguments: [Gaps.zero, spaced])
    func `The same past a left wall beside a right pin`(gaps: Gaps) throws {
        var ws = try pinned(strip(4, gaps: gaps, walls: [.left]), 4, .right)
        ws.minimumSizes[2] = CGSize(width: 800, height: 100)
        glide(&ws, wide: 2, from: 2, to: 3)
    }

    @Test(arguments: [Gaps.zero, spaced])
    func `Scrolled by the fingers, a lone wide window at a wall is never hidden behind the pin`(gaps: Gaps) throws {
        var ws = try pinned(strip(2, gaps: gaps, walls: [.right]), 1, .left)
        ws.minimumSizes[2] = CGSize(width: 900, height: 100)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        for _ in 0..<5 {
            ws.scrollFreely(by: 10)
            let placed = ws.placeStrip(ws.stripFrames)
            #expect(!ws.pinRect(0).contains(placed[2]!))
            #expect(placed[2]!.intersection(ws.bandRect).width > 0 && placed[2]!.height == ws.stripArea.height,
                    "in the band at its height")
            #expect(placed[2]!.maxX <= ws.bounds.maxX + 1, "held off the wall")
        }
    }

    @Test func `With gaps, a wide window's edge half a gap in from the band's still counts as spanning it`() throws {
        var ws = try pinned(strip(4, gaps: spaced, walls: [.right]), 1, .left)
        ws.minimumSizes[3] = CGSize(width: 800, height: 100)
        ws.focus(4)
        try #require(!ws.hangsUnderPin(3))
        var frames = ws.stripFrames
        let band = ws.bandRect, half = ws.gaps.horizontal / 2
        frames[3] = CGRect(x: band.minX + half, y: frames[3]!.minY, width: 800, height: frames[3]!.height)
        let shown = ws.placeStrip(frames)[3]!
        #expect(shown.intersection(band).width > 0 && shown.height == frames[3]!.height)
        #expect(shown.maxX <= ws.bounds.maxX + 1)
    }

    @Test(arguments: [Gaps.zero, spaced])
    func `A wide first band column at the gutter hangs under a right pin, focused or with the pin focused`(gaps: Gaps) throws {
        var ws = try pinned(strip(5, gaps: gaps), 5, .right)
        ws.minimumSizes[1] = CGSize(width: 900, height: 100)
        ws.focus(1)
        #expect(ws.hangsUnderPin(1))
        let mini = Miniature(screen: ws.bounds, height: 60, workspace: ws)
        #expect(mini.tiles.map(\.id).contains(1))
        #expect(mini.parkedRight == 3)
        ws.focus(5)
        #expect(ws.hangsUnderPin(1))
    }

    @Test func `At a right wall a first column wider than the screen keeps its height`() throws {
        var ws = try pinned(strip(5, walls: [.right]), 5, .right)
        ws.minimumSizes[1] = CGSize(width: 1100, height: 100)
        ws.focus(1)
        let frame = try #require(ws.layout().frames[1])
        #expect(frame.height == ws.stripArea.height)
    }

    @Test func `The fingers move the band a point for a point from where it held a wide column`() throws {
        var ws = try pinned(strip(4, width: 0.3), 1, .left)
        ws.minimumSizes[4] = CGSize(width: Double(ws.stripArea.width) + 10, height: 100)
        ws.focus(4)
        let before = ws.layout().frames
        do { let r = ws.beginFreeScroll(); #expect(r) }
        do { let r = ws.scrollFreely(by: -1); #expect(r == -1) }
        let after = ws.layout().frames
        for id: WindowID in [2, 3, 4] where after[id] != nil && before[id] != nil {
            #expect(abs(after[id]!.minX - before[id]!.minX - 1) < 0.01 || before[id]!.minX < 0, "\(id)")
        }
    }
}

struct StripTickerEndTests {
    @Test func `A slow stroke to the strip's start ticks once for the first column, and not again for a wiggle there`() {
        var ws = strip(6, gaps: spaced)
        ws.focus(6)
        do { let r = ws.beginFreeScroll(); #expect(r) }
        var ticker = StripTicker(target: ws.heldTarget, offset: ws.shownOffset, atEnd: ws.heldAtEnd)
        var ticked: [WindowID] = []
        var time = 0.0
        func feed() {
            time += 1
            if case .tick(let t) = ticker.moved(to: ws.heldTarget, offset: ws.shownOffset, at: time, atEnd: ws.heldAtEnd) {
                ticked.append(t)
            }
        }
        while ws.scrollFreely(by: -2) != 0 { feed() }
        feed()
        #expect(ticked.filter { $0 == 1 }.count == 1, "\(ticked)")
        for i in 0..<10 {
            ws.scrollFreely(by: i.isMultiple(of: 2) ? 0.6 : -0.6)
            feed()
        }
        #expect(ticked.filter { $0 == 1 }.count == 1, "\(ticked)")
    }
}
