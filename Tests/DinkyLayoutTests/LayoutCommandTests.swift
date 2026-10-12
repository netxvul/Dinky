import CoreGraphics
import Testing
@testable import DinkyLayout

/// i3's answer for `move` from every window of h[1 v[2 3]] in every direction.
struct MoveEveryDirectionTests {
    static let expected: [WindowID: [Direction: String]] = [
        1: [.left: "h[1 v[2 3]]", .right: "v[2 3 1]", .up: "v[1 2 3]", .down: "v[2 3 1]"],
        2: [.left: "h[1 2 3]", .right: "h[1 3 2]", .up: "v[2 h[1 3]]", .down: "h[1 v[3 2]]"],
        3: [.left: "h[1 3 2]", .right: "h[1 2 3]", .up: "h[1 v[3 2]]", .down: "v[h[1 2] 3]"],
    ]

    @Test(arguments: [1, 2, 3] as [WindowID], [Direction.left, .right, .up, .down])
    func `Every direction from every window`(id: WindowID, direction: Direction) {
        var ws = workspace(3)
        ws.focus(id)
        ws.move(direction)
        #expect(shape(ws.root) == Self.expected[id]?[direction])
        #expect(ws.focused == id, "keeps focus")
    }

    @Test func `Moving out at the edge keeps the other windows shares`() {
        var ws = workspace(3)
        ws.focus(1)
        ws.move(.up)
        assertRatios(ws.root.ratios, [0.5, 0.25, 0.25])
    }
}

struct FullscreenExitTests {
    @Test func `Focusing another window ends fullscreen`() {
        var ws = workspace(3)
        ws.toggleFullscreen()
        ws.focus(3)
        #expect(ws.fullscreen == 3)
        ws.focus(1)
        #expect(ws.fullscreen == nil)
    }

    @Test func `Layout commands end fullscreen and keep the tree`() {
        let commands: [(String, (inout Workspace) -> Void)] = [
            ("setMode", { $0.setMode(.tiles) }), ("move", { $0.move(.right) }),
            ("join", { $0.join(.down) }), ("resize", { $0.resize(by: 0) }), ("flatten", { $0.flatten() }),
        ]
        for (name, command) in commands {
            var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
            ws.toggleFullscreen()
            command(&ws)
            #expect(ws.fullscreen == nil, "\(name)")
        }
    }
}

struct FullscreenFocusTests {
    private func fullscreen(_ policy: FullscreenFocus) -> Workspace {
        var ws = workspace(3, bounds: rect(0, 0, 1200, 600), gaps: Gaps(all: 10))
        ws.fullscreenFocus = policy
        ws.focus(1)
        ws.toggleFullscreen()
        return ws
    }

    private let filled = rect(10, 10, 1180, 580)

    @Test func `Exit ends fullscreen, as before`() {
        var ws = fullscreen(.exit)
        ws.focus(2)
        #expect(ws.fullscreenWindows.isEmpty)
        #expect(ws.layout().frames[2] != filled)
    }

    @Test func `Follow hands fullscreen to the newly focused window`() {
        var ws = fullscreen(.follow)
        let tile1 = ws.tiledLayout().frames[1]
        ws.focus(2)
        #expect(ws.fullscreenWindows == [2])
        let layout = ws.layout()
        #expect(layout.frames[2] == filled)
        #expect(layout.frames[1] == tile1)
        #expect(layout.order.first == 2)
    }

    @Test func `Keep shows both fullscreen, the focused one in front`() {
        var ws = fullscreen(.keep)
        ws.focus(2)
        #expect(ws.fullscreenWindows == [2, 1])
        let layout = ws.layout()
        #expect(layout.frames[1] == filled)
        #expect(layout.frames[2] == filled)
        #expect(Array(layout.order.prefix(2)) == [2, 1])
        // Back to the first: it comes to the front again.
        ws.focus(1)
        #expect(ws.fullscreenWindows == [1, 2])
    }

    @Test(arguments: [FullscreenFocus.follow, .keep])
    func `Turning fullscreen off ends it for every window`(policy: FullscreenFocus) {
        var ws = fullscreen(policy)
        ws.focus(2)
        ws.toggleFullscreen()
        #expect(ws.fullscreenWindows.isEmpty)
        #expect(ws.layout() == ws.tiledLayout())
    }

    @Test(arguments: [FullscreenFocus.follow, .keep])
    func `Layout commands end it for every window`(policy: FullscreenFocus) {
        var ws = fullscreen(policy)
        ws.focus(2)
        ws.balanceSizes()
        #expect(ws.fullscreenWindows.isEmpty)
    }

    @Test func `Closing the fullscreen window passes it on with follow`() {
        var ws = fullscreen(.follow)
        ws.remove(1)
        #expect(ws.fullscreenWindows == [ws.focused!])
    }

    @Test func `Closing the fullscreen window ends it with exit`() {
        var ws = fullscreen(.exit)
        ws.remove(1)
        #expect(ws.fullscreenWindows.isEmpty)
    }

    @Test func `Closing one of several keeps the rest`() {
        var ws = fullscreen(.keep)
        ws.focus(2)
        ws.remove(1)
        #expect(ws.fullscreenWindows == [2])
        ws.remove(2)
        #expect(ws.fullscreenWindows == [3])
    }

    @Test func `A new window joins with keep and takes over with follow`() {
        var keep = fullscreen(.keep)
        keep.insert(4)
        #expect(keep.fullscreenWindows == [4, 1])
        var follow = fullscreen(.follow)
        follow.insert(4)
        #expect(follow.fullscreenWindows == [4])
    }

    @Test func `A tab taking over keeps its place`() {
        var ws = fullscreen(.keep)
        ws.focus(2)
        ws.replace(1, with: 9)
        #expect(ws.fullscreenWindows == [2, 9])
    }
}

/// `follow` with a delay: the window that took focus waits in its tile until promoted.
struct FullscreenFollowLaterTests {
    private func fullscreen() -> Workspace {
        var ws = workspace(3, bounds: rect(0, 0, 1200, 600))
        ws.fullscreenFocus = .follow
        ws.fullscreenFollowsLater = true
        ws.focus(1)
        ws.toggleFullscreen()
        return ws
    }

    @Test func `The other window goes back first, then the new one fills the screen`() {
        var ws = fullscreen()
        ws.focus(2)
        #expect(ws.fullscreenWindows.isEmpty)
        #expect(ws.pendingFullscreen == 2)
        #expect(ws.layout() == ws.tiledLayout())
        let promoted = ws.promotePendingFullscreen(2)
        #expect(promoted)
        #expect(ws.fullscreenWindows == [2])
        #expect(ws.pendingFullscreen == nil)
        #expect(ws.layout().frames[2] == rect(0, 0, 1200, 600))
    }

    @Test func `Focusing on while waiting hands the wait on`() {
        var ws = fullscreen()
        ws.focus(2)
        ws.focus(3)
        #expect(ws.pendingFullscreen == 3)
        let stale = ws.promotePendingFullscreen(2)
        #expect(!stale)
        #expect(ws.fullscreenWindows.isEmpty)
        let latest = ws.promotePendingFullscreen(3)
        #expect(latest)
        #expect(ws.fullscreenWindows == [3])
    }

    @Test func `Fullscreen during the wait ends it`() {
        var ws = fullscreen()
        ws.focus(2)
        ws.toggleFullscreen()
        #expect(ws.pendingFullscreen == nil)
        #expect(ws.fullscreenWindows.isEmpty)
        let promoted = ws.promotePendingFullscreen(2)
        #expect(!promoted)
    }

    @Test func `A layout command during the wait ends it`() {
        var ws = fullscreen()
        ws.focus(2)
        ws.balanceSizes()
        #expect(ws.pendingFullscreen == nil)
        let promoted = ws.promotePendingFullscreen(2)
        #expect(!promoted)
    }

    @Test func `Closing the fullscreen window passes it on at once`() {
        var ws = fullscreen()
        ws.remove(1)
        #expect(ws.pendingFullscreen == nil)
        #expect(ws.fullscreenWindows == [ws.focused!])
    }

    @Test func `Closing the waiting window passes the wait on`() {
        var ws = fullscreen()
        ws.focus(2)
        ws.remove(2)
        #expect(ws.pendingFullscreen == ws.focused)
        #expect(ws.fullscreenWindows.isEmpty)
    }

    @Test func `A new window waits too`() {
        var ws = fullscreen()
        ws.insert(4)
        #expect(ws.pendingFullscreen == 4)
        #expect(ws.fullscreenWindows.isEmpty)
    }
}

struct AccordionCommandTests {
    @Test func `Focus cycles through accordion order and brings it to front`() {
        var ws = workspace(3, algorithm: .dwindle(.accordion))
        #expect(ws.focus(.left) == true)
        #expect(ws.focused == 2)
        #expect(ws.layout().order.first == 2)
        #expect(ws.focus(.left) == true)
        #expect(ws.layout().order.first == 1)
        #expect(ws.focus(.left) == false)
        #expect(ws.focus(.right) == true)
        #expect(ws.layout().order.first == 2)
    }

    @Test func `Toggling back to tiles restores ratios`() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.resize(by: 300)
        let tiles = ws.layout()
        ws.setMode(.accordion)
        #expect(ws.container(of: 3)?.mode == .accordion)
        #expect(ws.layout() != tiles)
        ws.setMode(.tiles)
        #expect(ws.container(of: 3)?.mode == .tiles)
        #expect(ws.layout() == tiles)
    }

    @Test func `Container of unknown window is nil`() {
        #expect(workspace(1).container(of: 9) == nil)
    }

    @Test func `Container of nested window`() {
        let ws = workspace(3) // 1 on the left, 2 above 3 on the right
        #expect(ws.container(of: 1)?.orientation == .horizontal)
        #expect(ws.container(of: 3)?.orientation == .vertical)
        #expect(ws.container(of: 3).map { shape($0) } == "v[2 3]")
    }
}

struct ResizeAxisTests {
    @Test func `Width resizes the nearest horizontal container`() {
        var ws = workspace(3) // 3 sits in the right column
        #expect(ws.resize(by: 100, along: .horizontal) == true)
        assertRatios(ws.root.ratios, [0.4, 0.6])
        assertRatios(ws.root.container(at: [1]).ratios, [0.5, 0.5])
    }

    @Test func `Height resizes the column`() {
        var ws = workspace(3)
        #expect(ws.resize(by: 60, along: .vertical) == true)
        assertRatios(ws.root.ratios, [0.5, 0.5])
        assertRatios(ws.root.container(at: [1]).ratios, [0.4, 0.6])
    }

    @Test func `No container along the axis`() {
        var ws = workspace(2)
        #expect(ws.resize(by: 50, along: .vertical) == false)
    }
}

struct MinimumSizeTests {
    @Test func `Tile grows to its minimum at its siblings expense`() {
        var ws = workspace(2)
        ws.minimumSizes = [1: CGSize(width: 700, height: 0)]
        #expect(ws.layout().frames[1] == rect(0, 0, 700, 600))
        #expect(ws.layout().frames[2] == rect(700, 0, 300, 600))
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }

    @Test func `Minimums that do not fit are ignored`() {
        var ws = workspace(2)
        ws.minimumSizes = [1: CGSize(width: 700, height: 0), 2: CGSize(width: 700, height: 0)]
        #expect(ws.layout().frames[1] == rect(0, 0, 500, 600))
    }

    @Test func `Nested minimum widens its column`() {
        var ws = workspace(3)
        ws.minimumSizes = [3: CGSize(width: 800, height: 0)]
        #expect(ws.layout().frames[1] == rect(0, 0, 200, 600))
        #expect(ws.layout().frames[2] == rect(200, 0, 800, 300))
    }

    @Test func `Siblings give in proportion and stop at their own minimum`() {
        #expect(fit([1000, 1000, 1000], minimums: [2000, 0, 0], total: 3000) == [2000, 500, 500])
        #expect(fit([1000, 1000, 1000], minimums: [2000, 800, 0], total: 3000) == [2000, 800, 200])
        #expect(fit([600, 300, 100], minimums: [0, 0, 200], total: 1000) == [533.3333333333334, 266.6666666666667, 200])
    }

    @Test func `Resize stops at the minimum`() {
        var ws = workspace(2) // 2 focused
        ws.minimumSizes = [2: CGSize(width: 450, height: 0)]
        #expect(ws.resize(by: -100) == true)
        #expect(ws.layout().frames[2]?.width == 450)
        #expect(ws.resize(by: -100) == false)
    }

    @Test func `Resize the siblings minimum swallows is undone`() {
        var ws = workspace(2)
        ws.focus(1)
        ws.minimumSizes = [2: CGSize(width: 500, height: 0)]
        #expect(ws.resize(by: 100) == false)
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }

    @Test func `Accordion minimum includes the peeking neighbours`() {
        let accordion = Node.container(Container(.horizontal, .accordion, [.window(1), .window(2), .window(3)]))
        #expect(accordion.minimumExtent(.horizontal, gap: 8, padding: 30, [2: CGSize(width: 400, height: 0)]) == 460)
    }
}
