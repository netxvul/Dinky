import CoreGraphics
import Testing
@testable import DinkyLayout

/// A scrolling workspace of n half-screen columns, its columns between 0 and 1000 inside the gutters.
private func strip(_ n: Int) -> Workspace {
    var ws = Workspace(bounds: rect(-Workspace.peek, 0, 1000 + 2 * Workspace.peek, 600), gaps: .zero, algorithm: .scrolling)
    ws.columnWidth = 0.5
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// The strip's frames with `id` focused, and the workspace as it is then.
private func frames(_ ws: inout Workspace, focusing id: WindowID) -> [WindowID: CGRect] {
    ws.focus(id)
    return ws.stripFrames
}

struct ScrollShortcutTests {
    @Test func `A long scroll glides a screen's width, past none of the columns between`() {
        var ws = strip(8)
        let starts = frames(&ws, focusing: 1), targets = frames(&ws, focusing: 8)
        #expect(starts[3]!.minX == 975 && targets[6]!.maxX == 25, "slivers either end")
        let shortcut = ws.scrollShortcut(from: starts, to: targets)!
        #expect(shortcut.starts[1] == starts[1] && shortcut.starts[2] == starts[2])
        #expect(shortcut.targets[1]!.minX == -1025 && shortcut.targets[2]!.minX == -525, "out of view at the end")
        #expect(shortcut.starts[7]!.minX == 1025 && shortcut.starts[8]!.minX == 1525, "right behind them")
        #expect(shortcut.targets[7] == targets[7] && shortcut.targets[8] == targets[8])
        for id: WindowID in 3...6 { #expect(shortcut.starts[id] == targets[id], "straight there") }
    }

    @Test func `A long scroll back the other way`() {
        var ws = strip(8)
        let starts = frames(&ws, focusing: 8), targets = frames(&ws, focusing: 1)
        let shortcut = ws.scrollShortcut(from: starts, to: targets)!
        #expect(shortcut.targets[7]!.minX == 1025 && shortcut.targets[8]!.minX == 1525)
        #expect(shortcut.starts[1]!.minX == -1025 && shortcut.starts[2]!.minX == -525)
        for id: WindowID in 3...6 { #expect(shortcut.starts[id] == targets[id]) }
    }

    @Test func `A scroll that keeps a column in view glides as it is`() {
        var ws = strip(4)
        let starts = frames(&ws, focusing: 4), targets = frames(&ws, focusing: 2)
        #expect(ws.scrollShortcut(from: starts, to: targets) == nil)
    }

    @Test func `A window out of view that would cross the screen goes straight there`() {
        var ws = strip(8)
        let targets = frames(&ws, focusing: 1)
        var starts = targets
        starts[6] = starts[6]!.offsetBy(dx: -4000, dy: 0)
        let shortcut = ws.scrollShortcut(from: starts, to: targets)!
        #expect(shortcut.starts == targets)
        #expect(shortcut.targets == targets)
    }

    @Test func `A long scroll where a window in view changes size glides as it is`() {
        var ws = strip(8)
        let starts = frames(&ws, focusing: 1)
        var targets = frames(&ws, focusing: 8)
        targets[8]!.size.width -= 100
        let shortcut = ws.scrollShortcut(from: starts, to: targets)!
        #expect(shortcut.targets[1] == targets[1] && shortcut.starts[8] == starts[8], "the columns in view glide all the way")
        for id: WindowID in 3...6 { #expect(shortcut.starts[id] == targets[id], "those between still go straight there") }
    }
}
