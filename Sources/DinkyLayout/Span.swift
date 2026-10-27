import CoreGraphics

// A strip across two displays side by side (`[scrolling] span-displays`): one row of columns whose bounds are both
// displays' visible areas, the line where they meet the seam. Columns keep shares of one display's width, the narrower
// one's, so none is ever wider than a display, and a lone column fills only the display it is on.
//
// Each display shows its own Space, so nothing shows across the seam: where the strip comes to rest the seam falls
// between two columns, half an inner gap of each beside it, or beside an end column, the outer gap. `seamAligned` picks
// the resting offset nearest the one the strip would have otherwise that does so, the focused column whole. Unlike a
// wall (Scrolling.swift), the seam parks nothing: a column scrolling over it goes on to the other display, and only the
// outer edges of the two park and peek. A column is as tall as the display its middle is on.

/// The two displays a strip runs across, as their visible areas, top-left origin.
public struct Seam: Equatable, Sendable {
    public var left: CGRect
    public var right: CGRect

    public init(left: CGRect, right: CGRect) {
        self.left = left
        self.right = right
    }

    /// Where the displays meet.
    public var x: CGFloat { left.maxX }

    /// Both visible areas together: the bounds of a strip across them.
    public var bounds: CGRect { left.union(right) }
}

extension Workspace {
    /// Where the seam is, while the strip runs across two displays and lays out as a strip; nil otherwise.
    var seamLine: CGFloat? { isScrolling ? seam?.x : nil }

    /// Whether the strip runs across two displays.
    public var spansDisplays: Bool { seamLine != nil }

    /// Runs the strip across `seam`'s displays, its bounds both of them. Nil runs it on one display again, whose bounds
    /// the caller sets.
    public mutating func setSeam(_ seam: Seam?) {
        self.seam = seam
        if let seam { bounds = seam.bounds }
    }

    /// The width a column's share is of in `area`: across a seam, the narrower display's part of it, so no column grows
    /// wider than a display; on one display, all of it.
    func shareBase(of area: CGRect) -> CGFloat {
        guard let x = seamLine else { return area.width }
        return max(min(x - area.minX, area.maxX - x), 0)
    }

    /// The width inside the outer gaps a pin's share is of: the narrower display's across a seam.
    var screenWidth: CGFloat { shareBase(of: gaps.inset(bounds)) }

    /// The area inside the outer gaps of the display `x` is on: `bounds`' on one display.
    func displayInset(at x: CGFloat) -> CGRect {
        guard let seam, isScrolling else { return gaps.inset(bounds) }
        return gaps.inset(x < seam.x ? seam.left : seam.right)
    }

    /// `rect` as tall as the display its middle is on, inside the outer gaps there; as it is on one display.
    func onDisplay(_ rect: CGRect) -> CGRect {
        guard seamLine != nil else { return rect }
        let inset = displayInset(at: rect.midX)
        return CGRect(x: rect.minX, y: inset.minY, width: rect.width, height: inset.height)
    }

    /// The offsets that put a boundary between band columns on the seam, each with the boundary: band column k's start,
    /// the band's upper bound its end. Between two columns, half an inner gap of each either side of the seam; at the
    /// band's first or last column, half an inner gap all the same, as if the other display's column were beside it.
    /// None on one display.
    func seamOffsets(spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> [(boundary: Int, offset: CGFloat)] {
        let band = bandRange, beside = bandNeighbours
        guard let x = seamLine, !band.isEmpty else { return [] }
        let line = x - area.minX, half = gaps.horizontal / 2
        return (band.lowerBound...band.upperBound).map { k in
            if k == band.upperBound { return (k, bandEnd(of: spans) - line + (beside.right ? 0 : half)) }
            return (k, spans[k].start - line - (k == band.lowerBound && !beside.left ? half : 0))
        }
    }

    /// Whether band column `i` shows whole at offset `c`: within `area`, at an end of the strip into the gutter there.
    func showsWhole(_ i: Int, at c: CGFloat, spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> Bool {
        let slack: CGFloat = 1.5, gutters = endGutters(of: i, area), minX = area.minX + spans[i].start - c
        return minX >= area.minX - gutters.left - slack && minX + spans[i].width <= area.maxX + gutters.right + slack
    }

    /// Whether the band fits across the seam without scrolling: some offset with a boundary on the seam
    /// (`seamOffsets`) shows every column whole. Always on one display.
    func fitsAcrossSeam(spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> Bool {
        guard seamLine != nil else { return true }
        let band = bandRange
        return seamOffsets(spans: spans, in: area).contains { c in
            band.allSatisfy { showsWhole($0, at: c.offset, spans: spans, in: area) }
        }
    }

    /// The resting offset nearest `offset` with the seam between columns (`seamOffsets`) and the band column that must
    /// show (`shownBandColumn`) whole. With `inside`, as for a strip that fits, one showing every band column whole
    /// where any does. `offset` itself where none will do, on one display, or with no band column to show.
    func seamAligned(_ offset: CGFloat, spans: [(start: CGFloat, width: CGFloat)], in area: CGRect,
                     inside: Bool = false) -> CGFloat {
        guard seamLine != nil, let focusedColumn = shownBandColumn else { return offset }
        let band = bandRange
        let shown = seamOffsets(spans: spans, in: area).map(\.offset)
            .filter { showsWhole(focusedColumn, at: $0, spans: spans, in: area) }
        let all = inside ? shown.filter { c in band.allSatisfy { showsWhole($0, at: c, spans: spans, in: area) } } : []
        return (all.isEmpty ? shown : all).min { (abs($0 - offset), $0) < (abs($1 - offset), $1) } ?? offset
    }

    /// The offset that puts `column` in the middle of the display it shows on at `offset`: across a seam, whose middle
    /// is the seam, the middle of that display's part of `area`; on one display, of all of it.
    func centredOnDisplay(_ column: (start: CGFloat, width: CGFloat), from offset: CGFloat, in area: CGRect) -> CGFloat {
        guard let x = seamLine else { return centred(column, in: area) }
        let middle = area.minX + column.start + column.width / 2 - offset
        let (from, to) = middle < x ? (area.minX, x) : (x, area.maxX)
        return (column.start + column.width / 2 - ((from + to) / 2 - area.minX)).rounded()
    }

    /// The display a window at `frame` belongs on across the seam: left of it (true) where most of it is left of it.
    /// Nil on one display.
    public func isLeftOfSeam(_ frame: CGRect) -> Bool? {
        guard let x = seamLine else { return nil }
        return frame.midX < x
    }

    /// `other`'s columns after this strip's band, at their widths, as the strip of the display right of this one's comes
    /// to run across the seam with it: lined up so the seam falls between the two, focus kept here, or with none here,
    /// taken from `other`. Pins of `other` come as band columns.
    public mutating func takeColumns(of other: Workspace) {
        guard isScrolling else { return }
        let boundary = bandRange.upperBound
        var at = boundary
        for (i, column) in other.root.children.enumerated() {
            root.insert(column, at: at)
            at += 1
            let share = other.isScrolling ? other.width(ofColumn: i) : columnWidth
            for id in column.windows { columnWidths[id] = share }
        }
        minimumSizes.merge(other.minimumSizes) { mine, _ in mine }
        observedWidths.merge(other.observedWidths) { mine, _ in mine }
        untuckable.formUnion(other.untuckable)
        normalize()
        if focused == nil, let id = other.focused ?? windows.first { focus(id) }
        let area = stripArea, spans = columnSpans(in: area)
        if let between = seamOffsets(spans: spans, in: area).first(where: { $0.boundary == boundary }) {
            scrollOffset = between.offset
        }
    }
}
