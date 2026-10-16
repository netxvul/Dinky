import CoreGraphics

// The scrolling layout, after Hyprland's (and niri's): the root is a row of columns, each a window or a stack of
// windows, as wide as its own share of the screen whatever the number of columns, so the row runs past the
// screen edges and scrolls to keep the focused column in view. A lone column fills the screen, columns that fit
// are centred, and focusing a column scrolls just far enough to show it whole.
//
// macOS cannot clip another app's window at the screen edge, so a window scrolled out of view is parked
// instead: on an edge with nothing beyond it, the column nearest the screen hangs off it with `peek` points left
// on, in a gutter the columns keep an inner gap clear of, and the columns beyond tuck under that one with only
// `tuck` points left on, so a single shadow shows at the edge rather than one per parked window piled up; on an
// edge with another display beyond it, a window stops flush at the border, behind the columns in view, so it
// never shows on the other display.
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
    static let tuck: CGFloat = 2

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
    /// `pushed` is as wide as `area`, so with its half gaps it stays a whole gap from the gutters either side.
    func columnSpans(in area: CGRect, pushed: Set<Int> = []) -> [(start: CGFloat, width: CGFloat)] {
        let count = root.children.count, gap = gaps.horizontal
        var start: CGFloat = 0
        return root.children.indices.map { i in
            let insets = (i > 0 ? gap / 2 : 0) + (i < count - 1 ? gap / 2 : 0)
            let minimum = root.children[i].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
            let share = pushed.contains(i) ? area.width : (area.width * CGFloat(width(ofColumn: i))).rounded()
            let width = count == 1 ? area.width : max(share, minimum + insets)
            defer { start += width }
            return (start, width)
        }
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
    /// column keep the width the column has otherwise, behind its fullscreen window.
    func stripLayout(pushed: Set<Int> = []) -> Layout {
        var result = Layout()
        let area = stripArea, spans = columnSpans(in: area, pushed: pushed), inset = gaps.inset(bounds)
        let gap = gaps.horizontal, last = root.children.count - 1
        var offset = offset(for: spans, in: area)
        if let column = focused.flatMap({ root.path(of: $0)?.first }), pushed.contains(column) {
            offset = spans[column].start
        }
        let unpushed = pushed.isEmpty ? spans : columnSpans(in: area)
        result.containerRects[[]] = inset
        for i in root.stackingOrder {
            let span = spans[i]
            let lead = i > 0 ? gap / 2 : 0, trail = i < last ? gap / 2 : 0
            let x = area.minX + span.start - offset
            let (a, b) = ((x + lead).rounded(), (x + span.width - trail).rounded())
            let rect = CGRect(x: a, y: area.minY, width: b - a, height: area.height)
            switch root.children[i] {
            case .window(let id):
                result.frames[id] = rect
                result.order.append(id)
            case .container(let c) where pushed.contains(i):
                let end = (x + unpushed[i].width - trail).rounded()
                let inner = CGRect(x: a, y: area.minY, width: end - a, height: area.height)
                c.layout(in: inner, gaps: gaps, padding: accordionPadding, minimums: minimumSizes, path: [i], into: &result)
                for id in Node.container(c).windows where fullscreenWindows.contains(id) { result.frames[id] = rect }
            case .container(let c):
                c.layout(in: rect, gaps: gaps, padding: accordionPadding, minimums: minimumSizes, path: [i], into: &result)
            }
        }
        return result
    }

    /// Scrolling: the strip's frames before parking, at the current scroll offset. Gliding these and parking them
    /// on every frame (`placeStrip`) scrolls the strip as one: a column passing through slides across the screen
    /// where the strip has it, rather than every parked window flying straight from one edge to the other.
    public var stripFrames: [WindowID: CGRect] {
        isScrolling ? stripLayout(pushed: pushedColumns).frames : [:]
    }

    /// Where strip frames, such as `stripFrames` part way through a glide, go on screen: parked as `layout()` parks
    /// them.
    public func placeStrip(_ frames: [WindowID: CGRect]) -> [WindowID: CGRect] { parked(frames) }

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
    /// column in view nearest the wall, taking the frame of that column's biggest window, so none of it shows in
    /// the outer gap, between the columns, or between the windows of a column of several. It only grows past that
    /// frame to its minimum size, away from the wall. With no column in view it stays flush at the wall. While
    /// fullscreen pushes, the column in view is the fullscreen window's, so a window hiding behind it keeps its own
    /// size rather than taking the whole screen's.
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
                let minimum = minimumSizes[id] ?? .zero
                let width = keepsSize ? frame.width : max(cover.width, minimum.width)
                let height = keepsSize ? frame.height : max(cover.height, minimum.height)
                return (id, CGRect(x: offLeft ? cover.minX : cover.maxX - width, y: cover.minY, width: width, height: height))
            }
            var x = frame.minX
            x = min(x, walls.contains(.right) ? bounds.maxX - frame.width : rightLimit[id] ?? bounds.maxX - Self.peek)
            x = max(x, walls.contains(.left) ? bounds.minX : leftLimit[id] ?? bounds.minX + Self.peek - frame.width)
            return (id, CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height))
        })
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
