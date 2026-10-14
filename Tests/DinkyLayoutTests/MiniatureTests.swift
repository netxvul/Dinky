import CoreGraphics
import Testing
@testable import DinkyLayout

struct MiniatureTests {
    private let screen = rect(0, 0, 1000, 600)

    @Test func `A tree's windows are drawn where they are, scaled to the card`() {
        let mini = Miniature(screen: screen, height: 60, workspace: workspace(3))
        #expect(mini.size == CGSize(width: 100, height: 60))
        #expect(mini.tiles.count == 3)
        #expect(mini.tiles.first { $0.id == 1 }?.frame == rect(1, 1, 48, 58))
        #expect(mini.tiles.allSatisfy { !$0.behind })
        #expect(mini.tiles.filter { $0.id != 1 }.allSatisfy { $0.frame.minX >= 50 })
    }

    @Test func `The card keeps the display's proportions`() {
        let mini = Miniature(screen: rect(0, 0, 2560, 1440), height: 90, workspace: nil)
        #expect(mini.size == CGSize(width: 160, height: 90))
        #expect(mini.tiles.isEmpty)
    }

    @Test func `An accordion's neighbours peek out far enough to see, behind the focused window`() {
        let mini = Miniature(screen: screen, height: 60, workspace: workspace(3, algorithm: .dwindle(.accordion), padding: 30))
        #expect(mini.tiles.last?.id == 3)
        #expect(mini.tiles.last?.behind == false)
        #expect(mini.tiles.dropLast().allSatisfy { $0.behind })
        // Padding of 30 is 3 points at this size; the minimum peek makes it 5.
        let lefts = mini.tiles.map(\.frame.minX)
        #expect(lefts.last! - lefts.min()! >= Miniature.minimumPeek)
    }

    @Test func `A strip shows the columns in view, pulled in, and counts the parked ones`() {
        var ws = Workspace(bounds: rect(-25, 0, 1050, 600), algorithm: .scrolling)
        ws.columnWidth = 0.5
        for id in 1...4 { ws.insert(WindowID(id)) }
        let mini = Miniature(screen: ws.bounds, height: 60, workspace: ws)
        #expect(mini.tiles.map(\.id) == [3, 4])
        #expect(mini.parkedLeft == 2)
        #expect(mini.parkedRight == 0)
        let inset = (mini.size.width * Miniature.parkedInset).rounded()
        #expect(mini.tiles.allSatisfy { $0.frame.minX >= inset && $0.frame.maxX <= mini.size.width - inset })
        #expect(mini.parkedSliver(left: true) != nil)
        #expect(mini.parkedSliver(left: false) == nil)
    }

    @Test func `A strip with every column in view is not pulled in`() {
        var ws = Workspace(bounds: screen, algorithm: .scrolling)
        ws.columnWidth = 0.5
        for id in 1...2 { ws.insert(WindowID(id)) }
        let mini = Miniature(screen: screen, height: 60, workspace: ws)
        #expect(mini.parkedLeft + mini.parkedRight == 0)
        // Only the gutter the strip itself keeps, far less than the inset for parked columns.
        #expect(mini.tiles.map(\.frame.minX).min()! < (mini.size.width * Miniature.parkedInset).rounded())
    }

    @Test func `A fixed workspace shows its empty cells`() {
        var ws = Workspace(bounds: screen, algorithm: .fixed(rows: 2, columns: 2, expand: .columns))
        for id in 1...3 { ws.insert(WindowID(id)) }
        let mini = Miniature(screen: screen, height: 60, workspace: ws)
        #expect(mini.tiles.count == 3)
        #expect(mini.emptyCells == [rect(51, 31, 48, 28)])
    }

    @Test func `A fullscreen window is shown alone`() {
        var ws = workspace(2)
        ws.toggleFullscreen()
        let mini = Miniature(screen: screen, height: 60, workspace: ws)
        #expect(mini.fullscreen)
        #expect(mini.tiles == [Miniature.Tile(id: 2, frame: rect(1, 1, 98, 58), behind: false)])
    }

    @Test func `Floating windows go on top, and unknown windows are left out`() {
        let mini = Miniature(screen: screen, height: 60, workspace: workspace(2), known: { $0 != 2 },
                             floating: [(id: 9, frame: rect(100, 100, 400, 300))])
        #expect(mini.tiles.map(\.id) == [1, 9])
        #expect(mini.tiles.last?.frame == rect(11, 11, 38, 28))
    }
}

struct WorkspaceSwitcherLayoutTests {
    // Two built-in cards and a 16:9 one on another display.
    private let layout = WorkspaceSwitcherLayout(groups: [[1.5, 1.5], [16.0 / 9]], cardHeight: 80, maxWidth: 2000)

    @Test func `Cards go in groups, each with its display's name over it`() {
        #expect(layout.frames == [rect(14, 32, 120, 80), rect(146, 32, 120, 80), rect(295, 32, 142, 80)])
        #expect(layout.headers == [rect(14, 14, 252, 18), rect(295, 14, 142, 18)])
        #expect(layout.dividers == [281])
        #expect(layout.labels[0] == rect(8, 112, 132, 20))
        #expect(layout.size == CGSize(width: 451, height: 146))
    }

    @Test func `One display has no names over its cards`() {
        let single = WorkspaceSwitcherLayout(groups: [[1.5, 1.5]], cardHeight: 80, maxWidth: 2000)
        #expect(single.headers.isEmpty)
        #expect(single.dividers.isEmpty)
        #expect(single.frames[0] == rect(14, 14, 120, 80))
        #expect(single.size.height == 128)
    }

    @Test func `A row too wide is scaled down to fit`() {
        let narrow = WorkspaceSwitcherLayout(groups: [[2], [2]], cardHeight: 100, maxWidth: 300)
        #expect(narrow.cardHeight == 60)
        #expect(narrow.frames.map(\.minX) == [14, 163])
        #expect(narrow.size.width == 297)
    }

    @Test func `The card under x reaches halfway into the gaps`() {
        #expect(layout.index(atX: 0) == 0)
        #expect(layout.index(atX: 139) == 0)
        #expect(layout.index(atX: 141) == 1)
        #expect(layout.index(atX: 280) == 1)
        #expect(layout.index(atX: 281) == 2)
        #expect(layout.index(atX: 9000) == 2)
    }

    @Test func `The capsule centres the anchor card on the pointer, inside the screen`() {
        let visible = rect(0, 25, 1512, 900)
        #expect(layout.origin(anchor: 1, pointer: CGPoint(x: 700, y: 500), visible: visible) == CGPoint(x: 494, y: 428))
        #expect(layout.origin(anchor: 0, pointer: CGPoint(x: 10, y: 30), visible: visible) == CGPoint(x: 8, y: 33))
    }
}

struct SchematicTests {
    private let screen = rect(0, 0, 1600, 1000)

    @Test func `Each layout has a fixed picture`() {
        let tiles = Miniature(schematic: .tiles(.horizontal), screen: screen, height: 100)
        #expect(tiles.size == CGSize(width: 160, height: 100))
        // A gap of 3 at the edges and between windows.
        #expect(tiles.tiles.map(\.frame) == [rect(3, 3, 76, 94), rect(82, 3, 75, 46), rect(82, 52, 75, 45)])
        let vertical = Miniature(schematic: .tiles(.vertical), screen: screen, height: 100)
        #expect(vertical.tiles[0].frame == rect(3, 3, 154, 46))
        let grid = Miniature(schematic: .fixed(rows: 2, columns: 2), screen: screen, height: 100)
        #expect(grid.tiles[1].frame.minX - grid.tiles[0].frame.maxX == Miniature.schematicGap)
        #expect(Miniature(schematic: .fixed(rows: 2, columns: 3), screen: screen, height: 100).tiles.count == 6)
        #expect(Miniature(schematic: .fixed(rows: 9, columns: 9), screen: screen, height: 100).tiles.count == 16)
        #expect(Miniature(schematic: .fullscreen, screen: screen, height: 100).tiles.count == 1)
        #expect(Miniature(schematic: .floating, screen: screen, height: 100).tiles.count == 3)
    }

    @Test func `An accordion's front window is last, its neighbours behind`() {
        let accordion = Miniature(schematic: .accordion(.horizontal), screen: screen, height: 100)
        #expect(accordion.tiles.map(\.behind) == [true, true, false])
        #expect(accordion.tiles[2].frame.minX - accordion.tiles[0].frame.minX >= Miniature.minimumPeek)
    }

    @Test func `A strip has a parked sliver either side and its columns pulled in`() {
        let strip = Miniature(schematic: .scrolling, screen: screen, height: 100)
        #expect(strip.parkedLeft == 1 && strip.parkedRight == 1)
        #expect(strip.tiles.allSatisfy { $0.frame.minX >= 16 && $0.frame.maxX <= 144 })
        let sliver = strip.schematicSliver(left: true)!
        #expect(strip.tiles[0].frame.minX - sliver.maxX >= Miniature.schematicGap)
    }
}
