import CoreGraphics
import Testing
@testable import DinkyLayout

struct InsertTests {
    @Test func `First window fills root`() {
        let ws = workspace(1)
        #expect(shape(ws.root) == "h[1]")
        #expect(ws.focused == 1)
    }

    @Test func `Wide leaf splits side by side`() {
        #expect(shape(workspace(2).root) == "h[1 2]")
    }

    @Test func `Tall leaf splits top and bottom`() {
        #expect(shape(workspace(2, bounds: rect(0, 0, 600, 1000)).root) == "v[1 2]")
    }

    @Test func `Square leaf splits side by side`() {
        #expect(shape(workspace(2, bounds: rect(0, 0, 800, 800)).root) == "h[1 2]")
    }

    @Test func `Alternating splits nest`() {
        #expect(shape(workspace(5).root) == "h[1 v[2 h[3 v[4 5]]]]")
    }

    @Test func `Matching orientation inserts as sibling`() {
        // 1000x500 halves are square, so the third window splits side by side like its parent.
        #expect(shape(workspace(3, bounds: rect(0, 0, 1000, 500)).root) == "h[1 2 3]")
    }

    @Test func `New window goes after focused`() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.insert(4)
        #expect(shape(ws.root) == "h[1 4 2 3]")
        #expect(ws.focused == 4)
    }

    @Test func `Insert splits fifty fifty`() {
        assertRatios(workspace(2).root.ratios, [0.5, 0.5])
    }

    @Test func `Sibling insert divides ratios proportionally`() {
        var ws = workspace(2, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.resize(by: 300) // [0.6, 0.4]
        ws.insert(3)
        assertRatios(ws.root.ratios, [0.4, 1.0 / 3, 0.4 * 2 / 3])
    }

    @Test func `Insert into accordion is always a sibling`() {
        var ws = workspace(2, algorithm: .dwindle(.accordion))
        ws.insert(3)
        #expect(shape(ws.root) == "ah[1 2 3]")
    }

    @Test func `Inserting known window is ignored`() {
        var ws = workspace(2)
        ws.insert(1)
        #expect(shape(ws.root) == "h[1 2]")
    }
}

struct FixedLayoutTests {
    @Test func `Empty cells keep their frames`() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 3, columns: 2, expand: .columns))
        ws.insert(1)
        #expect(ws.layout().frames[1] == rect(0, 0, 600, 300))
        #expect(ws.edgeWindow(.right) == 1, "an empty boundary column must not hide occupied cells")
        #expect(ws.edgeWindow(.down) == 1)
        for id in 2...5 { ws.insert(WindowID(id)) }
        #expect(ws.windows.count == 5)
        #expect(ws.layout().frames[5] == rect(0, 600, 600, 300))
        #expect(ws.layout().frames.count == 5)
        ws.insert(6)
        #expect(ws.layout().frames[6] == rect(600, 600, 600, 300))
        ws.remove(2)
        #expect(ws.layout().frames[1] == rect(0, 0, 600, 300))
        #expect(ws.layout().frames[6] == rect(600, 600, 600, 300))
        ws.insert(7)
        #expect(ws.layout().frames[7] == rect(600, 0, 600, 300))
    }

    @Test func `Default one by one and column expansion`() {
        var ws = Workspace(bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 1, expand: .columns))
        ws.insert(1)
        #expect(ws.layout().frames[1] == rect(0, 0, 1200, 900))
        ws.insert(2)
        #expect(ws.layout().frames[1] == rect(0, 0, 600, 900))
        #expect(ws.layout().frames[2] == rect(600, 0, 600, 900))
        ws.remove(2)
        #expect(ws.layout().frames[1] == rect(0, 0, 1200, 900))
        ws.remove(1)
        ws.insert(3)
        #expect(ws.layout().frames[3] == rect(0, 0, 1200, 900))
    }

    @Test func `Row expansion and accordion overflow`() {
        var rows = workspace(3, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .rows))
        #expect(rows.layout().frames[3] == rect(0, 450, 600, 450))
        rows.remove(3)
        #expect(rows.layout().frames[1] == rect(0, 0, 600, 900))

        var stacked = workspace(8, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 3, columns: 2, expand: .accordion))
        #expect(stacked.windows.count == 8)
        #expect(stacked.container(of: 7)?.mode == .accordion)
        #expect(stacked.container(of: 8)?.mode == .accordion)
        stacked.remove(7)
        #expect(stacked.contains(8))
        stacked.remove(8)
        stacked.remove(6)
        stacked.insert(9)
        #expect(stacked.layout().frames[9] == rect(600, 600, 600, 300))
    }

    @Test func `Manual resize survives filling a hole`() {
        var ws = workspace(1, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        ws.focus(1)
        #expect(ws.resize(by: 120, along: .horizontal) == true)
        let widths = ws.root.ratios
        ws.insert(2)
        assertRatios(ws.root.ratios, widths)
    }

    @Test func `Resizing next to an empty cell uses the whole column`() {
        var ws = workspace(3, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        ws.focus(2)
        #expect(ws.rect(at: [1], in: ws.tiledLayout()) == rect(600, 0, 600, 900))
        #expect(ws.resize(by: 150) == true)
        #expect(ws.layout().frames[2] == rect(600, 0, 600, 600))
        #expect(ws.resize(2, to: CGSize(width: 600, height: 300), moving: [.down]) == true)
        #expect(ws.layout().frames[2] == rect(600, 0, 600, 300))
    }

    @Test func `Changing template keeps focus`() {
        var ws = workspace(4)
        ws.focus(1)
        ws.setAlgorithm(.fixed(rows: 3, columns: 2, expand: .columns))
        #expect(ws.focused == 1)
        #expect(ws.layout().frames[4] == rect(500, 200, 500, 200))
        ws.setAlgorithm(.dwindle(.accordion))
        #expect(ws.windows.count == 4)
        #expect(ws.root.mode == .accordion)
        #expect(ws.focused == 1)
    }

    @Test func `Changing dwindle to accordion reconfigures existing windows`() {
        var ws = workspace(3)
        ws.setAlgorithm(.dwindle(.accordion))
        #expect(ws.root.mode == .accordion)
        #expect(ws.windows.count == 3)
        ws.setAlgorithm(.dwindle(.tiles))
        #expect(ws.root.mode == .tiles)
    }

    @Test func `Move swaps cells and can fill a hole without breaking the template`() {
        var ws = workspace(2, bounds: rect(0, 0, 900, 600), algorithm: .fixed(rows: 2, columns: 3, expand: .columns))
        ws.focus(2)
        #expect(ws.move(.left) == true)
        #expect(ws.layout().frames[2] == rect(0, 0, 300, 300))
        #expect(ws.layout().frames[1] == rect(300, 0, 300, 300))
        #expect(ws.move(.down) == true)
        #expect(ws.layout().frames[2] == rect(0, 300, 300, 300))
        ws.insert(3)
        #expect(ws.layout().frames[3] == rect(0, 0, 300, 300))
    }

    @Test func `Empty edited tree restores the fixed template`() {
        var ws = workspace(1, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 3, columns: 2, expand: .columns))
        ws.setMode(.accordion)
        #expect(!ws.isFixedTree)
        ws.remove(1)
        ws.insert(2)
        #expect(ws.layout().frames[2] == rect(0, 0, 600, 300))
    }

    @Test func `A layout command that changes nothing keeps the template and its empty cells`() {
        var ws = workspace(3, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        ws.focus(1)
        let before = ws.layout().frames
        ws.setLayout(.tiles, .vertical) // the column 1 sits in already is vertical tiles
        #expect(ws.isFixedTree)
        #expect(ws.layout().frames == before)
        ws.insert(4)
        #expect(ws.layout().frames[4] == rect(600, 450, 600, 450), "the reserved cell is still there")
    }

    @Test func `Reorienting the overflow accordion keeps the template`() {
        var ws = workspace(4, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .accordion))
        ws.focus(3)
        ws.setLayout(.accordion, .vertical)
        #expect(shape(ws.root) == "h[v[1] v[av[2 3 4]]]")
        #expect(ws.isFixedTree)
        ws.insert(5)
        #expect(ws.container(of: 5)?.mode == .accordion)
        #expect(ws.layout().frames[1] == rect(0, 0, 600, 900))
    }

    @Test func `Moving out of overflow reclaims empty row`() {
        var ws = workspace(3, bounds: rect(0, 0, 1200, 900), algorithm: .fixed(rows: 1, columns: 2, expand: .rows))
        ws.remove(2)
        ws.focus(3)
        #expect(ws.move(.right) == true)
        #expect(ws.move(.up) == true)
        #expect(ws.layout().frames[1] == rect(0, 0, 600, 900))
        #expect(ws.layout().frames[3] == rect(600, 0, 600, 900))
    }
}

struct RemoveTests {
    @Test func `Remove redistributes proportionally`() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(1)
        ws.resize(by: 500) // 1 grows to 1/3 + 1/6
        ws.remove(3)
        assertRatios(ws.root.ratios, [0.5 / (0.5 + 0.25), 0.25 / (0.5 + 0.25)])
    }

    @Test func `Remove collapses single child container`() {
        var ws = workspace(3)
        ws.remove(2)
        #expect(shape(ws.root) == "h[1 3]")
        assertRatios(ws.root.ratios, [0.5, 0.5])
    }

    @Test func `Remove splices same orientation container keeping order`() {
        var ws = workspace(4) // h[1 v[2 h[3 4]]]
        ws.remove(2)
        #expect(shape(ws.root) == "h[1 3 4]")
        assertRatios(ws.root.ratios, [0.5, 0.25, 0.25])
    }

    @Test func `Remove unwraps root`() {
        var ws = workspace(3) // h[1 v[2 3]]
        ws.remove(1)
        #expect(shape(ws.root) == "v[2 3]")
    }

    @Test func `Remove last window leaves empty root`() {
        var ws = workspace(1)
        ws.remove(1)
        #expect(ws.windows == [])
        #expect(ws.focused == nil)
    }

    @Test func `Removing focused focuses window in its place`() {
        var ws = workspace(3, bounds: rect(0, 0, 3000, 500))
        ws.focus(2)
        ws.remove(2)
        #expect(ws.focused == 3)
    }

    @Test func `Removing other window keeps focus`() {
        var ws = workspace(3)
        ws.remove(1)
        #expect(ws.focused == 3)
    }
}

struct FlattenAndModeTests {
    @Test func `Flatten collapses to one container`() {
        var ws = workspace(5)
        ws.flatten()
        #expect(shape(ws.root) == "h[1 2 3 4 5]")
        assertRatios(ws.root.ratios, Array(repeating: 0.2, count: 5))
        #expect(ws.focused == 5)
    }

    @Test func `Flatten restores the configured accordion`() {
        var ws = workspace(3, algorithm: .dwindle(.accordion))
        ws.focus(2)
        ws.setMode(.tiles)
        ws.join(.right)
        ws.flatten()
        #expect(shape(ws.root) == "ah[1 2 3]")
        #expect(ws.focused == 2)
    }

    @Test func `Flatten restores the fixed template`() {
        var ws = workspace(3, bounds: rect(0, 0, 1200, 600), algorithm: .fixed(rows: 1, columns: 3, expand: .columns))
        ws.focus(3)
        ws.join(.left)
        #expect(!ws.isFixedTree)
        ws.flatten()
        #expect(ws.isFixedTree)
        #expect(ws.layout().frames[1] == rect(0, 0, 400, 600))
        #expect(ws.layout().frames[3] == rect(800, 0, 400, 600))
        #expect(ws.focused == 3)
    }

    @Test func `Set mode changes focused parent`() {
        var ws = workspace(3)
        ws.setMode(.accordion)
        #expect(shape(ws.root) == "h[1 av[2 3]]")
    }
}

struct ReplaceTests {
    @Test func `Replace keeps place size and focus`() {
        var ws = workspace(3)
        ws.focus(2)
        ws.toggleFullscreen()
        let before = ws.layout()
        ws.replace(2, with: 9)
        #expect(shape(ws.root) == "h[1 v[9 3]]")
        #expect(ws.focused == 9)
        #expect(ws.fullscreen == 9)
        #expect(ws.layout().frames[9] == before.frames[2])
    }

    @Test func `Replace ignores missing or present windows`() {
        var ws = workspace(2)
        ws.replace(7, with: 9)
        ws.replace(1, with: 2)
        #expect(shape(ws.root) == "h[1 2]")
    }
}
