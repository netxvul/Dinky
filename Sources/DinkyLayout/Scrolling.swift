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

    /// Whether fullscreen here widens the window's column and pushes its neighbours off, rather than covering them.
    public var pushesFullscreen: Bool { isScrolling && fullscreenPushesStrip }

    /// The columns fullscreen widens to the whole screen: those holding a fullscreen window, when it pushes.
    var pushedColumns: Set<Int> {
        guard pushesFullscreen else { return [] }
        return Set(fullscreenWindows.compactMap { root.path(of: $0)?.first })
    }

    /// Put a window in a new column right of the focused one, at the default width.
    mutating func insertColumn(_ id: WindowID) {
        let index = focused.flatMap { root.path(of: $0) }.map { $0[0] + 1 } ?? root.children.count
        root.insert(.window(id), at: index)
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

    /// Where the columns go: inside the outer gaps, and with more than one column also clear of the parked
    /// windows' gutter on each side without a wall, by half an inner gap, which with a column's own half makes
    /// a whole one. Column widths are shares of its width.
    var stripArea: CGRect {
        let area = gaps.inset(bounds)
        guard root.children.count > 1 else { return area }
        let clear = Self.peek + gaps.horizontal / 2
        let left = walls.contains(.left) ? 0 : max(clear - gaps.left, 0)
        let right = walls.contains(.right) ? 0 : max(clear - gaps.right, 0)
        return CGRect(x: area.minX + left, y: area.minY, width: area.width - left - right, height: area.height)
    }

    /// Each column's start and width in points along the strip, from its left edge. Half an inner gap is part
    /// of a column on each side that has a neighbour, so neighbours end up a whole gap apart. A lone column is
    /// as wide as the screen; any other is its share of it, grown to fit its windows' minimum widths. A column in
    /// `pushed` is as wide as `area`, so with its half gaps it stays a whole gap from the gutters either side; at
    /// an end of the strip, where nothing is parked, it reaches on through the gutter out to the outer gap.
    func columnSpans(in area: CGRect, pushed: Set<Int> = []) -> [(start: CGFloat, width: CGFloat)] {
        let count = root.children.count, gap = gaps.horizontal
        var start: CGFloat = 0
        return root.children.indices.map { i in
            let insets = (i > 0 ? gap / 2 : 0) + (i < count - 1 ? gap / 2 : 0)
            let minimum = root.children[i].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
            let share = pushed.contains(i) ? area.width + endGutters(of: i, area).left + endGutters(of: i, area).right
                : (area.width * CGFloat(width(ofColumn: i))).rounded()
            let width = count == 1 ? area.width : max(share, minimum + insets)
            defer { start += width }
            return (start, width)
        }
    }

    /// The gutters beside column `index` at the ends of the strip, where nothing is parked: the width between `area`
    /// and the outer gap on the side with no column beyond it.
    func endGutters(of index: Int, _ area: CGRect) -> (left: CGFloat, right: CGFloat) {
        let inset = gaps.inset(bounds)
        return (index == 0 ? area.minX - inset.minX : 0, index == root.children.count - 1 ? inset.maxX - area.maxX : 0)
    }

    /// The scroll offset the layout uses. The strip never scrolls past either end, and the column at an end
    /// reaches into the gutter there, which nothing is parked in, out to the outer gap. A strip that fits
    /// between the outer gaps is centred. The focused column always shows whole, scrolled to as little as
    /// that takes, even when what scrolled it away left focus alone: a column closing or growing to its
    /// windows' minimum width left of it, or the display or gaps changing.
    func offset(for spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> CGFloat {
        let total = spans.last.map { $0.start + $0.width } ?? 0, inset = gaps.inset(bounds)
        let first = area.minX - inset.minX, last = total - area.width - (inset.maxX - area.maxX)
        guard first < last else { return (first + (total - inset.width) / 2).rounded() }
        let wanted = focused.flatMap { root.path(of: $0)?.first }.map { showing(spans[$0], from: scrollOffset, in: area) }
        return min(max(wanted ?? scrollOffset, first), last)
    }

    /// The offset nearest `offset` that shows `column` whole, as Hyprland's `fit` does. A column wider than the
    /// area is centred.
    func showing(_ column: (start: CGFloat, width: CGFloat), from offset: CGFloat, in area: CGRect) -> CGFloat {
        column.width > area.width
            ? column.start - (area.width - column.width) / 2
            : min(max(offset, column.start + column.width - area.width), column.start)
    }

    /// Scroll as little as shows the window's column whole.
    mutating func reveal(_ id: WindowID) {
        guard isScrolling, let index = root.path(of: id)?.first else { return }
        let area = stripArea, spans = columnSpans(in: area)
        scrollOffset = showing(spans[index], from: offset(for: spans, in: area), in: area)
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
        let gap = gaps.horizontal, last = root.children.count - 1
        var offset = offset(for: spans, in: area)
        let focusedColumn = focused.flatMap { root.path(of: $0)?.first }
        if let column = focusedColumn, pushed.contains(column) {
            offset = spans[column].start + endGutters(of: column, area).left
        }
        let fills = { (i: Int, id: WindowID) in
            pushedFullscreenFills && i == focusedColumn && pushed.contains(i) && fullscreenWindows.contains(id)
        }
        let unpushed = pushed.isEmpty ? spans : columnSpans(in: area)
        let edges = spans.indices.map { i -> (left: CGFloat, right: CGFloat) in
            let x = area.minX + spans[i].start - offset
            return ((x + (i > 0 ? gap / 2 : 0)).rounded(), (x + spans[i].width - (i < last ? gap / 2 : 0)).rounded())
        }
        let reaching: (left: Int?, right: Int?) = pushed.isEmpty ? reachingWalls(edges, in: area) : (nil, nil)
        result.containerRects[[]] = inset
        for i in root.stackingOrder {
            let trail = i < last ? gap / 2 : 0
            let x = area.minX + spans[i].start - offset
            let a = i == reaching.left ? inset.minX : edges[i].left
            let b = i == reaching.right ? inset.maxX : edges[i].right
            let rect = CGRect(x: a, y: area.minY, width: b - a, height: area.height)
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

    /// The column in view nearest each wall that reaches out to the outer gap there, if any. A column scrolled out past
    /// a wall hides behind the column in view nearest it (see `parked`) and leaves the room it had: half an inner gap,
    /// and at the far end of the strip the gutter there too, which the end column reaches into instead of a column
    /// parking in it. Not reached over, that room would show the screen's background between the column and the outer
    /// gap. Only less room than the narrowest column takes: more is a column's worth, as columns of other widths can
    /// leave, and the column keeps its width. `edges` are each column's window edges where the strip has it.
    func reachingWalls(_ edges: [(left: CGFloat, right: CGFloat)], in area: CGRect) -> (left: Int?, right: Int?) {
        let inset = gaps.inset(bounds), most = area.width * CGFloat(Self.minimumColumnWidth)
        let inView = edges.indices.filter { edges[$0].left >= bounds.minX - 1 && edges[$0].right <= bounds.maxX + 1 }
        let reaches = { (room: CGFloat) in room > 0 && room < most }
        let left = inView.first.flatMap { i in
            i > 0 && walls.contains(.left) && reaches(edges[i].left - inset.minX) ? i : nil
        }
        let right = inView.last.flatMap { i in
            i < edges.count - 1 && walls.contains(.right) && reaches(inset.maxX - edges[i].right) ? i : nil
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
        let columns = root.children.map(\.windows)
        return (columns[column], columns[..<column].reversed(), Array(columns[(column + 1)...]))
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
        let rank = Dictionary(uniqueKeysWithValues: root.stackingOrder.enumerated().map { ($1, $0) })
        func shows(_ column: Int, behind front: CGFloat, _ frontColumn: Int?) -> CGFloat {
            guard let frontColumn, rank[column]! > rank[frontColumn]! else { return Self.peek }
            return min(max(front - behind, Self.tuck), Self.peek)
        }
        var leftLimit: [WindowID: CGFloat] = [:], rightLimit: [WindowID: CGFloat] = [:]
        var front = CGFloat.infinity, frontColumn: Int?
        for (column, ids) in columns.enumerated().reversed() where !ids.isEmpty {
            let shows = shows(column, behind: front, frontColumn)
            front = -.infinity
            frontColumn = column
            for id in ids {
                let frame = frames[id]!, width = shownWidth(of: id, frame)
                let limit = (bounds.minX + (untuckable.contains(id) ? Self.peek : shows) - width).rounded(.up)
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
                let limit = (bounds.maxX - (untuckable.contains(id) ? Self.peek : shows)).rounded(.down)
                rightLimit[id] = limit
                front = max(front, bounds.maxX - min(frame.minX, limit))
            }
        }
        return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
            let offLeft = frame.minX < bounds.minX - 1, offRight = frame.maxX > bounds.maxX + 1
            if offLeft != offRight, walls.contains(offLeft ? .left : .right), let cover = offLeft ? left : right {
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
        guard isScrolling, let frame = stripLayout(pushed: pushedColumns).frames[id] else { return true }
        return frame.minX >= bounds.minX - 1 && frame.maxX <= bounds.maxX + 1
    }

    /// `move` in the strip. Left and right take a window that shares its column out into a new column on that
    /// side, and swap a column of its own with its neighbour. Up and down only move it within its column.
    mutating func moveInStrip(_ direction: Direction) -> Bool {
        guard let focused, let path = root.path(of: focused) else { return false }
        let column = path[0], forward = direction.isForward
        if direction.orientation == .horizontal {
            if path.count > 1 {
                let share = width(ofColumn: column)
                root.modify(at: Array(path.dropLast())) { $0.remove(at: path.last!) }
                root.insert(.window(focused), at: column + (forward ? 1 : 0))
                columnWidths[focused] = share
            } else {
                let other = column + (forward ? 1 : -1)
                guard root.children.indices.contains(other) else { return false }
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
        let share = width(ofColumn: neighbour)
        guard joinInTree(direction), let joined = root.path(of: focused)?.first else { return false }
        setWidth(ofColumn: joined, share)
        reveal(focused)
        return true
    }

    /// Grow (positive) or shrink the focused window's column by `delta` points. False when nothing visibly changed.
    mutating func resizeColumn(by delta: CGFloat) -> Bool {
        guard let focused, let column = root.path(of: focused)?.first else { return false }
        let old = width(ofColumn: column)
        let (before, offset) = (tiledLayout(), scrollOffset)
        setWidth(ofColumn: column, old + Double(delta / stripArea.width))
        reveal(focused)
        // A step a lone column or the minimum sizes swallow whole is undone, so the width does not drift out of sight.
        guard tiledLayout() == before else { return true }
        setWidth(ofColumn: column, old)
        scrollOffset = offset
        return false
    }
}
