import CoreGraphics
import Testing
@testable import DinkyLayout

private let area = rect(0, 0, 1200, 600)

private func grid(_ rows: Int, _ columns: Int, _ x: Int, _ y: Int, _ width: Int, _ height: Int) -> GridPlacement {
    GridPlacement(rows: rows, columns: columns, x: x, y: y, width: width, height: height)!
}

struct GridTests {
    @Test func `Whole grid fills the area inside the outer gaps`() {
        #expect(grid(1, 1, 0, 0, 1, 1).frame(in: area, gaps: .zero) == area)
        #expect(grid(2, 3, 0, 0, 3, 2).frame(in: area, gaps: Gaps(all: 10)) == rect(10, 10, 1180, 580))
    }

    @Test func `Halves and quarters without gaps`() {
        #expect(grid(1, 2, 0, 0, 1, 1).frame(in: area, gaps: .zero) == rect(0, 0, 600, 600))
        #expect(grid(1, 2, 1, 0, 1, 1).frame(in: area, gaps: .zero) == rect(600, 0, 600, 600))
        #expect(grid(2, 2, 1, 1, 1, 1).frame(in: area, gaps: .zero) == rect(600, 300, 600, 300))
    }

    @Test func `Cells keep the inner gaps between them, as tiles do`() {
        let gaps = Gaps(all: 10)
        // Inside: 1180 x 580. Two columns of 585 with 10 between.
        #expect(grid(1, 2, 0, 0, 1, 1).frame(in: area, gaps: gaps) == rect(10, 10, 585, 580))
        #expect(grid(1, 2, 1, 0, 1, 1).frame(in: area, gaps: gaps) == rect(605, 10, 585, 580))
        // The same as the tiles of two windows side by side.
        let tiles = workspace(2, bounds: area, gaps: gaps).layout().frames
        #expect(grid(1, 2, 0, 0, 1, 1).frame(in: area, gaps: gaps) == tiles[1])
        #expect(grid(1, 2, 1, 0, 1, 1).frame(in: area, gaps: gaps) == tiles[2])
    }

    @Test func `A span covers the gaps inside it`() {
        let gaps = Gaps(all: 10)
        // Three columns of 386.67 with 10 between: two of them and the gap is 783.33.
        let frame = grid(1, 3, 0, 0, 2, 1).frame(in: area, gaps: gaps)
        #expect(frame == rect(10, 10, 783, 580))
        #expect(grid(3, 3, 1, 1, 1, 1).frame(in: area, gaps: .zero) == rect(400, 200, 400, 200))
    }

    @Test func `The area's origin carries over`() {
        let display = rect(1440, 25, 1200, 600)
        #expect(grid(2, 2, 1, 0, 1, 1).frame(in: display, gaps: .zero) == rect(2040, 25, 600, 300))
    }

    @Test(arguments: [(0, 1, 0, 0, 1, 1), (1, 0, 0, 0, 1, 1), (2, 2, 2, 0, 1, 1), (2, 2, 1, 0, 2, 1),
                      (2, 2, 0, 1, 1, 2), (2, 2, 0, 0, 0, 1), (2, 2, -1, 0, 1, 1)])
    func `Spans outside the grid are refused`(placement: (Int, Int, Int, Int, Int, Int)) {
        let (rows, columns, x, y, width, height) = placement
        #expect(GridPlacement(rows: rows, columns: columns, x: x, y: y, width: width, height: height) == nil)
    }

    @Test func `Written as rows:columns:x:y:width:height`() {
        #expect(grid(3, 4, 1, 2, 3, 1).description == "3:4:1:2:3:1")
    }
}
