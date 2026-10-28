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
        // Five, which do not all fit on the two displays; no gutters for parked ones to peek in, to measure by.
        var ws = spanning(5)
        ws.spanPeeks = false
        let frames = ws.layout().frames
        #expect([2, 3, 4, 5].map { frames[$0]!.width } == [500, 500, 500, 500])
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

    @Test func `With walls at the outer edges nothing peeks and the columns fill both displays`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.walls = [.left, .right]
        for id in ws.windows {
            ws.focus(id)
            let frames = ws.layout().frames
            #expect(straddling(ws).isEmpty, "\(id)")
            for other in ws.windows {
                #expect(frames[other]!.minX >= -1920 && frames[other]!.maxX <= 1800, "\(other) at \(frames[other]!), \(id) focused")
            }
            let shown = ws.windows.map { frames[$0]! }.filter { $0.width > 200 }
            #expect(shown.map(\.minX).min() == -1912 && shown.map(\.maxX).max() == 1792, "\(id) focused: \(ws.windows.map { "\($0):\(Int(frames[$0]!.minX))+\(Int(frames[$0]!.width))" })")
        }
    }

    @Test(arguments: [SpanCentring.both, .focused, .display(left: true), .display(left: false)])
    func `Focus beside a column as wide as a display leaves neither display bare`(_ on: SpanCentring) {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.walls = [.left, .right]
        ws.spanCentring = on
        ws.setWidth(ofColumn: 3, 1)
        ws.focus(4)
        for direction in [Direction.left, .left, .right, .right, .right] {
            _ = ws.focus(direction)
            let frames = ws.layout().frames
            for (from, to) in [(CGFloat(-1912), CGFloat(-4)), (4, 1792)] {
                // The room the windows on the display cover, the gaps between them counted as covered; windows hiding
                // behind others add nothing.
                let shown = ws.windows.map { frames[$0]! }.filter { $0.minX >= from - 1 && $0.maxX <= to + 1 }
                    .sorted { $0.minX < $1.minX }
                var reach = from, covered: CGFloat = 0
                for frame in shown where frame.maxX > reach {
                    covered += frame.maxX - max(frame.minX - 8, reach)
                    reach = frame.maxX
                }
                #expect(covered >= to - from - 1, "\(on) \(direction) to \(ws.focused!): \(from)...\(to) shows \(shown)")
            }
            #expect(straddling(ws).isEmpty)
        }
    }

    @Test(arguments: [PinSide.left, .right]) func `Beside a pin the band fills the rest of its display`(_ side: PinSide) {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.walls = [.left, .right]
        ws.focus(side == .left ? 1 : 8)
        _ = ws.pin(side)
        #expect(ws.pins[side] != nil)
        for direction in Array(repeating: side == .left ? Direction.right : .left, count: 4) {
            _ = ws.focus(direction)
            let frames = ws.layout().frames
            #expect(straddling(ws).isEmpty)
            for (from, to) in [(CGFloat(-1912), CGFloat(-4)), (4, 1792)] {
                // As a window hides behind others: the room the windows cover, gaps counted, none showing a sliver.
                let shown = ws.windows.map { frames[$0]! }.filter { $0.minX >= from - 1 && $0.maxX <= to + 1 }
                    .sorted { $0.minX < $1.minX }
                var reach = from, covered: CGFloat = 0
                for frame in shown where frame.maxX > reach {
                    covered += frame.maxX - max(frame.minX - 8, reach)
                    reach = frame.maxX
                }
                #expect(covered >= to - from - 1, "\(side) \(direction) to \(ws.focused!): \(from)...\(to) shows \(shown)")
            }
        }
    }

    @Test func `A step past an end of the strip runs into that end`() {
        var ws = spanning(4)
        ws.focus(1)
        #expect(ws.endRunInto(by: ["focus left"], from: 1) == .left)
        #expect(ws.endRunInto(by: ["move left"], from: 1) == .left)
        #expect(ws.endRunInto(by: ["focus right"], from: 1) == nil, "a column beyond")
        #expect(ws.endRunInto(by: ["focus right"], from: 4) == .right)
        #expect(ws.endRunInto(by: ["join-with right"], from: 4) == .right)
        #expect(ws.endRunInto(by: ["focus up"], from: 4) == nil)
        #expect(ws.endRunInto(by: ["resize width +50", "focus left"], from: 1) == .left)
        // On one display, none: the window's own edge glows there, as ever.
        var plain = Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling)
        plain.insert(1)
        #expect(plain.endRunInto(by: ["focus left"], from: 1) == nil)
    }

    @Test func `Without peeks parked columns show no more than the outer gap, keeping their size`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.spanPeeks = false
        for id in ws.windows {
            ws.focus(id)
            let frames = ws.layout().frames
            #expect(straddling(ws).isEmpty)
            let inView = ws.windows.map { frames[$0]! }.filter { $0.minX >= -1920 && $0.maxX <= 1800 }
            for other in ws.windows {
                let frame = frames[other]!
                let shown = frame.minX >= -1920 && frame.maxX <= 1800
                // Past an outer edge, it shows no further in than the outer gap: behind the column reaching out over it.
                let covered = frame.maxX <= -1912 + 0.5 || frame.minX >= 1792 - 0.5
                    || frame.minX < -1920 && inView.contains { $0.minX <= -1912 + 0.5 && $0.maxX >= frame.maxX }
                    || frame.maxX > 1800 && inView.contains { $0.maxX >= 1792 - 0.5 && $0.minX <= frame.minX }
                #expect(shown || covered, "\(other) at \(frame), \(id) focused")
                #expect(frame.width >= 870, "\(other) keeps its size, \(id) focused")
            }
        }
    }

    @Test(arguments: [1, 8] as [WindowID]) func `Fullscreen fills the display its column is on, whichever it is`(_ id: WindowID) {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.spanPeeks = false
        ws.focus(id)
        ws.toggleFullscreen()
        let frames = ws.layout().frames, frame = frames[id]!
        #expect(frame == (frame.midX < 0 ? rect(-1912, 38, 1904, 1154) : rect(8, 47, 1784, 1050)))
        // The other display shows the strip out to its outer gap, no sliver of a parked column beyond.
        let other = ws.windows.filter { $0 != id }.map { frames[$0]! }
            .filter { $0.minX >= -1920 && $0.maxX <= 1800 && ($0.midX < 0) != (frame.midX < 0) }
        #expect(frame.midX < 0 ? other.map(\.maxX).max() == 1792 : other.map(\.minX).min() == -1912)
    }

    @Test(arguments: [ColumnCentring.never, .always, .alwaysFill]) func `Fingers scroll no further than the strip rests at its ends`(
        _ centring: ColumnCentring) {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        for peeks in [true, false] {
            var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: centring)
            ws.spanPeeks = peeks
            for (id, push) in [(1, -5000), (8, 5000)] as [(WindowID, CGFloat)] {
                ws.focus(id)
                let rest = ws.shownOffset
                let held = ws.beginFreeScroll()
                #expect(held)
                #expect(ws.shownOffset == rest, "taking hold moves nothing, \(centring), \(id)")
                ws.scrollFreely(by: push)
                #expect(ws.shownOffset == rest, "nowhere to go past the end, \(centring), \(id)")
                ws.endFreeScroll()
                #expect(ws.shownOffset == rest, "nothing to spring back from, \(centring), \(id)")
            }
        }
    }

    @Test(arguments: [SpanHeight.perDisplay, .overlap, .atRest])
    func `Column heights across displays of different heights`(_ mode: SpanHeight) {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .never)
        ws.spanHeight = mode
        ws.focus(4)
        let rest = ws.shownOffset
        let shown = { (frames: [WindowID: CGRect]) in ws.windows.map { frames[$0]! }.filter { $0.minX < 1800 && $0.maxX > -1920 } }
        // Where a display's own height goes: (y, height) by the display a frame's middle is on.
        let own = { (frame: CGRect) -> (CGFloat, CGFloat) in frame.midX < 0 ? (38, 1154) : (47, 1050) }
        let overlap: (CGFloat, CGFloat) = (47, 1050)
        for frame in shown(ws.layout().frames) {
            let (y, h) = mode == .overlap ? overlap : own(frame)
            #expect(frame.minY == y && frame.height == h, "\(mode) at rest \(frame)")
        }
        // Held part way, a column over the seam.
        let before = Dictionary(uniqueKeysWithValues: ws.windows.map { ($0, ws.layout().frames[$0]!) })
        let held = ws.beginFreeScroll()
        #expect(held)
        ws.scrollFreely(by: -300)
        #expect(ws.shownOffset == rest - 300)
        let frames = ws.stripFrames
        for id in ws.windows where frames[id]!.minX < 1800 && frames[id]!.maxX > -1920 {
            let frame = frames[id]!
            switch mode {
            case .perDisplay: #expect(frame.height == own(frame).1, "\(frame)")
            case .overlap: #expect(frame.minY == 47 && frame.height == 1050, "\(frame)")
            // As where it was as the fingers took hold.
            case .atRest: #expect(frame.height == before[id]!.height, "\(frame) from \(before[id]!)")
            }
        }
        ws.endFreeScroll()
        for frame in shown(ws.layout().frames) {
            let (y, h) = mode == .overlap ? overlap : own(frame)
            #expect(frame.minY == y && frame.height == h, "\(mode) at rest again \(frame)")
        }
    }

    @Test func `Per display, a column takes the shorter display's height just before it crosses, the taller's as it does`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .never)
        ws.focus(4)
        let held = ws.beginFreeScroll()
        #expect(held)
        // Step the strip along a point at a time: each column's height against where its middle is.
        var crossings = 0
        for _ in 0..<1800 {
            ws.scrollFreely(by: -1)
            for frame in ws.stripFrames.values where frame.maxX > -1920 && frame.minX < 1800 {
                let middle = frame.midX
                if middle >= 0 {
                    #expect(frame.height == 1050, "on the shorter display \(frame)")
                } else if middle > -Workspace.seamLead {
                    crossings += 1
                    #expect(frame.height == 1050, "about to cross to the shorter \(frame)")
                } else {
                    #expect(frame.height == 1154, "on the taller display \(frame)")
                }
            }
        }
        #expect(crossings > 0)
    }

    @Test func `On a glide, a window bound for the shorter display has its height at once, for the taller as it crosses`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .never)
        ws.focus(4)
        let start = ws.stripFrames
        _ = ws.focus(.right)
        _ = ws.focus(.right)
        _ = ws.focus(.right)
        let end = ws.stripFrames
        // Steps of a glide from start to end, as the animator has them, placed.
        for step in 0...10 {
            let t = CGFloat(step) / 10
            var frames: [WindowID: CGRect] = [:]
            for (id, a) in start {
                let b = end[id]!
                frames[id] = CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                                    width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
            }
            let placed = ws.placeStrip(frames, resting: end)
            for (id, frame) in placed where frame.maxX > -1920 && frame.minX < 1800 {
                let bound = end[id]!.midX < 0 ? 1154 : 1050 as CGFloat
                let here = frame.midX < 0 ? 1154 : 1050 as CGFloat
                #expect(frame.height == min(here, bound) || frame.height == bound && abs(frame.midX) < Workspace.seamLead,
                        "\(id) at step \(step): \(frame)")
            }
        }
    }

    @Test func `Eased, a column's height comes down smoothly to the shorter display's before it crosses`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(8, gaps: Gaps(all: 8), seam: seam, centring: .never)
        ws.spanHeightAnimates = true
        ws.focus(4)
        for frame in ws.layout().frames.values where frame.maxX > -1920 && frame.minX < 1800 {
            #expect(frame.height == (frame.midX < 0 ? 1154 : 1050), "at rest \(frame)")
        }
        let held = ws.beginFreeScroll()
        #expect(held)
        // Columns on the taller display come to the seam, a point at a time: never taller as they come, the shorter
        // display's height before they cross, heights between the two on the way.
        var last: [WindowID: CGFloat] = [:], between = 0
        for _ in 0..<900 {
            ws.scrollFreely(by: -1)
            for (id, frame) in ws.stripFrames where frame.maxX > -1920 && frame.minX < 1800 {
                if frame.midX >= -Workspace.seamLead { #expect(frame.height == 1050, "\(frame)") }
                if frame.midX < 0, let was = last[id] { #expect(frame.height <= was + 0.5, "\(frame) after \(was)") }
                if frame.height > 1050, frame.height < 1154 { between += 1 }
                last[id] = frame.height
            }
        }
        #expect(between > 0)
    }

    /// Two displays of a laptop beside a monitor, a strip of six with its last column wider than half a display.
    private func endFitting() -> Workspace {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(6, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.spanPeeks = false
        ws.focus(6)
        _ = ws.resizeColumn(by: 1160 - (ws.layout().frames[6]?.width ?? 0))
        ws.focus(6)
        return ws
    }

    @Test func `At the strip's end the column before the end narrows to fill the display`() {
        let ws = endFitting(), frames = ws.layout().frames
        let end = frames[6]!, before = frames[5]!
        #expect(end.maxX == 1792, "the end column at the margin: \(end)")
        #expect(end.width > 1100, "at its own width")
        #expect(before.minX == 4 && before.maxX == end.minX - 8, "the one before it fills from the seam: \(before)")
        #expect(straddling(ws).isEmpty)
        // Left of the seam, the strip as ever: filled to the outer margin.
        let left = ws.windows.map { frames[$0]! }.filter { $0.minX >= -1920 && $0.maxX <= 0 }
        #expect(left.map(\.minX).min() == -1912 && left.map(\.maxX).max() == -4)
    }

    @Test func `Where it cannot narrow so far the end column widens instead`() {
        var ws = endFitting()
        ws.minimumSizes[5] = CGSize(width: 800, height: 100)
        let frames = ws.layout().frames
        #expect(frames[6]!.minX == 4 && frames[6]!.maxX == 1792, "\(frames[6]!)")
        #expect(straddling(ws).isEmpty)
    }

    @Test func `Focus leaving the end gives the columns their widths back`() {
        var ws = endFitting()
        let narrowed = ws.layout().frames[5]!.width
        ws.focus(2)
        let frames = ws.layout().frames
        #expect(frames[5]!.width > narrowed + 100, "back to its own width: \(frames[5]!)")
        #expect(frames[6]!.width > 1100)
        #expect(straddling(ws).isEmpty)
    }

    @Test func `With focus across the seam from an end the strip rests at, that end's display still fills`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(6, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.spanPeeks = false
        ws.focus(1)
        _ = ws.resizeColumn(by: 268)
        for id in [1, 2, 3] as [WindowID] {
            ws.focus(id)
            let frames = ws.layout().frames
            let left = ws.windows.map { frames[$0]! }.filter { $0.minX >= -1920 && $0.maxX <= 0 }
            #expect(left.map(\.minX).min() == -1912 && left.map(\.maxX).max() == -4, "\(id) focused: \(left)")
            #expect(straddling(ws).isEmpty)
        }
    }

    @Test func `Merged widths make half a column a display, none wider than one`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        for n in [2, 4, 6] {
            var ws = spanning(n, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
            ws.spanPeeks = false
            ws.spanWidthMerged = true
            for id in ws.windows {
                ws.focus(id)
                let frames = ws.layout().frames
                #expect(straddling(ws).isEmpty)
                for frame in frames.values where frame.minX >= -1920 && frame.maxX <= 1800 {
                    // Two to a display's room at 0.25 each, one at 0.5, give or take the edge filling.
                    // From the outer gap to half a gap from the seam on the wider display, at most.
                    #expect(frame.width <= 1908, "\(n): \(frame)")
                }
                let left = ws.windows.map { frames[$0]! }.filter { $0.minX >= -1920 && $0.maxX <= 0 }
                let right = ws.windows.map { frames[$0]! }.filter { $0.minX >= 0 && $0.maxX <= 1800 }
                #expect(left.map(\.minX).min() == -1912 && right.map(\.maxX).max() == 1792, "\(n), \(id): \(left) \(right)")
            }
        }
        // Half a column is a display: two windows, one to each.
        var two = spanning(2, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        two.spanWidthMerged = true
        let frames = two.layout().frames
        #expect(frames[1]!.width > 1700 && frames[2]!.width > 1700, "\(frames)")
    }

    @Test func `Two columns are one to each display, filling it, three or more their widths`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var two = spanning(2, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        for id in two.windows {
            two.focus(id)
            let frames = two.layout().frames
            #expect(frames[1] == rect(-1912, 38, 1908, 1154) && frames[2] == rect(4, 47, 1788, 1050), "\(frames)")
        }
        // Three: two on one display at their widths, the one alone on the other filling it.
        var three = spanning(3, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        for id in three.windows {
            three.focus(id)
            let frames = three.layout().frames
            let left = three.windows.map { frames[$0]! }.filter { $0.maxX <= 0 }
            let right = three.windows.map { frames[$0]! }.filter { $0.minX >= 0 }
            #expect(left.count + right.count == 3 && Set([left.count, right.count]) == [1, 2], "\(frames)")
            let lone = left.count == 1 ? left[0] : right[0], pair = left.count == 1 ? right : left
            #expect(lone.width >= 1788, "alone, filling its display: \(lone)")
            #expect(pair.allSatisfy { $0.width < 1100 }, "two at their widths, give or take an edge reached over: \(pair)")
            #expect(straddling(three).isEmpty)
        }
        // A fourth that does not fit with them: their widths again.
        three.insert(4)
        three.insert(5)
        let frames = three.layout().frames
        #expect(frames.values.filter { $0.minX >= -1920 && $0.maxX <= 1800 }.allSatisfy { $0.width < 1100 }, "\(frames)")
    }

    @Test func `A column dragged to a width takes it, though it showed wider filling an edge`() {
        let seam = Seam(left: rect(-1920, 30, 1920, 1170), right: rect(0, 39, 1800, 1066))
        var ws = spanning(5, gaps: Gaps(all: 8), seam: seam, centring: .alwaysFill)
        ws.spanPeeks = false
        ws.focus(1)
        for width in [630, 1100, 760] as [CGFloat] {
            let taken = ws.resize(1, to: CGSize(width: width, height: 1154), moving: [.right])
            #expect(taken)
            #expect(ws.layout().frames[1]!.width == width, "\(width): \(ws.layout().frames[1]!)")
            #expect(straddling(ws).isEmpty)
        }
        // One in the middle, on the other display.
        ws.focus(4)
        let shown = ws.layout().frames[4]!
        let taken = ws.resize(4, to: CGSize(width: shown.width - 200, height: shown.height), moving: [.right])
        #expect(taken)
        #expect(abs(ws.layout().frames[4]!.width - (shown.width - 200)) <= 1, "\(ws.layout().frames[4]!) from \(shown)")
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
