import CoreGraphics
import Testing
@testable import DinkyLayout

/// Three windows in 1000x600: 1 on the left, 2 above 3 on the right.
private func three() -> Workspace { workspace(3) }

struct RotateTests {
    @Test func `A quarter turn makes the row a column and the column a reversed row`() {
        var ws = three()
        let changed1 = ws.rotate(.quarter)
        #expect(changed1)
        #expect(shape(ws.root) == "v[1 h[3 2]]")
    }

    @Test func `A half turn reverses everything`() {
        var ws = three()
        let changed2 = ws.rotate(.half)
        #expect(changed2)
        #expect(shape(ws.root) == "h[v[3 2] 1]")
    }

    @Test func `Three quarters turns the other way`() {
        var ws = three()
        let changed3 = ws.rotate(.threeQuarters)
        #expect(changed3)
        #expect(shape(ws.root) == "v[h[2 3] 1]")
    }

    @Test func `Four quarter turns come back`() {
        var ws = three()
        let before = ws.root
        for _ in 0..<4 { ws.rotate(.quarter) }
        #expect(ws.root == before)
    }

    @Test func `Two half turns come back`() {
        var ws = three()
        let before = ws.root
        ws.rotate(.half)
        ws.rotate(.half)
        #expect(ws.root == before)
    }

    @Test func `A quarter and three quarters come back`() {
        var ws = three()
        let before = ws.root
        ws.rotate(.quarter)
        ws.rotate(.threeQuarters)
        #expect(ws.root == before)
    }

    @Test func `Ratios move with their windows`() {
        var ws = three()
        ws.focus(1)
        let changed4 = ws.resize(by: 100)
        #expect(changed4)
        let ratios = ws.root.ratios
        let changed5 = ws.rotate(.half)
        #expect(changed5)
        assertRatios(ws.root.ratios, ratios.reversed())
        #expect(ws.focused == 1)
    }

    @Test func `The y-axis swaps left and right`() {
        var ws = three()
        let changed6 = ws.mirror(.yAxis)
        #expect(changed6)
        #expect(shape(ws.root) == "h[v[2 3] 1]")
    }

    @Test func `The x-axis swaps top and bottom`() {
        var ws = three()
        let changed7 = ws.mirror(.xAxis)
        #expect(changed7)
        #expect(shape(ws.root) == "h[1 v[3 2]]")
    }

    @Test func `Mirroring twice comes back`() {
        var ws = three()
        let before = ws.root
        ws.mirror(.yAxis)
        ws.mirror(.yAxis)
        ws.mirror(.xAxis)
        ws.mirror(.xAxis)
        #expect(ws.root == before)
    }

    @Test func `Nothing runs across the axis`() {
        var ws = workspace(2)
        #expect(shape(ws.root) == "h[1 2]")
        let changed8 = ws.mirror(.xAxis)
        #expect(!changed8)
        #expect(shape(ws.root) == "h[1 2]")
    }

    @Test func `An accordion keeps its mode`() {
        var ws = workspace(3, algorithm: .dwindle(.accordion))
        #expect(shape(ws.root) == "ah[1 2 3]")
        let changed9 = ws.rotate(.quarter)
        #expect(changed9)
        #expect(shape(ws.root) == "av[1 2 3]")
        let changed10 = ws.mirror(.xAxis)
        #expect(changed10)
        #expect(shape(ws.root) == "av[3 2 1]")
    }

    @Test func `A lone window and an empty workspace have nothing to turn`() {
        var one = workspace(1)
        let changed11 = one.rotate(.quarter)
        #expect(!changed11)
        let changed12 = one.mirror(.yAxis)
        #expect(!changed12)
        var none = workspace(0)
        let changed13 = none.rotate(.half)
        #expect(!changed13)
    }

    @Test func `Fixed and scrolling layouts refuse`() {
        var fixed = workspace(4, algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        #expect(!fixed.rearranges)
        let changed14 = fixed.rotate(.quarter)
        #expect(!changed14)
        var strip = workspace(3, algorithm: .scrolling)
        #expect(!strip.rearranges)
        let changed15 = strip.mirror(.yAxis)
        #expect(!changed15)
        #expect(three().rearranges)
    }

    @Test func `A turn ends fullscreen`() {
        var ws = three()
        ws.focus(2)
        ws.toggleFullscreen()
        let changed16 = ws.rotate(.quarter)
        #expect(changed16)
        #expect(ws.fullscreenWindows.isEmpty)
        #expect(ws.focused == 2)
    }
}
