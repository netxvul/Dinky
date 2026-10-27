import CoreGraphics
import Testing
@testable import DinkyLayout

/// Two displays 1000 wide side by side, meeting at x = 1000; the right one `rightHeight` tall.
private func seam(rightHeight: CGFloat = 600) -> Seam {
    Seam(left: rect(0, 0, 1000, 600), right: rect(1000, 0, 1000, rightHeight))
}

/// A scrolling workspace across `seam` with windows 1...n inserted in order, so n is focused.
private func spanning(_ n: Int, width: Double = 0.5, gaps: Gaps = .zero, seam: Seam = seam(),
                      centring: ColumnCentring = .never) -> Workspace {
    var ws = Workspace(bounds: seam.bounds, gaps: gaps, algorithm: .scrolling)
    ws.setSeam(seam)
    ws.columnWidth = width
    ws.columnCentring = centring
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// The windows whose frames reach over the seam by more than half a point.
private func straddling(_ ws: Workspace) -> [WindowID] {
    let frames = ws.layout().frames, x = ws.seam!.x
    return ws.windows.filter { frames[$0]!.minX < x - 0.5 && frames[$0]!.maxX > x + 0.5 }
}

struct SpanTests {
    @Test func `A lone column fills only the display it is on`() {
        #expect(spanning(1).layout().frames[1] == rect(0, 0, 1000, 600))
        #expect(spanning(1, gaps: Gaps(all: 10)).layout().frames[1] == rect(10, 10, 985, 580), "half an inner gap from the seam")
    }

    @Test func `Column widths are shares of one display`() {
        let frames = spanning(3).layout().frames
        #expect([1, 2, 3].map { frames[$0]!.width } == [500, 500, 500])
    }

    @Test func `No column straddles the seam wherever focus goes`() {
        for n in 2...6 {
            for width in [0.5, 0.4, 0.6, 1.0 / 3] {
                var ws = spanning(n, width: width, gaps: Gaps(all: 10))
                for id in ws.windows + ws.windows.reversed() {
                    ws.focus(id)
                    #expect(straddling(ws).isEmpty, "\(n) columns at \(width), \(id) focused")
                    let frame = ws.layout().frames[id]!
                    #expect(frame.minX >= 0 && frame.maxX <= 2000, "the focused column shows whole")
                }
            }
        }
    }

    @Test func `The seam falls in the gap between two columns`() {
        let frames = spanning(4, gaps: Gaps(all: 10)).layout().frames
        let left = frames.values.filter { $0.maxX <= 1000 }.map(\.maxX).max()
        let right = frames.values.filter { $0.minX >= 1000 }.map(\.minX).min()
        #expect(left == 995 && right == 1005, "half an inner gap either side")
    }

    @Test func `Columns park and peek only at the outer edges`() {
        var ws = spanning(8)
        ws.focus(4)
        let frames = ws.layout().frames
        #expect(straddling(ws).isEmpty)
        let parked = ws.windows.filter { frames[$0]!.minX < 0 || frames[$0]!.maxX > 2000 }
        #expect(!parked.isEmpty)
        for id in ws.windows {
            let frame = frames[id]!
            let onLeft = frame.minX >= 0 && frame.maxX <= 1000, onRight = frame.minX >= 1000 && frame.maxX <= 2000
            let peeks = frame.maxX <= Workspace.peek + 0.5 || frame.minX >= 2000 - Workspace.peek - 0.5
            #expect(onLeft || onRight || peeks, "\(id) at \(frame)")
        }
    }

    @Test func `A column is as tall as the display it is on`() {
        let ws = spanning(4, gaps: Gaps(all: 10), seam: seam(rightHeight: 400))
        let frames = ws.layout().frames
        for id in ws.windows {
            #expect(frames[id]!.height == (frames[id]!.midX < 1000 ? 580 : 380))
        }
    }

    @Test func `Centring keeps the seam between columns`() {
        var ws = spanning(5, width: 0.5, centring: .always)
        for id in ws.windows {
            ws.focus(id)
            #expect(straddling(ws).isEmpty)
            let frame = ws.layout().frames[id]!
            #expect(frame.minX >= 0 && frame.maxX <= 2000)
        }
    }

    @Test(arguments: [ColumnCentring.never, .always, .onOverflow, .alwaysFill],
          [SpanCentring.both, .focused, .display(left: true), .display(left: false)])
    func `Stepping focus scrolls the strip only the way it steps`(_ centring: ColumnCentring, _ on: SpanCentring) {
        // Displays of different sizes, as a laptop's beside a monitor, so the middle of both is not the seam.
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: centring)
        ws.spanCentring = on
        ws.focus(1)
        var offset = ws.shownOffset
        for direction in Array(repeating: Direction.right, count: 7) + Array(repeating: .left, count: 7) {
            let moved = ws.focus(direction)
            #expect(moved)
            let now = ws.shownOffset
            #expect(direction == .right ? now >= offset : now <= offset, "\(centring) \(on) \(direction) to \(ws.focused!)")
            #expect(straddling(ws).isEmpty)
            offset = now
        }
    }

    @Test func `Centring rests the focused column beside the seam`() {
        var ws = spanning(6, gaps: Gaps(all: 10), centring: .always)
        for id in [3, 4, 5] as [WindowID] {
            ws.focus(id)
            let frame = ws.layout().frames[id]!
            #expect(frame.maxX == 995 || frame.minX == 1005, "\(id) at \(frame)")
        }
    }

    @Test(arguments: [true, false]) func `Centring on one display brings the focused column there`(_ left: Bool) {
        var ws = spanning(8, gaps: Gaps(all: 10), centring: .always)
        ws.spanCentring = .display(left: left)
        for id in [4, 5, 6, 7, 6, 5, 4, 3] as [WindowID] {
            ws.focus(id)
            let frame = ws.layout().frames[id]!
            #expect(left ? frame.maxX <= 1000 : frame.minX >= 1000, "\(id) at \(frame)")
            #expect(straddling(ws).isEmpty)
        }
    }

    @Test func `Centring on the focused column's display keeps it on the display it was on`() {
        var ws = spanning(8, gaps: Gaps(all: 10), centring: .always)
        ws.spanCentring = .focused
        ws.focus(4)
        for direction in [Direction.right, .right, .left, .left] {
            let before = ws.layout()
            _ = ws.focus(direction)
            let id = ws.focused!, was = before.frames[id]!, now = ws.layout().frames[id]!
            // Wholly on a display before: on that one still.
            if was.maxX <= 1000 || was.minX >= 1000 { #expect((was.midX < 1000) == (now.midX < 1000), "\(id) from \(was) to \(now)") }
        }
    }

    @Test func `The column in view at an outer edge reaches over room the narrower display's shares leave`() {
        // The left display 120 points wider than the right: two half columns leave that much at its outer edge.
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .always)
        ws.focus(5)
        let frames = ws.layout().frames
        let left = ws.windows.filter { frames[$0]!.minX >= -1920 && frames[$0]!.maxX <= 0 }
        let outer = left.min { frames[$0]!.minX < frames[$1]!.minX }!
        #expect(frames[outer]!.minX == -1912, "out to the outer gap")
        #expect(straddling(ws).isEmpty)
    }

    @Test func `Two strips coming together meet at the seam`() {
        var left = Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling)
        left.insert(1)
        left.insert(2)
        var right = Workspace(bounds: rect(1000, 0, 1000, 600), algorithm: .scrolling)
        right.insert(3)
        right.insert(4)
        left.setSeam(seam())
        left.takeColumns(of: right)
        #expect(left.windows == [1, 2, 3, 4])
        #expect(left.focused == 2)
        let frames = left.layout().frames
        #expect(frames[1] == rect(0, 0, 500, 600))
        #expect(frames[2] == rect(500, 0, 500, 600))
        #expect(frames[3] == rect(1000, 0, 500, 600))
        #expect(frames[4] == rect(1500, 0, 500, 600))
    }

    @Test func `Fullscreen pushing fills only the column's display`() {
        var ws = spanning(4)
        ws.focus(3)
        ws.toggleFullscreen()
        let frame = ws.layout().frames[3]!
        #expect(frame.width > 900, "the display less the gutter its neighbours park in")
        #expect(frame.minX >= 1000 && frame.maxX <= 2000 || frame.minX >= 0 && frame.maxX <= 1000)
        #expect(straddling(ws).isEmpty)
    }

    @Test func `On one display nothing changes`() {
        var plain = Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling)
        var unspanned = plain
        unspanned.setSeam(nil)
        for id in 1...4 as ClosedRange<WindowID> {
            plain.insert(id)
            unspanned.insert(id)
        }
        #expect(plain.layout() == unspanned.layout())
    }
}
