import CoreGraphics
import Testing
@testable import DinkyLayout

/// A scrolling workspace with windows 1...n inserted in order, so n is focused and in view. Its columns go
/// between 0 and 1000, inside the gutters, when it has no gaps or walls.
private func strip(_ n: Int, width: Double = 0.5, gaps: Gaps = .zero, walls: Set<Direction> = []) -> Workspace {
    var ws = Workspace(bounds: rect(-Workspace.peek, 0, 1000 + 2 * Workspace.peek, 600), gaps: gaps, algorithm: .scrolling)
    ws.columnWidth = width
    ws.walls = walls
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

struct ScrollingWidthSurvivalTests {
    @Test func `A column keeps the width it was given when its window is minimized and shown again`() {
        var ws = strip(3, width: 0.5)
        // The middle column takes a width of its own.
        ws.setWidth(ofColumn: 1, 0.3)
        #expect(ws.width(ofColumn: 1) == 0.3)

        // Minimized: it goes away for a while, but comes back.
        ws.depart(2)
        #expect(!ws.contains(2))

        // Shown again: it comes back at the width it had.
        ws.arrive(2)
        #expect(ws.contains(2))
        // Window 2 may be in a different column index now, but it should have its saved width
        let column = ws.root.path(of: 2)![0]
        #expect(ws.width(ofColumn: column) == 0.3, "the width it was given, not the default")
    }

    @Test func `A window that was never resized comes back at the default width`() {
        var ws = strip(3, width: 0.5)
        ws.depart(2)
        ws.arrive(2)
        #expect(ws.width(ofColumn: 1) == 0.5)
    }

    @Test func `Multiple windows preserve their custom widths through minimize and restore`() {
        var ws = strip(4, width: 0.5)
        // Give each column a different width
        ws.setWidth(ofColumn: 0, 0.3)
        ws.setWidth(ofColumn: 1, 0.6)
        ws.setWidth(ofColumn: 2, 0.4)
        ws.setWidth(ofColumn: 3, 0.7)

        // Minimize all windows
        ws.depart(1)
        ws.depart(2)
        ws.depart(3)
        ws.depart(4)
        #expect(ws.windows.isEmpty)

        // Restore all windows
        ws.arrive(1)
        ws.arrive(2)
        ws.arrive(3)
        ws.arrive(4)

        // Each should have its custom width back
        #expect(ws.width(ofColumn: 0) == 0.3)
        #expect(ws.width(ofColumn: 1) == 0.6)
        #expect(ws.width(ofColumn: 2) == 0.4)
        #expect(ws.width(ofColumn: 3) == 0.7)
    }

    @Test func `Width preservation works for windows restored in different order`() {
        var ws = strip(3, width: 0.5)
        ws.setWidth(ofColumn: 0, 0.3)
        ws.setWidth(ofColumn: 1, 0.6)
        ws.setWidth(ofColumn: 2, 0.4)

        // Minimize all
        ws.depart(1)
        ws.depart(2)
        ws.depart(3)

        // Restore in different order
        ws.arrive(3)
        ws.arrive(1)
        ws.arrive(2)

        // Each should still have its width, regardless of restore order
        #expect(ws.width(ofColumn: 0) == 0.4, "window 3 restored first")
        #expect(ws.width(ofColumn: 1) == 0.3, "window 1 restored second")
        #expect(ws.width(ofColumn: 2) == 0.6, "window 2 restored third")
    }

    @Test func `Pinned column widths are still preserved through depart and arrive`() {
        var ws = strip(3, width: 0.5)
        // Pin the first column and give it a custom width
        _ = ws.pin(.left, window: 1)
        ws.setWidth(ofColumn: 0, 0.3)
        #expect(ws.pins[.left] == 1)

        // Minimize the pinned window
        ws.depart(1)
        #expect(!ws.contains(1))

        // Restore it - should come back pinned with custom width
        ws.arrive(1)
        #expect(ws.contains(1))
        #expect(ws.pins[.left] == 1)
        #expect(ws.width(ofColumn: 0) == 0.3, "pinned column keeps its custom width")
    }

    @Test func `A window that closes while away leaves no width for another window with its id`() {
        var ws = strip(3, width: 0.5)
        ws.setWidth(ofColumn: 1, 0.3)

        ws.depart(2)
        #expect(ws.departedColumnWidths[2] == 0.3)
        #expect(ws.remembersDeparted(2))

        // Closed while minimized: the window is gone for good.
        ws.forgetPinned(2)
        #expect(ws.departedColumnWidths[2] == nil)
        #expect(!ws.remembersDeparted(2))

        // Its id comes back as another window's, at the default width.
        ws.insert(2)
        let column = ws.root.path(of: 2)![0]
        #expect(ws.width(ofColumn: column) == 0.5)
    }

    @Test func `A window removed from the tree does not keep its width`() {
        var ws = strip(3, width: 0.5)
        ws.setWidth(ofColumn: 1, 0.3)

        ws.remove(2)
        #expect(ws.departedColumnWidths[2] == nil)
        #expect(!ws.remembersDeparted(2))
    }

    @Test func `Cycle-size width changes are preserved through minimize`() {
        var ws = strip(2, width: 0.5)
        // Simulate cycle-size changing the width
        _ = ws.cycleWidth(through: [0.3, 0.6, 0.8])
        let customWidth = ws.width(ofColumn: 1)
        #expect(customWidth != 0.5, "width changed from default")

        // Minimize and restore
        ws.depart(2)
        ws.arrive(2)

        // Width should be preserved
        #expect(ws.width(ofColumn: 1) == customWidth)
    }

    @Test func `Resize operations are preserved through minimize`() {
        var ws = strip(2, width: 0.5)
        // Simulate resize command adjusting width
        let oldWidth = ws.width(ofColumn: 1)
        let delta = CGFloat(50) // 50 points
        let shareWidth = ws.stripInset.width
        let newWidth = oldWidth + Double(delta / shareWidth)
        ws.setWidth(ofColumn: 1, newWidth)

        // Minimize and restore
        ws.depart(2)
        ws.arrive(2)

        // Adjusted width should be preserved
        #expect(ws.width(ofColumn: 1) == newWidth)
    }
}
