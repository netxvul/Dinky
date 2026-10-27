import CoreGraphics

// The scrolling layout, after Hyprland's (and niri's): the root is a row of columns, each a window or a stack of
// windows, as wide as its own share of the screen whatever the number of columns, so the row runs past the
// screen edges and scrolls to keep the focused column in view. A lone column fills the screen, columns that fit
// are centred, and focusing a column scrolls just far enough to show it whole.
//
// macOS cannot clip another app's window at the screen edge, so a window scrolled out of view is parked
// instead: on an edge with nothing beyond it, the column nearest the screen hangs off it with `peek` points left
// on, in a gutter the columns keep an inner gap clear of, and the columns beyond tuck under that one with only
// `tuck` points left on, so a single shadow shows at the edge rather than one per parked window piled up. On an
// edge with another display beyond it (a wall), nothing leaves the screen, which would put it on the other display:
// the columns scrolled out past it hide behind the column in view nearest it, `shadowReach` inside it so their
// shadows hide too, and that column reaches out to the outer gap over the room they leave. A column cannot show in
// part there, so where the strip comes to rest a column lines up with the wall (`wallAligned`), rather than one
// straddling it hiding whole and leaving its room bare.
//
// Fullscreen, with `fullscreenPushesStrip`, widens the fullscreen window's column to the whole width the columns
// get, clear of the gutters, and scrolls to it, so its neighbours slide off and park in the gutters, a gap from it,
// as any column scrolled away does. The scroll offset is left alone meanwhile, so when fullscreen ends the strip
// goes back to where it was.

extension Workspace {
    /// How much of the parked column nearest the screen stays on it. A window's own app (AppKit) keeps any position
    /// that leaves at least a point of the window on screen, but pulls one asked to go wholly off, or to leave less
    /// than a point, back until 40 points show.
    public static let peek: CGFloat = 25

    /// How much of a parked column beyond the nearest one stays on screen, under the nearest: a point clear of
    /// AppKit's limit. Its edge is then `peek - tuck` inside the peek in front of it, past the 22.5 points an
    /// inactive window's shadow reaches, so its shadow hides under that peek too.
    public static let tuck: CGFloat = 2

    /// How far inside the column in view a window hiding behind it at a wall keeps, all round, so its shadow hides
    /// there too: past the 22.5 points an inactive window's shadow reaches.
    public static let shadowReach: CGFloat = 24

    /// How much narrower than its tile a window that snaps its size may be taken to be, from its last seen width,
    /// when placing it off the left edge, where its width decides how much of it stays on screen.
    static let snapAllowance: CGFloat = 16

    /// Narrowest a column can be resized to, as a share of the screen.
    static let minimumColumnWidth = 0.1

    public var isScrolling: Bool { algorithm == .scrolling }

    /// The columns that scroll, as indices of the root's children: the band between the columns pinned to the
    /// screen's sides, which are the first and the last. All of them when nothing is pinned.
    var bandRange: Range<Int> {
        let count = root.children.count
        let lower = pinnedIndex(.left) == nil ? 0 : 1, upper = pinnedIndex(.right) == nil ? count : count - 1
        return lower..<max(lower, upper)
    }

    /// The index of `id`'s column while it is in the band; nil for a pinned column or a window not here.
    func bandIndex(of id: WindowID) -> Int? {
        root.path(of: id).flatMap { bandRange.contains($0[0]) ? $0[0] : nil }
    }

    /// The area inside the outer gaps the band has: all of it but a pinned column and an inner gap beside it on each
    /// side pinned. The whole area inside the outer gaps when nothing is pinned.
    var stripInset: CGRect {
        var inset = gaps.inset(bounds)
        // A pin's span holds its half of the gap to the band; the band's end column there keeps the other half, as
        // beside any neighbour.
        if let left = pinnedIndex(.left) {
            let taken = pinSpan(left)
            inset.origin.x += taken
            inset.size.width -= taken
        }
        if let right = pinnedIndex(.right) { inset.size.width -= pinSpan(right) }
        inset.size.width = max(inset.width, 0)
        guard hasPins else { return inset }
        let minX = inset.minX.rounded(), maxX = inset.maxX.rounded()
        return CGRect(x: minX, y: inset.minY, width: max(maxX - minX, 0), height: inset.height)
    }

    /// Whether band column `index` is wider than the band beside a pin and shown from its start, the rest hanging
    /// under the pin or past the screen's edge: the column in view there though not wholly on screen.
    public func hangsUnderPin(column index: Int) -> Bool {
        guard hasPins, bandRange.contains(index) else { return false }
        let area = stripArea, spans = columnSpans(in: area)
        guard spans[index].width > area.width else { return false }
        let offset = offset(for: spans, in: area)
        // Shown from its start as far as the strip goes: a first column waits at the gutter before it.
        let lower = heldLimits(for: spans, in: area)?.lowerBound ?? -.infinity
        return abs(max(showing(spans[index], from: offset, in: area), lower) - offset) < 0.5
    }

    /// `hangsUnderPin(column:)` for the column of window `id`.
    public func hangsUnderPin(_ id: WindowID) -> Bool {
        bandIndex(of: id).map { hangsUnderPin(column: $0) } ?? false
    }

    /// Whether a column is pinned to either side.
    var hasPins: Bool { pinnedIndex(.left) != nil || pinnedIndex(.right) != nil }

    /// Whether the band's end column on each side has a pin beside it, which it keeps half a gap from, as from any
    /// neighbour.
    var bandNeighbours: (left: Bool, right: Bool) { (pinnedIndex(.left) != nil, pinnedIndex(.right) != nil) }

    /// The band's area on screen: inside the outer gaps, beside the pinned columns. The whole area inside the outer
    /// gaps when nothing is pinned.
    public var bandRect: CGRect { stripInset }

    /// The width a column's share is of: the strip's area as it is with nothing pinned, so pinning leaves the other
    /// columns' widths alone. Across a seam, the narrower display's part of it (`shareBase`).
    var shareWidth: CGFloat {
        guard hasPins else { return shareBase(of: stripArea) }
        // Without the pins, and so without a pin's fullscreen, which would count as pushing the strip.
        var plain = self
        plain.fullscreenWindows.removeAll { pinSide(of: $0) != nil }
        plain.pins = [:]
        return plain.shareBase(of: plain.stripArea)
    }

    /// Whether fullscreen here widens the window's column and pushes its neighbours off, rather than covering them.
    public var pushesFullscreen: Bool { isScrolling && fullscreenPushesStrip }

    /// The columns fullscreen widens to the whole screen: those holding a fullscreen window, when it pushes.
    var pushedColumns: Set<Int> {
        guard pushesFullscreen else { return [] }
        return Set(fullscreenWindows.compactMap { bandIndex(of: $0) })
    }

    /// Put a window in a new column right of the focused one, at the default width: in the band, right of the band
    /// window focused last while a pin has focus, else at the band's end beside that pin.
    mutating func insertColumn(_ id: WindowID) {
        let band = bandRange
        let anchor = focused.flatMap { bandIndex(of: $0) } ?? bandFocus.flatMap { bandIndex(of: $0) }
        let index = anchor.map { $0 + 1 }
            ?? (focused.flatMap { pinSide(of: $0) } == .left ? band.lowerBound : band.upperBound)
        root.insert(.window(id), at: min(max(index, band.lowerBound), band.upperBound))
        columnWidths[id] = columnWidth
    }

    /// The width of column `index` as a share: its windows all have it.
    func width(ofColumn index: Int) -> Double {
        root.children[index].windows.lazy.compactMap { columnWidths[$0] }.first ?? columnWidth
    }

    /// Give every window of column `index` the width `share`, kept between the narrowest a column goes and the
    /// whole screen.
    mutating func setWidth(ofColumn index: Int, _ share: Double) {
        let share = min(max(share, Self.minimumColumnWidth), 1)
        for id in root.children[index].windows { columnWidths[id] = share }
    }

    /// Where the columns go: inside the outer gaps, and when some have to park, also clear of the parked windows'
    /// gutter on each side without a wall, by half an inner gap, which with a column's own half makes a whole one.
    /// Columns that all fit inside the outer gaps at their shares of it park nowhere, so they keep no gutters; nor
    /// does a lone column. A fullscreen column pushing the others off parks them, so it keeps them. Column widths
    /// are shares of its width. Across a seam, columns fit only where they also leave it between two of them
    /// (`fitsAcrossSeam`).
    var stripArea: CGRect {
        let area = stripInset, band = bandRange
        guard band.count > 1 else { return area }
        let spans = columnSpans(in: area)
        if pushedColumns.isEmpty, let end = spans[safe: band.upperBound - 1],
           end.start + end.width <= area.width, fitsAcrossSeam(spans: spans, in: area) { return area }
        let clear = Self.peek + gaps.horizontal / 2
        // Across a seam without peeks, the columns parked at the outer edges tuck under the one in view: no gutters.
        let tucks = spansDisplays && !spanPeeks
        let left = walls.contains(.left) || pinnedIndex(.left) != nil || tucks ? 0 : max(clear - gaps.left, 0)
        let right = walls.contains(.right) || pinnedIndex(.right) != nil || tucks ? 0 : max(clear - gaps.right, 0)
        return CGRect(x: area.minX + left, y: area.minY, width: area.width - left - right, height: area.height)
    }

    /// Each column's start and width in points along the strip, from its left edge. Half an inner gap is part
    /// of a column on each side that has a neighbour, so neighbours end up a whole gap apart. A lone column is
    /// as wide as the screen; any other is its share of it, grown to fit its windows' minimum widths. A column in
    /// `pushed` is as wide as `area`, so with its half gaps it stays a whole gap from the gutters either side; at
    /// an end of the strip, where nothing is parked, it reaches on through the gutter out to the outer gap.
    func columnSpans(in area: CGRect, pushed: Set<Int> = []) -> [(start: CGFloat, width: CGFloat)] {
        let band = bandRange, gap = gaps.horizontal, pinned = hasPins, beside = bandNeighbours
        // With a column pinned, the others keep the widths they have without: shares of the unpinned strip, as wide
        // as the band at most. Across a seam, shares of one display, as wide as one goes (`shareBase`).
        let room = shareBase(of: area), base = pinned ? shareWidth : room
        var start: CGFloat = 0
        return root.children.indices.map { i in
            // A pinned column has a place of its own (`pinRect`), not along the band.
            guard band.contains(i) else { return (0, pinSpan(i)) }
            let insets = (i > band.lowerBound || beside.left ? gap / 2 : 0)
                + (i < band.upperBound - 1 || beside.right ? gap / 2 : 0)
            let minimum = root.children[i].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
            let wide = (base * CGFloat(width(ofColumn: i))).rounded()
            let share = pushed.contains(i)
                ? spansDisplays ? room : area.width + endGutters(of: i, area).left + endGutters(of: i, area).right
                : pinned ? min(wide, room) : wide
            // A lone column fills the area, beside a pin no narrower than its windows take: it then hangs under the
            // pin, or is held off a wall (`parked`), rather than growing past it onto the next display. Across a seam,
            // only the display it is on, half an inner gap from the seam.
            let alone = room - (spansDisplays ? gap / 2 : 0)
            let lone = pinned ? max(alone, minimum + insets) : alone
            let width = band.count == 1 ? lone : max(share, minimum + insets)
            defer { start += width }
            return (start, width)
        }
    }

    /// The gutters beside column `index` at the ends of the strip, where nothing is parked: the width between `area`
    /// and the outer gap on the side with no column beyond it.
    func endGutters(of index: Int, _ area: CGRect) -> (left: CGFloat, right: CGFloat) {
        let inset = stripInset, band = bandRange
        return (index == band.lowerBound ? area.minX - inset.minX : 0,
                index == band.upperBound - 1 ? inset.maxX - area.maxX : 0)
    }

    /// The scroll offset the layout uses. The strip never scrolls past either end (`scrollLimits`), and the column at
    /// an end reaches into the gutter there, which nothing is parked in, out to the outer gap. A strip that fits
    /// between the outer gaps is centred. The focused column always shows whole, scrolled to as little as that takes,
    /// even when what scrolled it away left focus alone: a column closing or growing to its windows' minimum width left
    /// of it, or the display or gaps changing; not `showingFocus`, nor while a click holds the strip still
    /// (`holdsScroll`) or fingers scroll it freely (`freeScrollFrom`), the offset is only kept within the ends.
    func offset(for spans: [(start: CGFloat, width: CGFloat)], in area: CGRect, showingFocus: Bool = true) -> CGFloat {
        let wanted = showingFocus && !holdsScroll && freeScrollFrom == nil
            ? focused.flatMap { bandIndex(of: $0) }.map { showing(spans[$0], from: scrollOffset, in: area) } : nil
        if keepsScroll { return wanted ?? scrollOffset }
        // Across a seam, it then rests with the seam between columns, unless fingers or a click hold it.
        let aligns = showingFocus && !holdsScroll && freeScrollFrom == nil
        guard let limits = heldLimits(for: spans, in: area) else {
            let total = bandEnd(of: spans), inset = stripInset
            // Across a seam, a strip that fits stays where it is rather than centred, whose middle is the seam.
            guard spansDisplays else { return (area.minX - inset.minX + (total - inset.width) / 2).rounded() }
            let kept = min(max(wanted ?? scrollOffset, min(total - area.width, 0)), 0)
            return aligns ? seamAligned(kept, spans: spans, in: area, inside: true) : kept
        }
        let offset = min(max(wanted ?? scrollOffset, limits.lowerBound), limits.upperBound)
        return aligns ? seamAligned(offset, spans: spans, in: area) : offset
    }

    /// `scrollLimits`, but past the end as far as a focused band column wider than the band, beside a pin, takes to
    /// show from the band's start, the rest of it under the pin; or the band window focused last while a pin has focus.
    /// What the offset, the fingers' scroll and a let-go keep to, so none of them jumps for it.
    func heldLimits(for spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> ClosedRange<CGFloat>? {
        guard let limits = scrollLimits(for: spans, in: area) else { return nil }
        // Across a seam, where the strip rests with its first or last column shown: past those, a let-go would only
        // spring back.
        if let ends = seamEnds(limits, spans: spans, in: area) { return ends }
        let shownColumn = focused.flatMap { bandIndex(of: $0) } ?? bandFocus.flatMap { bandIndex(of: $0) }
        let wide = hasPins ? shownColumn.flatMap { spans[$0].width > area.width ? spans[$0] : nil } : nil
        let upper = wide.map { max(limits.upperBound, showing($0, from: limits.upperBound, in: area)) } ?? limits.upperBound
        return limits.lowerBound...upper
    }

    /// How far the strip scrolls, from its first column at its start to its last at its end; nil for a strip that fits
    /// between the outer gaps, which is centred. With `columnCentring` `always` or `onOverflow`, the ends are as far as
    /// centres the column there, the screen bare beyond it; `alwaysFill` keeps them, so the column there goes to the
    /// screen's edge and the columns beside it fill the rest.
    func scrollLimits(for spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> ClosedRange<CGFloat>? {
        let total = bandEnd(of: spans), inset = stripInset, band = bandRange
        let first = area.minX - inset.minX, last = total - area.width - (inset.maxX - area.maxX)
        guard first < last else { return nil }
        guard columnCentring.centresEnds, !band.isEmpty else { return first...last }
        let start = spans[band.lowerBound], end = spans[band.upperBound - 1]
        return min(first, centred(start, in: area))...max(last, centred(end, in: area))
    }

    /// Where the band ends along the strip: the end of its last column, 0 with none.
    func bandEnd(of spans: [(start: CGFloat, width: CGFloat)]) -> CGFloat {
        let band = bandRange
        return band.isEmpty ? 0 : spans[safe: band.upperBound - 1].map { $0.start + $0.width } ?? 0
    }

    /// The offset that puts `column` in the middle of the area.
    func centred(_ column: (start: CGFloat, width: CGFloat), in area: CGRect) -> CGFloat {
        (column.start - (area.width - column.width) / 2).rounded()
    }

    /// The offset nearest `offset` that shows `column` whole, as Hyprland's `fit` does. A column wider than the
    /// area is centred; with a pin it starts at the band's start instead, its title bar and as much as fits showing,
    /// the rest under the pin beyond.
    func showing(_ column: (start: CGFloat, width: CGFloat), from offset: CGFloat, in area: CGRect) -> CGFloat {
        guard column.width > area.width else {
            return min(max(offset, column.start + column.width - area.width), column.start)
        }
        return hasPins ? column.start : column.start - (area.width - column.width) / 2
    }

    /// Scroll to the window's column as `columnCentring` says: as little as shows it whole, to the middle of the
    /// screen, to the middle as near as the strip's ends allow, or to the middle only when it did not all show; then
    /// lined up with a wall, so no column straddles one (`wallAligned`). Columns that all fit stay centred as a whole.
    /// A strip a click held still (`holdsScroll`) is held no more, and fingers scrolling it freely (`freeScrollFrom`)
    /// let go.
    mutating func reveal(_ id: WindowID) {
        holdsScroll = false
        freeScrollFrom = nil
        let from = revealingFrom
        revealingFrom = nil
        guard isScrolling, let index = bandIndex(of: id) else { return }
        let area = stripArea, spans = columnSpans(in: area), column = spans[index], resting = scrollOffset
        let shown = showing(column, from: offset(for: spans, in: area), in: area)
        // Across a seam, the display `spanCentring` names, if any (see Span.swift).
        let side = centringSide(column, from: shown, in: area)
        let middle = side.map { centred(column, onLeft: $0, in: area) } ?? centred(column, in: area)
        var centres = true
        switch columnCentring {
        case .never:
            scrollOffset = shown
            centres = false
        case .always, .alwaysFill: scrollOffset = middle
        case .onOverflow:
            // Across a seam, where it rests now: lined up with the seam, it can be past the ends the layout keeps to,
            // and a column beside the seam a point past the gutter, as spans are rounded, counts as whole.
            let before = spansDisplays ? scrollOffset : offset(for: spans, in: area, showingFocus: false)
            let slack: CGFloat = spansDisplays ? 1.5 : 0
            centres = abs(showing(column, from: before, in: area) - before) > slack
            scrollOffset = centres ? middle : shown
        }
        // Across a seam, a centred column rests beside it on the side nearer where the strip shows now, or on the display
        // `spanCentring` names; focus stepping along the strip never scrolls it back.
        let step = from.map { index == $0 ? 0 : index > $0 ? 1 : -1 } ?? 0
        scrollOffset = seamAligned(wallAligned(scrollOffset, spans: spans, in: area), spans: spans, in: area,
                                   near: resting, onLeft: centres ? side : nil, stepping: step)
    }

    /// The resting offset nearest in spirit to `offset` with no band column straddling a wall: at a wall nothing leaves
    /// the screen, so a column part past it hides whole behind the column in view nearest it (`parked`), and its room
    /// on screen would stay bare. For the column straddling a wall, the offset that shows it whole, ending at the wall;
    /// failing that, the one that puts it wholly beyond, starting at the wall; failing both, `offset`. Either only with
    /// the focused band column still whole on screen and within the ends (`heldLimits`). Showing comes first: the side
    /// away from the wall can show a column in part, or peek, and the wall side cannot. With walls on both sides, the
    /// right one's choice, then the left one's from there; should that make a column straddle the right one again,
    /// once more round both, and the one of those offsets leaving the least room bare at the walls. Not on a pinned
    /// side, nor for a strip that fits, nor with no band column focused or, a pin focused, focused last
    /// (`shownBandColumn`).
    func wallAligned(_ offset: CGFloat, spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> CGFloat {
        let right = walls.contains(.right) && pinnedIndex(.right) == nil
        let left = walls.contains(.left) && pinnedIndex(.left) == nil
        let band = bandRange
        guard right || left, let focusedColumn = shownBandColumn,
              let limits = heldLimits(for: spans, in: area) else { return offset }
        // A column counts as whole a little past the area, as spans are rounded to the point: an area an odd number of
        // points wide leaves two half-width spans one point over it. A straddler is one past a wall by more than half
        // one.
        let slack: CGFloat = 0.5, wholeSlack: CGFloat = 1.5
        func onScreen(_ i: Int, at c: CGFloat) -> (minX: CGFloat, maxX: CGFloat) {
            let minX = area.minX + spans[i].start - c
            return (minX, minX + spans[i].width)
        }
        func whole(_ i: Int, at c: CGFloat) -> Bool {
            let span = onScreen(i, at: c)
            return span.minX >= area.minX - wholeSlack && span.maxX <= area.maxX + wholeSlack
        }
        func valid(_ c: CGFloat) -> Bool { limits.contains(c) && whole(focusedColumn, at: c) }
        func straddler(_ wall: Direction, at c: CGFloat) -> Int? {
            let edge = wall == .right ? area.maxX : area.minX
            return band.first { i in
                let span = onScreen(i, at: c)
                return span.minX < edge - slack && span.maxX > edge + slack
            }
        }
        // Past an end of the strip, as when the column at it reaches into the gutter there, a candidate goes no further
        // than the end: taken all the same where what it leaves of the straddler on screen is room the column in view
        // nearest the wall reaches over (`reachesOver`).
        func taken(_ c: CGFloat, straddling j: Int, at wall: Direction) -> CGFloat? {
            if valid(c) { return c }
            let clamped = min(max(c, limits.lowerBound), limits.upperBound)
            guard clamped != c, valid(clamped) else { return nil }
            let span = onScreen(j, at: clamped)
            let left = wall == .right ? area.maxX - span.minX : span.maxX - area.minX
            return reachesOver(left, in: area) ? clamped : nil
        }
        func aligned(_ wall: Direction, from c: CGFloat) -> CGFloat {
            guard let j = straddler(wall, at: c) else { return c }
            let (start, width) = spans[j]
            let show = wall == .right ? start + width - area.width : start
            let past = wall == .right ? start - area.width : start + width
            return taken(show, straddling: j, at: wall) ?? taken(past, straddling: j, at: wall) ?? c
        }
        // The room bare between each wall and the nearest edge of a column shown whole on its half of the area.
        func bare(at c: CGFloat) -> CGFloat {
            let shown = band.filter { whole($0, at: c) }.map { onScreen($0, at: c) }
            var room: CGFloat = 0
            if right {
                let near = shown.filter { ($0.minX + $0.maxX) / 2 > area.midX }.map(\.maxX).max()
                room += area.maxX - (near ?? area.midX)
            }
            if left {
                let near = shown.filter { ($0.minX + $0.maxX) / 2 < area.midX }.map(\.minX).min()
                room += (near ?? area.midX) - area.minX
            }
            return room
        }
        guard right && left else { return aligned(right ? .right : .left, from: offset) }
        let afterRight = aligned(.right, from: offset), afterBoth = aligned(.left, from: afterRight)
        guard straddler(.right, at: afterBoth) != nil else { return afterBoth }
        // The left step left a column straddling the right wall: once more round both, then the least room bare.
        let again = aligned(.right, from: afterBoth), againBoth = aligned(.left, from: again)
        return [offset, afterRight, afterBoth, again, againBoth].min { bare(at: $0) < bare(at: $1) }!
    }

    /// The band column that must show whole where the strip rests: the focused one's, or with a pin focused, the band
    /// window focused last's (as `heldLimits` takes it). Nil with neither in the band.
    var shownBandColumn: Int? {
        focused.flatMap { bandIndex(of: $0) } ?? bandFocus.flatMap { bandIndex(of: $0) }
    }

    /// Lines the strip up with its walls where it shows now (`wallAligned`), as after a display came beside it: no
    /// centring again. Not while a click holds the scroll, fingers scroll it freely, the scroll is kept, something is
    /// or is about to be fullscreen, or no band column is to show whole (`shownBandColumn`).
    public mutating func alignToWalls() {
        guard isScrolling, !holdsScroll, freeScrollFrom == nil, !keepsScroll, fullscreenWindows.isEmpty,
              pendingFullscreen == nil, shownBandColumn != nil else { return }
        let area = stripArea, spans = columnSpans(in: area)
        scrollOffset = seamAligned(wallAligned(shownOffset, spans: spans, in: area), spans: spans, in: area)
    }

    /// Scrolls to the focused column as focusing it would have, now that the click that focused it with
    /// `holdingScroll` is done. Nothing while the strip holds no scroll: the focused column has been scrolled to.
    public mutating func revealFocus() {
        guard holdsScroll else { return }
        holdsScroll = false
        if let focused { reveal(focused) }
    }

    /// Whether focusing with `holdingScroll` holds the strip still: wherever focusing can scroll it, to the middle or as
    /// little as shows the column whole, since either takes the tree from under the pointer that pressed it while the
    /// screen has not moved yet, and a drag the press starts is measured against the tree. Not while a window is
    /// fullscreen: focusing ends fullscreen or hands it on, laying the strip out afresh anyway.
    var canHoldScroll: Bool { isScrolling && fullscreenWindows.isEmpty }

    /// The scroll offset the strip shows at: `scrollOffset` as the layout takes it, within the ends, the focused
    /// column whole.
    public var shownOffset: CGFloat {
        let area = stripArea
        return offset(for: columnSpans(in: area), in: area)
    }

    /// The strip laid out at the current scroll offset, windows anywhere along it, on screen or not. The focused
    /// column comes first in the stacking, then the others by distance from it.
    /// The columns in `pushed` are as wide as the strip's area and their fullscreen windows fill them; the focused
    /// one, if pushed, fills the area whatever the scroll offset, its neighbours parked in the gutters either side. The other windows of a pushed
    /// column keep the width the column has otherwise, behind its fullscreen window. With `pushedFullscreenFills`, the
    /// focused one's fullscreen windows fill the area inside the outer gaps, over the gutters. At a wall, the column in
    /// view nearest it may reach out to the outer gap there (see `reachingWalls`).
    func stripLayout(pushed: Set<Int> = []) -> Layout {
        var result = Layout()
        let area = stripArea, spans = columnSpans(in: area, pushed: pushed), inset = gaps.inset(bounds)
        let gap = gaps.horizontal, band = bandRange, first = band.lowerBound, last = band.upperBound - 1
        var offset = offset(for: spans, in: area)
        let focusedColumn = focused.flatMap { bandIndex(of: $0) }
        if let column = focusedColumn, pushed.contains(column) {
            if let x = seamLine {
                // Across a seam it fills the display it is on, against the seam, the other display left as it shows.
                let left = area.minX + spans[column].start + spans[column].width / 2 - offset < x
                let between = seamOffsets(spans: spans, in: area)
                offset = between.first { $0.boundary == column + (left ? 1 : 0) }?.offset ?? offset
            } else {
                offset = spans[column].start + endGutters(of: column, area).left
            }
        }
        // Not with a column pinned: the system's Fill would cover it.
        // Across a seam, the display it is on, inside the outer gaps, whichever display that is.
        let fills = { (i: Int, id: WindowID) in
            (pushedFullscreenFills || self.spansDisplays) && !self.hasPins && i == focusedColumn && pushed.contains(i)
                && fullscreenWindows.contains(id)
        }
        let unpushed = pushed.isEmpty ? spans : columnSpans(in: area)
        let beside = bandNeighbours
        let edges = spans.indices.map { i -> (left: CGFloat, right: CGFloat) in
            let x = area.minX + spans[i].start - offset
            return ((x + (i > first || beside.left ? gap / 2 : 0)).rounded(),
                    (x + spans[i].width - (i < last || beside.right ? gap / 2 : 0)).rounded())
        }
        // Not while fingers scroll the strip freely: a column would change width under them as it came to the wall.
        // Across a seam, while fullscreen pushes too: the other display shows the strip as ever.
        let reaching: (left: Int?, right: Int?) = (pushed.isEmpty || spansDisplays) && freeScrollFrom == nil
            ? reachingWalls(edges, in: area) : (nil, nil)
        result.containerRects[[]] = inset
        let reach = stripInset
        for i in stripStackingOrder {
            let trail = i < last || beside.right ? gap / 2 : 0
            let x = area.minX + spans[i].start - offset
            // Beside a pin, still half a gap from its own half (only across a seam does a column reach towards a pin).
            let a = i != reaching.left ? edges[i].left : beside.left ? (reach.minX + gap / 2).rounded() : reach.minX
            let b = i != reaching.right ? edges[i].right : beside.right ? (reach.maxX - gap / 2).rounded() : reach.maxX
            // A pinned column stays at its side whatever the scroll. Across a seam, as tall as the display it is on; with
            // `spanHeight` `atRest`, while fingers hold the strip, the one it was on as they took hold.
            let held = spanHeight == .atRest && band.contains(i)
                ? freeScrollFrom.map { area.minX + spans[i].start - $0 + spans[i].width / 2 } : nil
            let rect = onDisplay(band.contains(i) ? CGRect(x: a, y: area.minY, width: b - a, height: area.height)
                : pinRect(i), anchor: held)
            let filled = spansDisplays ? displayInset(at: rect.midX) : inset
            switch root.children[i] {
            case .window(let id):
                result.frames[id] = fills(i, id) ? filled : rect
                result.order.append(id)
            case .container(let c) where pushed.contains(i):
                let end = (x + unpushed[i].width - trail).rounded()
                let inner = onDisplay(CGRect(x: a, y: area.minY, width: end - a, height: area.height), anchor: held)
                c.layout(in: inner, gaps: gaps, padding: accordionPadding, minimums: minimumSizes, path: [i], into: &result)
                for id in Node.container(c).windows where fullscreenWindows.contains(id) {
                    result.frames[id] = fills(i, id) ? filled : rect
                }
            case .container(let c):
                c.layout(in: rect, gaps: gaps, padding: accordionPadding, minimums: minimumSizes, path: [i], into: &result)
            }
        }
        return result
    }

    /// The strip's columns front to back: the pinned ones, which the band's scroll under, then the band's, its
    /// focused column first and the others by distance from it, lower index first on ties. The band's focused column
    /// is the band window focused last while a pin has focus.
    var stripStackingOrder: [Int] {
        let band = bandRange
        let pinned = PinSide.allCases.compactMap(pinnedIndex)
        let clamped = min(max(root.activeIndex, band.lowerBound), max(band.upperBound - 1, band.lowerBound))
        let active = band.contains(root.activeIndex) ? root.activeIndex
            : bandFocus.flatMap { bandIndex(of: $0) } ?? clamped
        return pinned + band.sorted { (abs($0 - active), $0) < (abs($1 - active), $1) }
    }

    /// Whether the column in view nearest a wall reaches out over `span`, the part of the strip between that column's
    /// span and the outer gap there, as a column's span is measured, half a gap of each neighbour in it: less than the
    /// narrowest column takes in `area`. More is a column's worth, as columns of other widths can leave.
    func reachesOver(_ span: CGFloat, in area: CGRect) -> Bool {
        span < area.width * CGFloat(Self.minimumColumnWidth)
    }

    /// The column in view nearest each wall that reaches out to the outer gap there, if any. A column scrolled out past
    /// a wall hides behind the column in view nearest it (see `parked`) and leaves the room it had: half an inner gap,
    /// and at the far end of the strip the gutter there too, which the end column reaches into instead of a column
    /// parking in it. Not reached over, that room would show the screen's background between the column and the outer
    /// gap. Only less room than the narrowest column takes: more is a column's worth, as columns of other widths can
    /// leave, and the column keeps its width. Not on a pinned side: the pin is there, a gap from the band. Across a seam,
    /// the outer edges of the two displays too: columns are shares of the narrower one, so the wider one has room left
    /// at its outer edge that a column in view reaches over rather than leave a sliver of the next one showing there,
    /// or bare room past the strip's end, which the seam keeps it from scrolling into.
    /// `edges` are each column's window edges where the strip has it.
    func reachingWalls(_ edges: [(left: CGFloat, right: CGFloat)], in area: CGRect) -> (left: Int?, right: Int?) {
        let inset = stripInset, band = bandRange, half = gaps.horizontal / 2, beside = bandNeighbours
        // Across a seam, in view beside a pin is clear of it: a column under it does not count.
        let view = spansDisplays ? CGRect(x: inset.minX - (beside.left ? half : 0), y: bounds.minY,
                                          width: inset.width + (beside.left ? half : 0) + (beside.right ? half : 0),
                                          height: bounds.height) : bounds
        let inView = band.filter { edges[$0].left >= view.minX - 1 && edges[$0].right <= view.maxX + 1 }
        // The room from the column's window to the outer gap holds the column's own half gap too; beside a pin, the
        // half gap the column keeps from it as well.
        let reaches = { (room: CGFloat) in room > 0 && reachesOver(room - half, in: area) }
        // Across a seam, beside a pin too: the band there has the room left that columns of the narrower display's
        // shares leave, like any other edge.
        let left = inView.first.flatMap { i in
            (i > band.lowerBound || spansDisplays) && (walls.contains(.left) || spansDisplays)
                && (pinnedIndex(.left) == nil || spansDisplays)
                && reaches(edges[i].left - inset.minX - (beside.left ? half : 0)) ? i : nil
        }
        let right = inView.last.flatMap { i in
            (i < band.upperBound - 1 || spansDisplays) && (walls.contains(.right) || spansDisplays)
                && (pinnedIndex(.right) == nil || spansDisplays)
                && reaches(inset.maxX - edges[i].right - (beside.right ? half : 0)) ? i : nil
        }
        return (left, right)
    }

    /// Scrolling: the strip's frames before parking, at the current scroll offset. Gliding these and parking them
    /// on every frame (`placeStrip`) scrolls the strip as one: a column passing through slides across the screen
    /// where the strip has it, rather than every parked window flying straight from one edge to the other.
    public var stripFrames: [WindowID: CGRect] {
        isScrolling ? stripLayout(pushed: pushedColumns).frames : [:]
    }

    /// The strip's columns left to right, each as its windows top to bottom; none outside the scrolling layout.
    public var stripColumns: [[WindowID]] { isScrolling ? root.children.map(\.windows) : [] }

    /// Where strip frames, such as `stripFrames` part way through a glide, go on screen: parked as `layout()` parks
    /// them. With `resting`, the strip frames the glide ends at, a window hiding at a wall is sized by where the column
    /// it hides behind rests, so it changes size once on the way rather than with every step of that column's.
    public func placeStrip(_ frames: [WindowID: CGRect], resting: [WindowID: CGRect]? = nil) -> [WindowID: CGRect] {
        parked(frames, resting: resting)
    }

    /// `frame` moved back to a wall it would hang past, for one placed where the strip has it rather than parked: past
    /// the wall it would be on the other display, and macOS would take it to that display's Space. One wider than the
    /// screen between two walls stays at the left one.
    public func keptOffWalls(_ frame: CGRect) -> CGRect {
        var x = frame.minX
        if walls.contains(.right) { x = min(x, bounds.maxX - frame.width) }
        if walls.contains(.left) { x = max(x, bounds.minX) }
        return CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }

    /// The windows of `id`'s column, and of the columns left and right of it, each side nearest column first.
    public func columns(around id: WindowID) -> (own: [WindowID], left: [[WindowID]], right: [[WindowID]]) {
        guard isScrolling, let column = root.path(of: id)?.first else { return ([], [], []) }
        let columns = root.children.map(\.windows), band = bandRange
        let left = columns[band.lowerBound..<max(min(column, band.upperBound), band.lowerBound)]
        let right = columns[min(max(column + 1, band.lowerBound), band.upperBound)..<band.upperBound]
        return (columns[column], left.reversed(), Array(right))
    }

    /// Where the strip's windows go on screen. A window stays where the strip puts it while more of it shows than
    /// its edge allows, so the columns in view and their neighbours keep their gaps; past that it stops at the edge.
    /// On an edge with nothing beyond it, a column stops with `peek` showing, unless the column between it and the
    /// screen shows less than `peek - tuck` more than that: then it stops `peek - tuck` inside that column's edge,
    /// down to `tuck`. So the column nearest the screen peeks out, the ones beyond it tuck under it, and one sliding
    /// out or in moves continuously between the two, its edge and shadow under the column in front all the while.
    /// A window that would not stay tucked (`untuckable`) stops at `peek`. Off the left edge, how much shows depends
    /// on the window's width, so a window that came out narrower than its tile is placed by the width it had.
    ///
    /// At a wall, a window stays wholly on screen instead, and one scrolled out past the wall hides behind the
    /// column in view nearest the wall, inside that column's biggest window (see `hiddenAtWall`), so neither it nor
    /// its shadow shows in the outer gap, between the columns, or between the windows of a column of several. With
    /// no column in view it stays flush at the wall. While fullscreen pushes, the column in view is the fullscreen
    /// window's, so a window hiding behind it grows no bigger than it is rather than to the whole screen's size.
    /// `resting`, the strip frames where a glide ends, sizes a window hiding at a wall (see `hiddenAtWall`).
    func parked(_ frames: [WindowID: CGRect], resting: [WindowID: CGRect]? = nil) -> [WindowID: CGRect] {
        let frames = onDisplays(frames, resting: resting)
        let keepsSize = !pushedColumns.isEmpty
        let columns = root.children.map { $0.windows.filter { frames[$0] != nil } }
        let covers = wallCovers(of: frames)
        // How much of each window must stay on screen at each edge, column by column from the screen outwards,
        // following how much the column in front shows. Rounded towards more of the window on screen, since part of
        // a point counts as none. A column stacked above the one in front of it (as on the far side of a long glide,
        // stacked for where it ends) would show its sliver and shadow over that one, so it stays at `peek` instead.
        let behind = Self.peek - Self.tuck
        let rank = Dictionary(uniqueKeysWithValues: stripStackingOrder.enumerated().map { ($1, $0) })
        func shows(_ column: Int, behind front: CGFloat, _ frontColumn: Int?) -> CGFloat {
            guard let frontColumn, rank[column]! > rank[frontColumn]! else { return Self.peek }
            return min(max(front - behind, Self.tuck), Self.peek)
        }
        // On a pinned side every parked column tucks: the pin covers them, and should it lose its place in front
        // only a sliver shows.
        // So does every one across a seam without peeks.
        let tucks = spansDisplays && !spanPeeks
        let tucked = (left: pinnedIndex(.left) != nil || tucks, right: pinnedIndex(.right) != nil || tucks)
        var leftLimit: [WindowID: CGFloat] = [:], rightLimit: [WindowID: CGFloat] = [:]
        var front = CGFloat.infinity, frontColumn: Int?
        for (column, ids) in columns.enumerated().reversed() where !ids.isEmpty {
            let shows = shows(column, behind: front, frontColumn)
            front = -.infinity
            frontColumn = column
            for id in ids {
                let frame = frames[id]!, width = shownWidth(of: id, frame)
                let shows = untuckable.contains(id) ? Self.peek : tucked.left ? Self.tuck : shows
                let limit = (bounds.minX + shows - width).rounded(.up)
                leftLimit[id] = limit
                front = max(front, max(frame.minX, limit) + width - bounds.minX)
            }
        }
        front = .infinity
        frontColumn = nil
        for (column, ids) in columns.enumerated() where !ids.isEmpty {
            let shows = shows(column, behind: front, frontColumn)
            front = -.infinity
            frontColumn = column
            for id in ids {
                let frame = frames[id]!
                let shows = untuckable.contains(id) ? Self.peek : tucked.right ? Self.tuck : shows
                let limit = (bounds.maxX - shows).rounded(.down)
                rightLimit[id] = limit
                front = max(front, bounds.maxX - min(frame.minX, limit))
            }
        }
        let hanging = hangingUnderPins(frames)
        return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
            if let wall = wallParking(frame, covers: covers), !hanging.contains(id),
               let cover = wall == .left ? covers.left : covers.right {
                if let curtain = curtain(frame, at: wall, under: cover), !keepsSize {
                    return (id, curtain)
                }
                return (id, hiddenAtWall(id, frame, behind: cover.frame, sizedBy: resting?[cover.id], wall: wall,
                                         keepsSize: keepsSize))
            }
            var x = frame.minX
            x = min(x, walls.contains(.right) ? bounds.maxX - frame.width : rightLimit[id] ?? bounds.maxX - Self.peek)
            x = max(x, walls.contains(.left) ? bounds.minX : leftLimit[id] ?? bounds.minX + Self.peek - frame.width)
            return (id, CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height))
        })
    }

    /// The biggest window of a column shown whole, and the frames of that column's windows.
    struct WallCover {
        let id: WindowID, frame: CGRect, column: [CGRect]

        /// Whether the column's windows, top to bottom, leave no gap between them from `top` down to `bottom`, as an
        /// accordion's overlapping windows do, half a point allowed.
        func spans(from top: CGFloat, to bottom: CGFloat) -> Bool {
            var reached: CGFloat?
            for rect in column.sorted(by: { $0.minY < $1.minY }) {
                if let low = reached {
                    guard rect.minY <= low + 0.5 else { break }
                    reached = max(low, rect.maxY)
                } else {
                    guard rect.minY <= top else { return false }
                    reached = rect.maxY
                }
            }
            return reached.map { $0 >= bottom } ?? false
        }
    }

    /// For strip frames such as `placeStrip` takes, the biggest window of the column in view nearest each side: what
    /// a window scrolled out past a wall there hides behind, or hangs under as a curtain (see `parked`).
    func wallCovers(of frames: [WindowID: CGRect]) -> (left: WallCover?, right: WallCover?) {
        let covers = root.children.map { $0.windows.filter { frames[$0] != nil } }.compactMap { ids -> WallCover? in
            let rects = ids.map { (id: $0, frame: frames[$0]!) }
            let shown = rects.allSatisfy { $0.frame.minX >= bounds.minX - 1 && $0.frame.maxX <= bounds.maxX + 1 }
            guard !rects.isEmpty, shown,
                  let biggest = rects.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            else { return nil }
            return WallCover(id: biggest.id, frame: biggest.frame, column: rects.map(\.frame))
        }
        return (covers.min { $0.frame.minX < $1.frame.minX }, covers.max { $0.frame.maxX < $1.frame.maxX })
    }

    /// The wall a window at `frame` is parked at, as a curtain or hidden behind the cover there, if any: part or wholly
    /// past a wall on one side, with a column in view to cover it. One hanging under a pin is held off the wall
    /// instead, which the caller tells (`hangingUnderPins`).
    private func wallParking(_ frame: CGRect, covers: (left: WallCover?, right: WallCover?)) -> Direction? {
        let offLeft = frame.minX < bounds.minX - 1, offRight = frame.maxX > bounds.maxX + 1
        guard offLeft != offRight else { return nil }
        let wall: Direction = offLeft ? .left : .right
        return walls.contains(wall) && (wall == .left ? covers.left : covers.right) != nil ? wall : nil
    }

    /// The band windows hanging under a pin, held off a wall rather than parked at it.
    private func hangingUnderPins(_ frames: [WindowID: CGRect]) -> Set<WindowID> {
        // A band window as wide as the band or wider, beside a pin, is the one in view there: past a wall it is held
        // off it, hanging under the pin, not hidden behind a column in view.
        // A band window wider than the band beside a pin, the one in view there: as it rests (`hangsUnderPin`), and on
        // the way, glided or scrolled by the fingers, wherever its frame spans the band, half a gap in from a
        // neighbour on either side allowed.
        var hanging = Set(bandRange.filter { hangsUnderPin(column: $0) }.flatMap { root.children[$0].windows })
        if hasPins {
            let area = stripArea, spans = columnSpans(in: area), band = bandRect, half = gaps.horizontal / 2
            let beside = bandNeighbours, range = bandRange
            for i in range where spans[i].width > area.width {
                let left = min(band.minX, area.minX) + (i > range.lowerBound || beside.left ? half : 0) + 1
                let right = max(band.maxX, area.maxX) - (i < range.upperBound - 1 || beside.right ? half : 0) - 1
                for id in root.children[i].windows {
                    if let frame = frames[id], frame.minX <= left, frame.maxX >= right { hanging.insert(id) }
                }
            }
        }
        return hanging
    }

    /// For strip frames such as `placeStrip` takes, the window at each wall that windows parked there are under: the
    /// cover (`wallCovers(of:)`) where at least one band window is held there as a curtain or hides behind it, the
    /// left wall's first, each once: between two walls with one column shown, it is both walls' cover. None on a
    /// pinned side, whose pin is put in front of the band by the pins' own ordering.
    public func wallCovers(_ frames: [WindowID: CGRect]) -> [WindowID] {
        let covers = wallCovers(of: frames), hanging = hangingUnderPins(frames)
        var parkedAt: Set<Direction> = []
        for (id, frame) in frames where !hanging.contains(id) && pinSide(of: id) == nil {
            if let wall = wallParking(frame, covers: covers) { parkedAt.insert(wall) }
        }
        var ids: [WindowID] = []
        for (wall, cover) in [(Direction.left, covers.left), (.right, covers.right)] {
            guard parkedAt.contains(wall), let cover, pinnedIndex(wall == .left ? .left : .right) == nil,
                  pinSide(of: cover.id) == nil, !ids.contains(cover.id) else { continue }
            ids.append(cover.id)
        }
        return ids
    }

    /// Where a window part past `wall` stays as a curtain: at its size, held at the wall where the strip holds a
    /// window that reaches it, under `cover`, the biggest window of the column in view nearest the wall, so the room
    /// between that column and the wall shows the window rather than nothing. Only while the cover leaves room at the
    /// wall, and the window's edge away from the wall, and its shadow, stay `shadowReach` inside the cover's far edge,
    /// short of the column beyond; nil otherwise, and for a window wholly past the wall, inside the outer gap or
    /// beyond, which hide behind the cover. Under a column of several windows, only one no taller than the cover, or
    /// one the column's windows span top to bottom with no gap between them, as an accordion's: one reaching past
    /// would show in the gaps between that column's windows.
    func curtain(_ frame: CGRect, at wall: Direction, under column: WallCover) -> CGRect? {
        let inset = stripInset, reach = Self.shadowReach, cover = column.frame
        // Only where the cover leaves room at the wall: one reaching out to the outer gap covers it all.
        let partly = wall == .right ? frame.minX < inset.maxX - 1 : frame.maxX > inset.minX + 1
        let room = wall == .right ? cover.maxX < inset.maxX - 1 : cover.minX > inset.minX + 1
        let covered = column.column.count == 1 || frame.minY >= cover.minY && frame.maxY <= cover.maxY
            || column.spans(from: frame.minY, to: frame.maxY)
        guard partly, room, covered else { return nil }
        let held = keptOffWalls(frame)
        return wall == .right ? held.minX >= cover.minX + reach ? held : nil
            : held.maxX <= cover.maxX - reach ? held : nil
    }

    /// Where a window scrolled out past `wall` hides behind `cover`, the biggest window of the column in view nearest
    /// the wall: `shadowReach` inside it all round, so its shadow hides there too and the column shows one window's
    /// shadow, not one more for each window behind it. Grown to its minimum size, it stays inside the cover as far as
    /// it fits, and past that hangs out away from the wall and downwards. While fullscreen pushes (`keepsSize`), the
    /// cover is the fullscreen window, and it grows no bigger than it is, but still keeps `shadowReach` inside: as tall
    /// as the fullscreen window, it would show its shadow above and below it, one more for each window behind.
    /// Sized by `rest`, where the cover rests at the end of a glide, it keeps that size as the cover changes its own on
    /// the way, only made smaller where the cover is smaller than that now, so it never shows past it.
    func hiddenAtWall(_ id: WindowID, _ frame: CGRect, behind cover: CGRect, sizedBy rest: CGRect? = nil,
                      wall: Direction, keepsSize: Bool) -> CGRect {
        let minimum = minimumSizes[id] ?? .zero, margins = Self.shadowReach * 2
        let room = CGSize(width: min(rest?.width ?? cover.width, cover.width),
                          height: min(rest?.height ?? cover.height, cover.height))
        let width = max(min(keepsSize ? frame.width : .infinity, room.width - margins), minimum.width, 1)
        let height = max(min(keepsSize ? frame.height : .infinity, room.height - margins), minimum.height, 1)
        let x = (cover.midX - width / 2).rounded(), y = (cover.midY - height / 2).rounded()
        let inside = wall == .left ? max(min(x, cover.maxX - width), cover.minX)
            : min(max(x, cover.minX), cover.maxX - width)
        return CGRect(x: inside, y: max(min(y, cover.maxY - height), cover.minY), width: width, height: height)
    }

    /// The width `frame` takes on screen: its own, or the width the window last had if it came out a little
    /// narrower, as an app that snaps its size to a grid does.
    func shownWidth(of id: WindowID, _ frame: CGRect) -> CGFloat {
        guard let seen = observedWidths[id] else { return frame.width }
        return frame.width - min(max(frame.width - seen, 0), Self.snapAllowance)
    }

    /// Whether the strip shows the whole window now. Always true outside the scrolling layout. Neighbours a
    /// fullscreen window pushed off are not in view.
    public func isInView(_ id: WindowID) -> Bool {
        guard isScrolling, pinSide(of: id) == nil, let frame = stripLayout(pushed: pushedColumns).frames[id] else {
            return true
        }
        // Under a pin is out of view too.
        let left = pinnedIndex(.left) == nil ? bounds.minX : stripInset.minX
        let right = pinnedIndex(.right) == nil ? bounds.maxX : stripInset.maxX
        return frame.minX >= left - 1 && frame.maxX <= right + 1
    }

    /// `move` in the strip. Left and right take a window that shares its column out into a new column on that
    /// side, and swap a column of its own with its neighbour. Up and down only move it within its column.
    mutating func moveInStrip(_ direction: Direction) -> Bool {
        guard let focused, let path = root.path(of: focused) else { return false }
        let column = path[0], forward = direction.isForward
        if direction.orientation == .horizontal {
            // A pinned column stays where it is, and the band does not swap into it; a window of a pinned stack
            // moving inwards becomes the band's first column on that side.
            if let side = pinSide(ofColumn: column), path.count == 1 || PinSide(direction) == side { return false }
            if path.count > 1 {
                let share = width(ofColumn: column)
                rekeyPins(leaving: focused)
                root.modify(at: Array(path.dropLast())) { $0.remove(at: path.last!) }
                let band = bandRange
                root.insert(.window(focused), at: min(max(column + (forward ? 1 : 0), band.lowerBound), band.upperBound))
                columnWidths[focused] = share
            } else {
                let other = column + (forward ? 1 : -1)
                guard bandRange.contains(other), bandRange.contains(column) else { return false }
                let node = root.children[other]
                root.replace(at: other, with: root.children[column])
                root.replace(at: column, with: node)
            }
            normalize()
            focus(focused)
            return true
        }
        // Up or down within a column; in a pin, not where its new shape needs more room than the band can give.
        guard path.count > 1 else { return false }
        var moving = self
        guard moving.moveInTree(direction) else { return false }
        if moving.pinSide(of: focused) != nil, lacksRoom(after: moving) { return false }
        self = moving
        return true
    }

    /// `join-with` in the strip: left and right put the window into the neighbouring column, at that column's
    /// width; up and down work as in any tree, within the column, refused where they would make or merge columns, move
    /// a window into or out of a pin, or leave the band short of room beside one.
    mutating func joinInStrip(_ direction: Direction) -> Bool {
        guard direction.orientation == .horizontal, let focused, let column = root.path(of: focused)?.first else {
            // Up or down, within a column: never into columns of their own, nor out of a pin or into one.
            var joining = self
            guard joining.joinInTree(direction), joining.root.children.count == root.children.count,
                  joining.pins == pins, Set(joining.pinnedWindows) == Set(pinnedWindows) else { return false }
            // In a pin, not where its new shape needs more room than the band can give.
            if let focused, joining.pinSide(of: focused) != nil, lacksRoom(after: joining) { return false }
            self = joining
            return true
        }
        let neighbour = column + (direction.isForward ? 1 : -1)
        guard root.children.indices.contains(neighbour) else { return false }
        // Out of a pin of its own it unpins; into a pin, it stacks there at the pin's width.
        if let side = pinSide(ofColumn: column), PinSide(direction) == side { return false }
        let share = width(ofColumn: neighbour)
        var joining = self
        joining.rekeyPins(leaving: focused)
        guard joining.joinInTree(direction), let joined = joining.root.path(of: focused)?.first else { return false }
        joining.setWidth(ofColumn: joined, share)
        // Into a pin, not where the pin then leaves the band too little room.
        if joining.pinSide(ofColumn: joined) != nil, lacksRoom(after: joining) { return false }
        self = joining
        reveal(focused)
        return true
    }

    /// Grow (positive) or shrink the focused window's column by `delta` points. False when nothing visibly changed.
    mutating func resizeColumn(by delta: CGFloat) -> Bool {
        guard let focused, let column = root.path(of: focused)?.first else { return false }
        let old = width(ofColumn: column)
        let (before, offset, room) = (tiledLayout(), scrollOffset, stripInset.width)
        let pinned = pinSide(ofColumn: column) != nil
        // A band column as wide as the band steps from the width it shows, not its share past it.
        let shown = pinned || !hasPins ? old : min(old, Double(stripArea.width / shareWidth))
        setWidth(ofColumn: column, shown + Double(delta / (pinned ? screenWidth : shareWidth)))
        reveal(focused)
        // A step a lone column or the minimum sizes swallow whole is undone, so the width does not drift out of sight;
        // so is a pin's that leaves the band too little room.
        if tiledLayout() != before, !narrowsBand(column, from: room) { return true }
        setWidth(ofColumn: column, old)
        scrollOffset = offset
        return false
    }
}
