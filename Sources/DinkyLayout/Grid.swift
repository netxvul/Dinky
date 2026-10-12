import CoreGraphics

/// Cells of a grid laid over a display, as yabai's `--grid rows:cols:start-x:start-y:width:height`: the grid has
/// `rows` by `columns` equal cells, and the window takes `width` by `height` of them from the cell at column `x`,
/// row `y`, counted from 0 at the top left.
public struct GridPlacement: Equatable, Sendable, CustomStringConvertible {
    public let rows: Int
    public let columns: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    /// Nil unless the grid has at least one cell and the span lies inside it.
    public init?(rows: Int, columns: Int, x: Int, y: Int, width: Int, height: Int) {
        guard rows >= 1, columns >= 1, x >= 0, y >= 0, width >= 1, height >= 1,
              x + width <= columns, y + height <= rows else { return nil }
        (self.rows, self.columns, self.x, self.y, self.width, self.height) = (rows, columns, x, y, width, height)
    }

    /// The `rows:columns:x:y:width:height` form it is written in.
    public var description: String { "\(rows):\(columns):\(x):\(y):\(width):\(height)" }

    /// The frame the span takes in `area`, inside the outer gaps, with the inner gaps between cells as tiles have
    /// them, so a window placed on a grid lines up with tiles of the same size. Edges rounded to whole points.
    /// Top-left origin, as AX uses.
    public func frame(in area: CGRect, gaps: Gaps) -> CGRect {
        let inner = gaps.inset(area)
        let (minX, maxX) = span(from: inner.minX, extent: inner.width, cells: columns, gap: gaps.horizontal, at: x, count: width)
        let (minY, maxY) = span(from: inner.minY, extent: inner.height, cells: rows, gap: gaps.vertical, at: y, count: height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func span(from origin: CGFloat, extent: CGFloat, cells: Int, gap: CGFloat, at start: Int, count: Int)
        -> (CGFloat, CGFloat) {
        let cell = max(0, extent - gap * CGFloat(cells - 1)) / CGFloat(cells)
        let a = origin + CGFloat(start) * (cell + gap)
        let b = a + CGFloat(count) * cell + CGFloat(count - 1) * gap
        return (a.rounded(), b.rounded())
    }
}
