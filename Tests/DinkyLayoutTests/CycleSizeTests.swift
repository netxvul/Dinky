import CoreGraphics
import Testing
@testable import DinkyLayout

private let sizes = [0.5, 0.3, 0.6]

struct CycleSizeTests {
    @Test func `The next size after the current one, wrapping`() {
        #expect(SizeCycle.next(after: 0.5, in: sizes) == 0.3)
        #expect(SizeCycle.next(after: 0.3, in: sizes) == 0.6)
        #expect(SizeCycle.next(after: 0.6, in: sizes) == 0.5)
        #expect(SizeCycle.next(after: 0.51, in: sizes) == 0.3, "close enough counts")
    }

    @Test func `The first size when at none of them`() {
        #expect(SizeCycle.next(after: 0.4, in: sizes) == 0.5)
        #expect(SizeCycle.next(after: 1, in: sizes) == 0.5)
    }

    @Test func `A floating frame is centred at the share`() {
        let area = rect(10, 30, 1000, 600)
        #expect(FloatingFrame.centered(0.5, in: area) == rect(260, 180, 500, 300))
        #expect(FloatingFrame.centered(0.3, in: area) == rect(360, 240, 300, 180))
        #expect(FloatingFrame.centered(1, in: area) == area)
    }

    @Test func `A tile steps through the widths`() {
        var ws = workspace(2)
        #expect(shape(ws.root) == "h[1 2]")
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(ws.layout().frames[2]!.width == 300)
        #expect(ws.layout().frames[1]!.width == 700)
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(ws.layout().frames[2]!.width == 600)
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(ws.layout().frames[2]!.width == 500)
    }

    @Test func `A tile in a stack sizes its column`() {
        var ws = workspace(3)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(ws.layout().frames[2]!.width == 300)
        #expect(ws.layout().frames[3]!.width == 300)
        #expect(ws.layout().frames[3]!.height == 300, "heights stay")
    }

    @Test func `A tile's width counts the gaps`() {
        var ws = workspace(2, gaps: Gaps(all: 10))
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(abs(ws.layout().frames[2]!.width - 294) <= 1, "30% of the 980 points inside the outer gaps")
    }

    @Test func `A tile with no neighbour beside it does nothing`() {
        var lone = workspace(1)
        #expect(lone.cycleWidth(through: sizes) == false)
        var stacked = workspace(2)
        stacked.setOrientation(.vertical)
        #expect(shape(stacked.root) == "v[1 2]")
        #expect(stacked.cycleWidth(through: sizes) == false)
    }

    @Test func `A scrolling column steps through the widths`() {
        var ws = Workspace(bounds: rect(-Workspace.peek, 0, 1000 + 2 * Workspace.peek, 600), gaps: .zero, algorithm: .scrolling)
        for id in 1...2 { ws.insert(WindowID(id)) }
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(ws.tiledLayout().frames[2]!.width == 300)
        #expect(ws.tiledLayout().frames[1]!.width == 500)
        #expect(ws.cycleWidth(through: sizes) == true)
        #expect(ws.tiledLayout().frames[2]!.width == 600)
    }

    @Test func `A lone scrolling column keeps filling the screen`() {
        var ws = Workspace(bounds: rect(0, 0, 1000, 600), gaps: .zero, algorithm: .scrolling)
        ws.insert(1)
        #expect(ws.cycleWidth(through: sizes) == false)
        #expect(ws.width(ofColumn: 0) == ws.columnWidth)
    }
}
