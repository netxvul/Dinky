import CoreGraphics

// A strip across two displays side by side (`[scrolling] span-displays`): one row of columns whose bounds are both
// displays' visible areas, the line where they meet the seam. Columns keep shares of one display's width, the narrower
// one's, so none is ever wider than a display, and a lone column fills only the display it is on.
//
// Each display shows its own Space, so nothing shows across the seam: where the strip comes to rest the seam falls
// between two columns, half an inner gap of each beside it, or half a gap from an end column. `seamAligned` picks the
// resting offset nearest the one the strip would have otherwise that does so, the focused column whole. Centring
// (`columnCentring`) centres on both displays together, so the focused column comes to rest beside the seam, on the
// side nearer where the strip shows: centred on the display it is on, it would snap to that display's outer edge as
// often as to the seam, and the strip would scroll the other way from focus. `spanCentring` can name one display
// instead, the one under the pointer or the one the column is on: the column then rests whole on it as near its middle
// as the seam allows. Either way focus stepping along the strip never scrolls it back. Unlike a
// wall (Scrolling.swift), the seam parks nothing: a column scrolling over it goes on to the other display, and only the
// outer edges of the two park and peek. A column is as tall as the display its middle is on.

/// Which display focusing a column centres it on, across a seam (`Workspace.spanCentring`).
public enum SpanCentring: Equatable, Sendable {
    /// Both together: it rests beside the seam, on the side nearer where the strip shows.
    case both
    /// The display it is on as focus comes to it.
    case focused
    /// The left display (true) or the right one, as the one under the pointer.
    case display(left: Bool)
}

/// How tall the columns of a strip across two displays are (`Workspace.spanHeight`).
public enum SpanHeight: Equatable, Sendable {
    /// As the display a column's middle is on: it changes size as that crosses the seam.
    case perDisplay
    /// As high as both displays have room, everywhere, so nothing changes size crossing the seam.
    case overlap
    /// As the display a column's middle is on where it rests; while fingers or the mouse hold the strip, as where it
    /// was as they took hold, so nothing changes size till they let go.
    case atRest
}

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

    /// The scroll offset as set and the ends it is kept to, for `dinky debug-state`.
    public var scrollDebug: (offset: CGFloat, limits: ClosedRange<CGFloat>?) {
        let area = stripArea
        return (scrollOffset, heldLimits(for: columnSpans(in: area), in: area))
    }

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

    /// The area inside the outer gaps of the display `x` is on: `bounds`' on one display. With `spanHeight` `overlap`,
    /// only as high as both displays have room, inside both's outer gaps, where they have any.
    func displayInset(at x: CGFloat) -> CGRect {
        guard let seam, isScrolling else { return gaps.inset(bounds) }
        let inset = gaps.inset(x < seam.x ? seam.left : seam.right)
        guard spanHeight == .overlap else { return inset }
        let left = gaps.inset(seam.left), right = gaps.inset(seam.right)
        let top = max(left.minY, right.minY), bottom = min(left.maxY, right.maxY)
        return bottom > top ? CGRect(x: inset.minX, y: top, width: inset.width, height: bottom - top) : inset
    }

    /// `rect` as tall as the display it is on, inside the outer gaps there (`displayInset`): the one `anchor` is on, or
    /// its middle. With `spanHeight` `perDisplay`, a column whose middle comes within `seamLead` of the seam on the taller
    /// display already has the shorter one's height: macOS shows it there as its middle crosses, and an app slow to take
    /// a size has it by then. As it is on one display.
    func onDisplay(_ rect: CGRect, anchor: CGFloat? = nil) -> CGRect {
        guard let x = seamLine else { return rect }
        var inset = displayInset(at: anchor ?? rect.midX)
        if anchor == nil, spanHeight == .perDisplay {
            let there = displayInset(at: rect.midX < x ? x + 1 : x - 1)
            // Short of half the column, less a gap: one resting beside the seam keeps its display's height.
            let lead = min(Self.seamLead, rect.width / 2 - gaps.horizontal)
            let away = abs(rect.midX - x)
            if there.height < inset.height, away < lead {
                inset = there
            } else if spanHeightEases, there.height < inset.height {
                // Easing down over `seamEase` before the lead, by the same curve as a glide, so it shrinks as it comes.
                let ease = min(Self.seamEase, rect.width / 2 - gaps.horizontal) - lead
                if ease > 0, away < lead + ease {
                    let t = Easing.easeInOutCubic(Double((lead + ease - away) / ease))
                    inset.origin.y += (there.minY - inset.minY) * CGFloat(t)
                    inset.size.height += (there.height - inset.height) * CGFloat(t)
                }
            }
        }
        return CGRect(x: rect.minX, y: inset.minY.rounded(), width: rect.width, height: inset.height.rounded())
    }

    /// Strip frames such as a glide or fingers have them on the way, each window alone in its column as tall as the display
    /// it is on (`onDisplay`), rather than somewhere between where it set out and where it goes: with `spanHeight`
    /// `perDisplay`, one on its way to the shorter display, as `resting`, where the glide ends, has it, already that one's
    /// height, so it shows there at it, and one on its way to the taller takes that one's height as it crosses. As they
    /// are on one display, with `atRest`, and for a column of several, whose windows share its height.
    func onDisplays(_ frames: [WindowID: CGRect], resting: [WindowID: CGRect]?) -> [WindowID: CGRect] {
        guard spansDisplays, spanHeight != .atRest else { return frames }
        var placed = frames
        for column in root.children {
            guard case .window(let id) = column, let frame = frames[id] else { continue }
            var shown = onDisplay(frame)
            // Easing, a glide's own steps between its heights stand, kept no taller than the display has room as it comes.
            if spanHeightEases {
                if shown.height < frame.height { placed[id] = shown }
                continue
            }
            if spanHeight == .perDisplay, let rest = resting?[id], let x = seamLine {
                let there = displayInset(at: rest.midX)
                if there.height < shown.height {
                    shown = CGRect(x: frame.minX, y: there.minY, width: frame.width, height: there.height)
                } else if (rest.midX < x) == (frame.midX < x) {
                    // Resting on the display it is on: its height, however near the seam it passes on the way.
                    let here = displayInset(at: frame.midX)
                    shown = CGRect(x: frame.minX, y: here.minY, width: frame.width, height: here.height)
                }
            }
            placed[id] = shown
        }
        return placed
    }

    /// Across a seam, with every band column fitting on the two displays without scrolling, a display showing only one of
    /// them has it fill that display, as a lone column fills one display: two columns are one to each display, and of
    /// three, the one alone on its display fills it. Which columns go on which display, of the ways they fit: as evenly
    /// as they can be shared, then more on the display with more room. The widths the columns are given stand; one more column that
    /// does not fit and they lay out at them again. Whether they all fit.
    func fillLoneColumns(_ widths: inout [CGFloat], narrowest: [Int: CGFloat], in area: CGRect) -> Bool {
        let band = bandRange
        guard let x = seamLine, band.count >= 2 else { return false }
        let rooms = (left: x - area.minX, right: area.maxX - x)
        var starts: [CGFloat] = [], start: CGFloat = 0
        for i in band { starts.append(start); start += widths[i] }
        let total = start
        // Boundary k: band columns before it on the left display, the rest on the right.
        let splits = (0...band.count).filter { k in
            starts[safe: k].map { $0 <= rooms.left + 0.5 && total - $0 <= rooms.right + 0.5 }
                ?? (total <= rooms.left + 0.5)
        }
        // As evenly shared as they can be, then more on the display with more room: not by where the strip shows, which
        // focus moves, so focus moving changes no window's size.
        let wider = rooms.left >= rooms.right
        guard let k = splits.min(by: { a, b in
            (abs(2 * a - band.count), wider ? -a : a) < (abs(2 * b - band.count), wider ? -b : b)
        }) else { return false }
        if k == 1 { widths[band.lowerBound] = max(rooms.left, narrowest[band.lowerBound] ?? 0) }
        if band.count - k == 1 { widths[band.upperBound - 1] = max(rooms.right, narrowest[band.upperBound - 1] ?? 0) }
        // A display of several: room at its edge the column in view would reach over goes to the one beside the seam, so
        // the one at the edge keeps the width it was given, as one dragged to it does, whichever has focus.
        for (side, room) in [(Array(band.lowerBound..<band.lowerBound + k), rooms.left),
                             (Array((band.lowerBound + k)..<band.upperBound).reversed(), rooms.right)] where side.count > 1 {
            let left = room - side.reduce(0) { $0 + widths[$1] }
            if left > 0.5, reachesOver(left - gaps.horizontal / 2, in: area) { widths[side.last!] += left }
        }
        return true
    }

    /// Across a seam, with focus near enough an end of the strip that it rests there, the columns from the end to it fitting
    /// on the two displays together, the display at that end filled
    /// to the outer margin as one display's strip at its end is: the columns from the end keep their widths at the
    /// margin, and the one that would reach over the seam narrows to the room left between them and it, so the seam still
    /// falls between columns; where that one cannot go so narrow, the end column widens over the room instead. Room less
    /// than the column in view there reaches over (`reachesOver`) goes to the column beside the seam, not the end one.
    /// Only while focus is there: the widths the columns are given stand, and come back as focus leaves.
    func fitEnds(_ widths: inout [CGFloat], narrowest: [Int: CGFloat], in area: CGRect) {
        let band = bandRange
        guard let x = seamLine, band.count >= 2, let focus = shownBandColumn else { return }
        let half = gaps.horizontal / 2
        func fit(from end: Int, step: Int, room: CGFloat) {
            var left = room, i = end, on: [Int] = []
            while band.contains(i), widths[i] <= left + 0.5 {
                left -= widths[i]
                on.append(i)
                i += step
            }
            // All of the band fits on that display, or nothing does: no end to fill. Nor with focus too far from the end
            // for the strip to rest there.
            let toFocus = stride(from: end, through: focus, by: step).reduce(CGFloat(0)) { $0 + widths[$1] }
            guard band.contains(i), !on.isEmpty, (focus - end) * step >= 0, toFocus <= area.width + 0.5 else { return }
            // Room the column in view would reach over goes to the one beside the seam instead, so the end column keeps
            // the width it was given, as one dragged to it does.
            guard !reachesOver(left - half, in: area) else {
                if on.count > 1 { widths[on.last!] += left }
                return
            }
            if let floor = narrowest[i], floor <= left {
                widths[i] = left
            } else {
                widths[end] += left
            }
        }
        fit(from: band.upperBound - 1, step: -1, room: area.maxX - x)
        fit(from: band.lowerBound, step: 1, room: x - area.minX)
    }

    /// How far before the seam a column's middle takes the shorter display's height on its way there.
    static let seamLead: CGFloat = 100

    /// With `spanHeightEases`, how far before the seam a column's middle starts easing to the shorter display's height,
    /// reaching it `seamLead` before.
    static let seamEase: CGFloat = 300

    /// Whether heights ease between displays rather than step: `spanHeightAnimates` with `spanHeight` `perDisplay`.
    var spanHeightEases: Bool { spanHeightAnimates && spanHeight == .perDisplay }

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
    /// where any does. Of two about as near, a column's width either way as when `offset` centres a column on the seam,
    /// the one nearer `near`, where the strip shows now, so it moves no more than it must. `offset` itself where none
    /// will do, on one display, or with no band column to show.
    /// With `onLeft`, only offsets showing it whole on that display, where there are any; with `stepping`, the way focus
    /// stepped along the strip, 1 right and -1 left, none scrolling it back from `near`, where there are any.
    /// With `column`, that band column shown whole rather than the one that must show.
    func seamAligned(_ offset: CGFloat, spans: [(start: CGFloat, width: CGFloat)], in area: CGRect,
                     inside: Bool = false, near: CGFloat? = nil, onLeft: Bool? = nil, stepping: Int = 0,
                     column: Int? = nil) -> CGFloat {
        guard let x = seamLine, let focusedColumn = column ?? shownBandColumn else { return offset }
        let band = bandRange
        var shown = seamOffsets(spans: spans, in: area).map(\.offset)
            .filter { showsWhole(focusedColumn, at: $0, spans: spans, in: area) }
        func narrowed(_ keeps: (CGFloat) -> Bool) {
            let kept = shown.filter(keeps)
            if !kept.isEmpty { shown = kept }
        }
        if let near, stepping != 0 { narrowed { c in stepping > 0 ? c >= near - 0.5 : c <= near + 0.5 } }
        // Not one leaving a display bare beside a wall past what the column in view there reaches over: a column too wide
        // for the room left would hide behind its neighbour there. Before the display to centre on, which gives way.
        narrowed { c in !leavesBare(at: c, spans: spans, in: area) }
        if let onLeft {
            narrowed { c in (area.minX + spans[focusedColumn].start - c + spans[focusedColumn].width / 2 < x) == onLeft }
        }
        let all = inside ? shown.filter { c in band.allSatisfy { showsWhole($0, at: c, spans: spans, in: area) } } : []
        // Columns of a width differ by a point or two of rounding and gap: that far counts as a tie.
        let tie = gaps.horizontal + 4
        func rank(_ c: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            (near == nil ? abs(c - offset) : (abs(c - offset) / tie).rounded(), abs(c - (near ?? offset)), c)
        }
        return (all.isEmpty ? shown : all).min { rank($0) < rank($1) } ?? offset
    }

    /// Whether the strip at offset `c` leaves room on a display, at an outer edge that is a wall, more than the column in
    /// view nearest it reaches over (`reachesOver`): room the band columns shown whole on that display leave bare.
    func leavesBare(at c: CGFloat, spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> Bool {
        guard let x = seamLine else { return false }
        let inset = stripInset, band = bandRange
        for (wall, from, to) in [(Direction.left, inset.minX, x), (.right, x, inset.maxX)] where walls.contains(wall) {
            let covered = band.reduce(CGFloat(0)) { sum, i in
                let minX = area.minX + spans[i].start - c, maxX = minX + spans[i].width
                return minX >= from - 1.5 && maxX <= to + 1.5 ? sum + spans[i].width : sum
            }
            if !reachesOver(to - from - covered, in: area) { return true }
        }
        return false
    }

    /// Across a seam, how far fingers or the mouse scroll the strip: from where it rests with its first column shown,
    /// as `limits` has that end, to where it rests with its last, both lined up with the seam. On one display, nil.
    func seamEnds(_ limits: ClosedRange<CGFloat>, spans: [(start: CGFloat, width: CGFloat)], in area: CGRect)
        -> ClosedRange<CGFloat>? {
        let band = bandRange
        guard spansDisplays, let first = band.first, let last = band.last else { return nil }
        let lower = seamAligned(limits.lowerBound, spans: spans, in: area, column: first)
        let upper = seamAligned(limits.upperBound, spans: spans, in: area, column: last)
        return min(lower, upper)...max(lower, upper)
    }

    /// The display `spanCentring` centres `column` on, left (true) or right, as the strip shows at `offset`; nil to
    /// centre across both, or on one display.
    func centringSide(_ column: (start: CGFloat, width: CGFloat), from offset: CGFloat, in area: CGRect) -> Bool? {
        guard let x = seamLine else { return nil }
        switch spanCentring {
        case .both: return nil
        case .focused: return area.minX + column.start + column.width / 2 - offset < x
        case .display(let left): return left
        }
    }

    /// The offset that puts `column` in the middle of the left display's part of `area` (true), or the right one's.
    func centred(_ column: (start: CGFloat, width: CGFloat), onLeft left: Bool, in area: CGRect) -> CGFloat {
        guard let x = seamLine else { return centred(column, in: area) }
        let (from, to) = left ? (area.minX, x) : (x, area.maxX)
        return (column.start + column.width / 2 - ((from + to) / 2 - area.minX)).rounded()
    }

    /// The end of a strip across two displays that `commands`, a binding that did nothing, ran into with `id` focused:
    /// left or right, for a `focus`, `move` or `join-with` that way from the column at that end. Nil for anything else,
    /// and on one display.
    public func endRunInto(by commands: [String], from id: WindowID) -> Direction? {
        guard spansDisplays, bandIndex(of: id) != nil else { return nil }
        let around = columns(around: id)
        for command in commands {
            let words = command.split(separator: " ").map(String.init)
            guard words.count >= 2, ["focus", "move", "join-with"].contains(words[0]) else { continue }
            if words[1] == "left", around.left.isEmpty { return .left }
            if words[1] == "right", around.right.isEmpty { return .right }
        }
        return nil
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
        // Kept as it shows, so focusing a column from here scrolls from where it is.
        scrollOffset = shownOffset
    }
}
