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
// shadows hide too, and that column reaches out to the outer gap over the room they leave.
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

    /// Whether a column is pinned to either side.
    var hasPins: Bool { pinnedIndex(.left) != nil || pinnedIndex(.right) != nil }

    /// Whether the band's end column on each side has a pin beside it, which it keeps half a gap from, as from any
    /// neighbour.
    var bandNeighbours: (left: Bool, right: Bool) { (pinnedIndex(.left) != nil, pinnedIndex(.right) != nil) }

    /// The band's area on screen: inside the outer gaps, beside the pinned columns. The whole area inside the outer
    /// gaps when nothing is pinned.
    public var bandRect: CGRect { stripInset }

    /// The width a column's share is of: the strip's area as it is with nothing pinned, so pinning leaves the other
    /// columns' widths alone.
    var shareWidth: CGFloat {
        guard hasPins else { return stripArea.width }
        // Without the pins, and so without a pin's fullscreen, which would count as pushing the strip.
        var plain = self
        plain.fullscreenWindows.removeAll { pinSide(of: $0) != nil }
        plain.pins = [:]
        return plain.stripArea.width
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
    /// are shares of its width.
    var stripArea: CGRect {
        let area = stripInset, band = bandRange
        guard band.count > 1 else { return area }
        if pushedColumns.isEmpty, let end = columnSpans(in: area)[safe: band.upperBound - 1],
           end.start + end.width <= area.width { return area }
        let clear = Self.peek + gaps.horizontal / 2
        let left = walls.contains(.left) || pinnedIndex(.left) != nil ? 0 : max(clear - gaps.left, 0)
        let right = walls.contains(.right) || pinnedIndex(.right) != nil ? 0 : max(clear - gaps.right, 0)
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
        // as the band at most.
        let base = pinned ? shareWidth : area.width
        var start: CGFloat = 0
        return root.children.indices.map { i in
            // A pinned column has a place of its own (`pinRect`), not along the band.
            guard band.contains(i) else { return (0, pinSpan(i)) }
            let insets = (i > band.lowerBound || beside.left ? gap / 2 : 0)
                + (i < band.upperBound - 1 || beside.right ? gap / 2 : 0)
            let minimum = root.children[i].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
            let wide = (base * CGFloat(width(ofColumn: i))).rounded()
            let share = pushed.contains(i) ? area.width + endGutters(of: i, area).left + endGutters(of: i, area).right
                : pinned ? min(wide, area.width) : wide
            // A lone column fills the area, beside a pin no narrower than its windows take: it then hangs under the
            // pin, or is held off a wall (`parked`), rather than growing past it onto the next display.
            let lone = pinned ? max(area.width, minimum + insets) : area.width
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
        guard let limits = scrollLimits(for: spans, in: area) else {
            let total = bandEnd(of: spans), inset = stripInset
            return (area.minX - inset.minX + (total - inset.width) / 2).rounded()
        }
        // A focused column wider than the band, beside a pin, shows from the band's start though that scrolls the
        // strip on past its end, the rest of it under the pin.
        let wide = hasPins && focused.flatMap { bandIndex(of: $0) }.map { spans[$0].width > area.width } == true
        let upper = wide ? max(limits.upperBound, wanted ?? limits.upperBound) : limits.upperBound
        return min(max(wanted ?? scrollOffset, limits.lowerBound), upper)
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
    /// screen, to the middle as near as the strip's ends allow, or to the middle only when it did not all show.
    /// Columns that all fit stay centred as a whole. A strip a click held still (`holdsScroll`) is held no more, and
    /// fingers scrolling it freely (`freeScrollFrom`) let go.
    mutating func reveal(_ id: WindowID) {
        holdsScroll = false
        freeScrollFrom = nil
        guard isScrolling, let index = bandIndex(of: id) else { return }
        let area = stripArea, spans = columnSpans(in: area), column = spans[index]
        let shown = showing(column, from: offset(for: spans, in: area), in: area)
        switch columnCentring {
        case .never: scrollOffset = shown
        case .always, .alwaysFill: scrollOffset = centred(column, in: area)
        case .onOverflow:
            let before = offset(for: spans, in: area, showingFocus: false)
            scrollOffset = showing(column, from: before, in: area) == before ? shown : centred(column, in: area)
        }
    }

    /// Scrolls to the focused column as focusing it would have, now that the click that focused it with
    /// `holdingScroll` is done. Nothing while the strip holds no scroll: the focused column has been scrolled to.
    public mutating func revealFocus() {
        guard holdsScroll else { return }
        holdsScroll = false
        if let focused { reveal(focused) }
    }

    /// Whether focusing with `holdingScroll` holds the strip still: only where focusing can scroll a column to the
    /// middle, which takes the window from under the pointer that pressed it. Scrolling as little as shows the column
    /// whole leaves the pointer over the window, the part of it that showed staying on screen, so that scrolls at once as
    /// it always has. Not while a window is fullscreen: focusing ends fullscreen or hands it on, laying the strip out
    /// afresh anyway.
    var canHoldScroll: Bool { isScrolling && columnCentring != .never && fullscreenWindows.isEmpty }

    /// The scroll offset the strip shows at: `scrollOffset` as the layout takes it, within the ends, the focused
    /// column whole.
    var shownOffset: CGFloat {
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
            offset = spans[column].start + endGutters(of: column, area).left
        }
        // Not with a column pinned: the system's Fill would cover it.
        let fills = { (i: Int, id: WindowID) in
            pushedFullscreenFills && !self.hasPins && i == focusedColumn && pushed.contains(i)
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
        let reaching: (left: Int?, right: Int?) = pushed.isEmpty && freeScrollFrom == nil ? reachingWalls(edges, in: area)
            : (nil, nil)
        result.containerRects[[]] = inset
        let reach = stripInset
        for i in stripStackingOrder {
            let trail = i < last || beside.right ? gap / 2 : 0
            let x = area.minX + spans[i].start - offset
            let a = i == reaching.left ? reach.minX : edges[i].left
            let b = i == reaching.right ? reach.maxX : edges[i].right
            // A pinned column stays at its side whatever the scroll.
            let rect = band.contains(i) ? CGRect(x: a, y: area.minY, width: b - a, height: area.height) : pinRect(i)
            switch root.children[i] {
            case .window(let id):
                result.frames[id] = fills(i, id) ? inset : rect
                result.order.append(id)
            case .container(let c) where pushed.contains(i):
                let end = (x + unpushed[i].width - trail).rounded()
                let inner = CGRect(x: a, y: area.minY, width: end - a, height: area.height)
                c.layout(in: inner, gaps: gaps, padding: accordionPadding, minimums: minimumSizes, path: [i], into: &result)
                for id in Node.container(c).windows where fullscreenWindows.contains(id) {
                    result.frames[id] = fills(i, id) ? inset : rect
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

    /// The column in view nearest each wall that reaches out to the outer gap there, if any. A column scrolled out past
    /// a wall hides behind the column in view nearest it (see `parked`) and leaves the room it had: half an inner gap,
    /// and at the far end of the strip the gutter there too, which the end column reaches into instead of a column
    /// parking in it. Not reached over, that room would show the screen's background between the column and the outer
    /// gap. Only less room than the narrowest column takes: more is a column's worth, as columns of other widths can
    /// leave, and the column keeps its width. Not on a pinned side: the pin is there, a gap from the band.
    /// `edges` are each column's window edges where the strip has it.
    func reachingWalls(_ edges: [(left: CGFloat, right: CGFloat)], in area: CGRect) -> (left: Int?, right: Int?) {
        let inset = stripInset, band = bandRange, most = area.width * CGFloat(Self.minimumColumnWidth)
        let inView = band.filter { edges[$0].left >= bounds.minX - 1 && edges[$0].right <= bounds.maxX + 1 }
        let reaches = { (room: CGFloat) in room > 0 && room < most }
        let left = inView.first.flatMap { i in
            i > band.lowerBound && walls.contains(.left) && pinnedIndex(.left) == nil && reaches(edges[i].left - inset.minX)
                ? i : nil
        }
        let right = inView.last.flatMap { i in
            i < band.upperBound - 1 && walls.contains(.right) && pinnedIndex(.right) == nil
                && reaches(inset.maxX - edges[i].right) ? i : nil
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
    /// them.
    public func placeStrip(_ frames: [WindowID: CGRect]) -> [WindowID: CGRect] { parked(frames) }

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
    func parked(_ frames: [WindowID: CGRect]) -> [WindowID: CGRect] {
        let keepsSize = !pushedColumns.isEmpty
        let columns = root.children.map { $0.windows.filter { frames[$0] != nil } }
        let covers = columns.compactMap { ids -> CGRect? in
            let rects = ids.map { frames[$0]! }
            guard !rects.isEmpty, rects.allSatisfy({ $0.minX >= bounds.minX - 1 && $0.maxX <= bounds.maxX + 1 }) else { return nil }
            return rects.max { $0.width * $0.height < $1.width * $1.height }
        }
        let left = covers.min { $0.minX < $1.minX }, right = covers.max { $0.maxX < $1.maxX }
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
        let tucked = (left: pinnedIndex(.left) != nil, right: pinnedIndex(.right) != nil)
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
        // A band window as wide as the band or wider, beside a pin, is the one in view there: past a wall it is held
        // off it, hanging under the pin, not hidden behind a column in view.
        let band = hasPins ? bandRect : .null
        let spans = { (frame: CGRect) in !band.isNull && frame.minX <= band.minX + 1 && frame.maxX >= band.maxX - 1 }
        return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
            let offLeft = frame.minX < bounds.minX - 1, offRight = frame.maxX > bounds.maxX + 1
            if offLeft != offRight, walls.contains(offLeft ? .left : .right), let cover = offLeft ? left : right,
               pinSide(of: id) != nil || !spans(frame) {
                return (id, hiddenAtWall(id, frame, behind: cover, wall: offLeft ? .left : .right, keepsSize: keepsSize))
            }
            var x = frame.minX
            x = min(x, walls.contains(.right) ? bounds.maxX - frame.width : rightLimit[id] ?? bounds.maxX - Self.peek)
            x = max(x, walls.contains(.left) ? bounds.minX : leftLimit[id] ?? bounds.minX + Self.peek - frame.width)
            return (id, CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height))
        })
    }

    /// Where a window scrolled out past `wall` hides behind `cover`, the biggest window of the column in view nearest
    /// the wall: `shadowReach` inside it all round, so its shadow hides there too and the column shows one window's
    /// shadow, not one more for each window behind it. Grown to its minimum size, it stays inside the cover as far as
    /// it fits, and past that hangs out away from the wall and downwards. While fullscreen pushes (`keepsSize`), the
    /// cover is the fullscreen window, and it grows no bigger than it is, but still keeps `shadowReach` inside: as tall
    /// as the fullscreen window, it would show its shadow above and below it, one more for each window behind.
    func hiddenAtWall(_ id: WindowID, _ frame: CGRect, behind cover: CGRect, wall: Direction, keepsSize: Bool) -> CGRect {
        let minimum = minimumSizes[id] ?? .zero, margins = Self.shadowReach * 2
        let width = max(min(keepsSize ? frame.width : .infinity, cover.width - margins), minimum.width, 1)
        let height = max(min(keepsSize ? frame.height : .infinity, cover.height - margins), minimum.height, 1)
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
        return path.count > 1 && moveInTree(direction)
    }

    /// `join-with` in the strip: left and right put the window into the neighbouring column, at that column's
    /// width; up and down work as in any tree, within the column.
    mutating func joinInStrip(_ direction: Direction) -> Bool {
        guard direction.orientation == .horizontal, let focused, let column = root.path(of: focused)?.first else {
            return joinInTree(direction)
        }
        let neighbour = column + (direction.isForward ? 1 : -1)
        guard root.children.indices.contains(neighbour) else { return false }
        // Out of a pin of its own it unpins; into a pin, it stacks there at the pin's width.
        if let side = pinSide(ofColumn: column), PinSide(direction) == side { return false }
        let share = width(ofColumn: neighbour)
        var joining = self
        joining.rekeyPins(leaving: focused)
        guard joining.joinInTree(direction), let joined = joining.root.path(of: focused)?.first else { return false }
        self = joining
        setWidth(ofColumn: joined, share)
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
        setWidth(ofColumn: column, shown + Double(delta / (pinned ? gaps.inset(bounds).width : shareWidth)))
        reveal(focused)
        // A step a lone column or the minimum sizes swallow whole is undone, so the width does not drift out of sight;
        // so is a pin's that leaves the band too little room.
        if tiledLayout() != before, !narrowsBand(column, from: room) { return true }
        setWidth(ofColumn: column, old)
        scrollOffset = offset
        return false
    }
}
