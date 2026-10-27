import CoreGraphics

/// How new windows are placed in a workspace. Dwindle carries the root's layout mode.
public enum TilingAlgorithm: Equatable, Sendable {
    case dwindle(LayoutMode)
    case fixed(rows: Int, columns: Int, expand: FixedExpansion)
    /// A strip of columns wider than the screen, scrolled to the focused one. See Scrolling.swift.
    case scrolling
}

public enum FixedExpansion: Equatable, Sendable {
    case rows, columns, accordion
}

/// What focusing another window of the workspace does while one is fullscreen: end fullscreen, hand it to the
/// newly focused window, or show that one fullscreen too.
public enum FullscreenFocus: String, Equatable, Sendable {
    case exit, follow, keep
}

/// Where focusing a scrolling column scrolls it: just far enough to show it whole, to the middle of the screen, to
/// the middle but never past the strip's ends, or to the middle only when it was not all in view, as niri's
/// `center-focused-column`.
public enum ColumnCentring: String, Equatable, Sendable {
    case never, always
    case alwaysFill = "always-fill"
    case onOverflow = "on-overflow"

    /// Whether the strip scrolls past its ends to centre the first or last column, the screen bare beyond it.
    var centresEnds: Bool { self == .always || self == .onOverflow }
}

/// One Space's tiling state: the tree, focus, fullscreen and the geometry settings used to lay it out.
public struct Workspace: Equatable, Sendable {
    /// The Space's visible rect, top-left origin.
    public var bounds: CGRect
    public var gaps: Gaps
    public var accordionPadding: CGFloat
    /// Whether a container switching to accordion follows its longer side (`auto`), unless a `layout` command
    /// chose its orientation.
    public var autoOrientAccordions: Bool
    public private(set) var algorithm: TilingAlgorithm
    /// The tree. The root is always a container, possibly empty.
    public internal(set) var root: Container
    /// The focused window, if any.
    public internal(set) var focused: WindowID?
    /// Windows shown fullscreen over the tree, most recently focused first. When there are any, the focused window
    /// is the first. Focusing another window does what `fullscreenFocus` says; any layout command ends fullscreen.
    public internal(set) var fullscreenWindows: [WindowID] = []
    /// What focusing another window does while one is fullscreen.
    public var fullscreenFocus = FullscreenFocus.exit
    /// With `follow`, whether the newly focused window waits until the coordinator promotes it, so the window it took
    /// focus from is back in its tile first. Off, it goes fullscreen at once.
    public var fullscreenFollowsLater = false
    /// Scrolling: whether fullscreen widens the window's column across the screen and pushes its neighbours off it,
    /// rather than covering them where they are. See Scrolling.swift.
    public var fullscreenPushesStrip = true
    /// Scrolling, while fullscreen pushes: whether the focused fullscreen window fills the area inside the outer gaps,
    /// over its neighbours' peeks, rather than the strip's area between them. Where macOS's own Fill puts a window, so
    /// the system can animate it there itself.
    public var pushedFullscreenFills = false
    /// The focused window waiting to go fullscreen with `fullscreenFollowsLater`. See `promotePendingFullscreen`.
    public internal(set) var pendingFullscreen: WindowID?
    /// The window shown fullscreen in front, if any: the focused one.
    public var fullscreen: WindowID? { fullscreenWindows.first }
    /// Sizes windows refused to go below. Tiles grow to them when their siblings can give the space.
    public var minimumSizes: [WindowID: CGSize] = [:]
    /// Scrolling: each window's width as last seen on screen, which an app that snaps its size leaves a little
    /// off its tile's. See `shownWidth(of:_:)`.
    public var observedWidths: [WindowID: CGFloat] = [:]
    /// Scrolling: windows that would not stay tucked under the nearest parked column, so they park at `peek`.
    public var untuckable: Set<WindowID> = []
    /// Scrolling: the width of a new column, as a share of the width inside the outer gaps.
    public var columnWidth = 0.5
    /// Scrolling: where focusing a column scrolls it. See `reveal(_:)`.
    public var columnCentring = ColumnCentring.never
    /// Scrolling: each window's column width, as a share. Every window of a column has its column's width.
    var columnWidths: [WindowID: Double] = [:]
    /// Scrolling: the columns pinned to the screen's sides, each by one of its windows. The slot decides: the left one
    /// is the first column, the right one the last; the window only confirms which. See Pins.swift.
    public internal(set) var pins: [PinSide: WindowID] = [:]
    /// Scrolling: where each pinned column was in the band as it was pinned, to go back to as it is unpinned.
    var pinOrigins: [PinSide: PinOrigin] = [:]
    /// Scrolling: the band window focused last, which focus goes back to from a pin and the band's stacking follows.
    public internal(set) var bandFocus: WindowID?
    /// Scrolling: pinned windows away for a while, minimized, hidden or floated, pinned again as they come back to a
    /// side still free.
    public var departedPins: [PinSide: WindowID] = [:]
    /// Scrolling: the width each departed pin had, which it takes again as it comes back.
    var departedWidths: [WindowID: Double] = [:]
    /// Scrolling: where each departed pin was pinned from, which unpinning it goes back to once it is pinned again.
    var departedOrigins: [WindowID: PinOrigin] = [:]
    /// Scrolling: the side pinned last, whose pin narrows first where the band needs room (see `fitBand`).
    var lastPinned: PinSide?
    /// Scrolling: how far the strip is scrolled, in points from its start. The layout clamps it.
    var scrollOffset: CGFloat = 0
    /// Scrolling: the layout keeps `scrollOffset` past the strip's ends, as `scroll(columnOf:to:pastEnds:)` leaves it.
    public var keepsScroll = false
    /// Scrolling: the strip stays where it showed as focus moved, the focused column not scrolled to, till
    /// `revealFocus()`: a click focused it, and a strip scrolled under the pressed button would take the window from
    /// under the pointer. See `focus(_:holdingScroll:)`.
    public internal(set) var holdsScroll = false
    /// Scrolling: where the strip showed as fingers took hold of it to scroll it freely, while they do: the layout
    /// keeps `scrollOffset` within the ends meanwhile, the focused column not scrolled to. Nil otherwise. See
    /// FreeScroll.swift.
    var freeScrollFrom: CGFloat?
    /// Scrolling: the edges of `bounds` with another display beyond them, where a window cannot hang over.
    public var walls: Set<Direction> = []
    /// Scrolling: the two displays side by side one strip runs across (`[scrolling] span-displays`), `bounds` being both;
    /// nil on one display. See Span.swift.
    public internal(set) var seam: Seam?
    /// Scrolling across a seam: which display focusing a column centres it on, with `columnCentring` other than
    /// `never`. See Span.swift.
    public var spanCentring = SpanCentring.both
    /// Scrolling across a seam: whether columns scrolled off the outer edges peek out there, in gutters kept for them, as
    /// on one display; off, they tuck under the column in view with only `tuck` points on, and nothing keeps a gutter.
    public var spanPeeks = true
    /// The band column focus moved from, for the `reveal` it is moving with: the way it steps along the strip.
    var revealingFrom: Int?
    /// The algorithm a `layout` command switched to, kept over the config's. Nil follows the config.
    public var chosenAlgorithm: TilingAlgorithm?

    /// An empty workspace laid out by `algorithm`. A dwindle accordion root with `autoOrientAccordions` starts
    /// `auto`, as a container switched to accordion would, so it runs top to bottom on a tall display.
    public init(bounds: CGRect, gaps: Gaps = .zero, accordionPadding: CGFloat = 30, autoOrientAccordions: Bool = false,
                algorithm: TilingAlgorithm = .dwindle(.tiles)) {
        self.bounds = bounds
        self.gaps = gaps
        self.accordionPadding = accordionPadding
        self.autoOrientAccordions = autoOrientAccordions
        self.algorithm = algorithm
        switch algorithm {
        case .dwindle(let mode):
            root = Container(mode == .accordion && autoOrientAccordions ? .auto : .horizontal, mode)
        case .fixed(let rows, let columns, _):
            precondition(rows > 0 && columns > 0)
            root = Self.fixedRoot(rows: rows, columns: columns)
        case .scrolling:
            root = Container(.horizontal)
        }
    }

    /// All windows in tree order.
    public var windows: [WindowID] { Node.container(root).windows }

    /// Whether the window is tiled here.
    public func contains(_ id: WindowID) -> Bool { root.path(of: id) != nil }

    /// Insert a window and focus it. Fixed workspaces fill empty cells before expanding. If a tree command
    /// has changed the template structure, use the focused-leaf split instead of discarding the edits.
    public mutating func insert(_ id: WindowID) {
        guard !contains(id) else { return }
        if case .fixed(let rows, let columns, _) = algorithm, windows.isEmpty, !isFixedTree {
            root = Self.fixedRoot(rows: rows, columns: columns)
        }
        if case .fixed(_, _, let expansion) = algorithm, insertIntoFixed(id, expand: expansion) {
            return focus(id)
        }
        if isScrolling {
            insertColumn(id)
            return focus(id)
        }
        guard let focused, let path = root.path(of: focused) else {
            root.insert(.window(id), at: root.children.count)
            return focus(id)
        }
        let layout = tiledLayout(), leaf = layout.frames[focused] ?? gaps.inset(bounds)
        let axis: Orientation = leaf.width >= leaf.height ? .horizontal : .vertical
        let parentPath = Array(path.dropLast()), index = path.last!
        let joins = axisOfContainer(at: parentPath, in: layout) == axis || root.container(at: parentPath).children.count == 1
        root.modify(at: parentPath) { parent in
            if parent.children.count == 1, parent.orientation != .auto { parent.orientation = ContainerOrientation(axis) }
            if joins || parent.mode == .accordion {
                parent.insert(.window(id), at: index + 1)
            } else {
                parent.replace(at: index, with: .container(Container(ContainerOrientation(axis), .tiles, [.window(focused), .window(id)])))
            }
        }
        focus(id)
    }

    /// Remove a window. Its share goes to its siblings, redundant containers collapse.
    /// If it was focused, focus moves to the window that took its place.
    public mutating func remove(_ id: WindowID) {
        // What the pins remember of it goes, in any layout and whether it is in the tree or away: its id may come back as
        // another window's.
        forgetPinned(id)
        guard let path = root.path(of: id) else { return }
        // A pinned column it closes is unpinned, focus going back to the band; the last band column closing, to the
        // one beside it in the band rather than to the pin the root's focus would land on.
        let column = path[0], inBand = bandIndex(of: id) != nil, pinnedSide = pinSide(of: id)
        let lone = root.children[column].windows.count == 1
        rekeyPins(leaving: id)
        if case .fixed = algorithm, isFixedTree {
            removeFixedWindow(at: path)
            trimEmptyOverflow()
        } else {
            root.modify(at: Array(path.dropLast())) { $0.remove(at: path.last!) }
            normalize()
        }
        if windows.isEmpty, case .fixed(let rows, let columns, _) = algorithm {
            root = Self.fixedRoot(rows: rows, columns: columns)
        }
        columnWidths[id] = nil
        observedWidths[id] = nil
        untuckable.remove(id)
        let wasFullscreen = fullscreenWindows.contains(id)
        if focused == id {
            focused = nil
            let band = bandRange
            let next: WindowID? = if let pinnedSide, lone, let back = bandReturn(from: pinnedSide) {
                back
            } else if isScrolling, inBand, lone, !band.isEmpty {
                Node.container(root).windows.isEmpty ? nil : {
                    switch root.children[min(max(column, band.lowerBound), band.upperBound - 1)] {
                    case .window(let id): return id
                    case .container(let c): return c.mostRecentWindow
                    }
                }()
            } else {
                root.mostRecentWindow ?? windows.first
            }
            // Focus moves on as fullscreen says first: with `follow` the next window takes over the screen, at once
            // when the fullscreen window has gone, since there is nothing to wait for.
            if let next = next ?? root.mostRecentWindow ?? windows.first {
                focus(next)
                if wasFullscreen { _ = promotePendingFullscreen(next) }
            }
        }
        fullscreenWindows.removeAll { $0 == id }
        if pendingFullscreen == id { pendingFullscreen = nil }
    }

    static var emptyCell: Node { .container(Container(.horizontal)) }

    mutating func removeFixedWindow(at path: [Int]) {
        let cell = Array(path.prefix(2))
        if path.count == 3, case .container(let stack) = root.node(at: cell) {
            root.modify(at: cell) { $0.remove(at: path[2]) }
            if stack.children.count == 2, case .container(let remaining) = root.node(at: cell) {
                root.modify(at: [cell[0]]) { $0.replace(at: cell[1], with: remaining.children[0]) }
            }
        } else {
            root.modify(at: [cell[0]]) { $0.replace(at: cell[1], with: Self.emptyCell) }
        }
    }

    /// Reserved cells stay; trailing rows or columns created by overflow disappear once empty.
    mutating func trimEmptyOverflow() {
        guard case .fixed(let reservedRows, let reservedColumns, let expand) = algorithm else { return }
        switch expand {
        case .columns:
            while root.children.count > reservedColumns, root.children.last!.windows.isEmpty {
                root.remove(at: root.children.count - 1)
            }
        case .rows:
            while root.container(at: [0]).children.count > reservedRows {
                let last = root.container(at: [0]).children.count - 1
                guard root.children.indices.allSatisfy({ root.node(at: [$0, last]).windows.isEmpty }) else { break }
                for column in root.children.indices { root.modify(at: [column]) { $0.remove(at: last) } }
            }
        case .accordion: break
        }
    }

    private static func fixedColumn(rows: Int) -> Node {
        .container(Container(.vertical, .tiles, (0..<rows).map { _ in emptyCell }))
    }

    private static func fixedRoot(rows: Int, columns: Int) -> Container {
        Container(.horizontal, .tiles, (0..<columns).map { _ in fixedColumn(rows: rows) })
    }

    /// Recognize the template in the tree. A manual tree command may break this shape; it must not be
    /// silently undone just because another window appeared.
    var isFixedTree: Bool {
        guard root.orientation == .horizontal, root.mode == .tiles,
              let first = root.children.first, case .container(let firstColumn) = first,
              !firstColumn.children.isEmpty else { return false }
        return root.children.allSatisfy { node in
            guard case .container(let column) = node, column.orientation == .vertical,
                  column.mode == .tiles, column.children.count == firstColumn.children.count else { return false }
            return column.children.allSatisfy { cell in
                switch cell {
                case .window: true
                case .container(let c): c.children.isEmpty || (c.mode == .accordion
                    && c.children.allSatisfy { if case .window = $0 { true } else { false } })
                }
            }
        }
    }

    /// Fill the first hole in row-major order, or add a row/column, or stack in the last cell.
    private mutating func insertIntoFixed(_ id: WindowID, expand: FixedExpansion) -> Bool {
        guard isFixedTree else { return false }
        let rows = root.container(at: [0]).children.count
        let columns = root.children.count
        for row in 0..<rows {
            for column in 0..<columns where root.node(at: [column, row]).windows.isEmpty {
                root.modify(at: [column]) { $0.replace(at: row, with: .window(id)) }
                return true
            }
        }
        switch expand {
        case .columns:
            root.insert(Self.fixedColumn(rows: rows), at: columns)
            root.modify(at: [columns]) { $0.replace(at: 0, with: .window(id)) }
        case .rows:
            for column in 0..<columns { root.modify(at: [column]) { $0.insert(Self.emptyCell, at: rows) } }
            root.modify(at: [0]) { $0.replace(at: rows, with: .window(id)) }
        case .accordion:
            let cell = [columns - 1, rows - 1]
            switch root.node(at: cell) {
            case .window(let existing):
                root.modify(at: [cell[0]]) { $0.replace(at: cell[1], with: .container(Container(.horizontal, .accordion, [.window(existing), .window(id)]))) }
            case .container:
                root.modify(at: cell) { $0.insert(.window(id), at: $0.children.count) }
            }
        }
        return true
    }

    private var fixedWindows: [WindowID] {
        let rows = root.container(at: [0]).children.count
        return (0..<rows).flatMap { row in
            root.children.indices.flatMap { root.node(at: [$0, row]).windows }
        }
    }

    /// Switch algorithms. Changing the template deliberately rearranges the existing windows once.
    public mutating func setAlgorithm(_ new: TilingAlgorithm) {
        guard algorithm != new else { return }
        let wasStrip = isScrolling
        algorithm = new
        rebuild(fromStrip: wasStrip)
    }

    /// Lay the windows out afresh in the configured layout, keeping their order and focus.
    private mutating func rebuild(fromStrip: Bool? = nil) {
        let fromStrip = fromStrip ?? isScrolling
        let ids = isFixedTree ? fixedWindows : windows
        switch algorithm {
        case .dwindle(let mode):
            root = Container(mode == .accordion && autoOrientAccordions ? .auto : .horizontal, mode, ids.map(Node.window))
        case .fixed(let rows, let columns, let expand):
            root = Self.fixedRoot(rows: rows, columns: columns)
            for id in ids { _ = insertIntoFixed(id, expand: expand) }
        case .scrolling:
            // A pinned column stays whole at its end; one pinned while the strip was another layout comes back as a
            // column of its own window there.
            let ends = PinSide.allCases.map { side -> Node? in
                guard let id = pins[side], ids.contains(id) else { return nil }
                return fromStrip ? pinnedIndex(side).map { root.children[$0] } ?? .window(id) : .window(id)
            }
            let pinned = Set(ends.compactMap { $0?.windows }.joined())
            let band = ids.filter { !pinned.contains($0) }.map(Node.window)
            root = Container(.horizontal, .tiles, [ends[0]].compactMap { $0 } + band + [ends[1]].compactMap { $0 })
            for id in ids { columnWidths[id] = columnWidths[id] ?? columnWidth }
            settlePins()
            // Back from another layout, the pins it kept may leave too little room on this display now: the band's own
            // room first, as a display change fits a strip, then the pins.
            if !fromStrip {
                fitBand()
                fitPins()
            }
        }
        if let focused { focus(focused) }
    }

    /// Put `new` in `old`'s place, keeping its size, focus and fullscreen: another tab of the same native tab group
    /// became the one shown. Does nothing if `old` is not here or `new` already is.
    public mutating func replace(_ old: WindowID, with new: WindowID) {
        guard let path = root.path(of: old), !contains(new) else { return }
        root.modify(at: Array(path.dropLast())) { $0.replace(at: path.last!, with: .window(new)) }
        if focused == old { focused = new }
        if bandFocus == old { bandFocus = new }
        for side in PinSide.allCases {
            if pins[side] == old { pins[side] = new }
            if departedPins[side] == old { departedPins[side] = new }
            if pinOrigins[side]?.before == old { pinOrigins[side]?.before = new }
            if pinOrigins[side]?.after == old { pinOrigins[side]?.after = new }
        }
        if let origin = departedOrigins.removeValue(forKey: old) { departedOrigins[new] = origin }
        if let share = departedWidths.removeValue(forKey: old) { departedWidths[new] = share }
        for (departed, origin) in departedOrigins {
            if origin.before == old { departedOrigins[departed]?.before = new }
            if origin.after == old { departedOrigins[departed]?.after = new }
        }
        fullscreenWindows = fullscreenWindows.map { $0 == old ? new : $0 }
        if pendingFullscreen == old { pendingFullscreen = new }
        minimumSizes[old] = nil
        columnWidths[new] = columnWidths.removeValue(forKey: old)
    }

    /// Undo every tree edit: the windows go back into the configured layout, in order, with equal ratios.
    public mutating func flatten() {
        endFullscreen()
        rebuild()
    }

    /// Focus a window and mark it most recent along its path, so accordions show it on top. While a window is
    /// fullscreen, focusing another ends fullscreen, hands it over or adds the window, as `fullscreenFocus` says.
    /// With `holdingScroll`, as for a click whose button may still be down, a strip stays where it shows till
    /// `revealFocus()`, whether focusing would centre the column or only bring it into view, unless a window is
    /// fullscreen (see `canHoldScroll`).
    public mutating func focus(_ id: WindowID, holdingScroll: Bool = false) {
        guard let path = root.path(of: id) else { return }
        // Pinned where the strip shows before focus moves, which can be past `scrollOffset`: the layout scrolls on from
        // there to show the focused column whole.
        let held: CGFloat? = holdingScroll && canHoldScroll ? shownOffset : nil
        // From the band to a pin, the band stays where it shows: the layout no longer scrolls to a focused column there.
        if isScrolling, let from = focused, from != id, bandIndex(of: from) != nil, pinSide(of: id) != nil {
            scrollOffset = shownOffset
        }
        if focused != id, !fullscreenWindows.isEmpty || pendingFullscreen != nil {
            pendingFullscreen = nil
            switch fullscreenFocus {
            case .exit: fullscreenWindows = []
            case .follow where fullscreenFollowsLater:
                fullscreenWindows = []
                pendingFullscreen = id
            case .follow: fullscreenWindows = [id]
            case .keep: fullscreenWindows = [id] + fullscreenWindows.filter { $0 != id }
            }
        }
        let previousColumn = focused.flatMap { bandIndex(of: $0) }
        focused = id
        if bandIndex(of: id) != nil { bandFocus = id }
        for depth in path.indices {
            root.modify(at: Array(path.prefix(depth))) { $0.active = path[depth] }
        }
        if let held {
            scrollOffset = held
            holdsScroll = true
        } else {
            revealingFrom = previousColumn
            reveal(id)
        }
    }

    /// Focus the neighbour in `direction`. At the edge, `wrapping` focuses the window at the opposite edge
    /// instead. Returns false when there is nothing to focus.
    @discardableResult
    public mutating func focus(_ direction: Direction, wrapping: Bool = false) -> Bool {
        guard let focused else { return false }
        // From a pin, its own windows first, as across a pinned accordion; past them, outwards nothing, or with
        // `wrapping` the far end, and inwards back to the band window focused last.
        if isScrolling, let side = pinSide(of: focused), let across = PinSide(direction) {
            let column = root.path(of: focused)?.first
            if let within = neighbor(of: focused, direction), root.path(of: within)?.first == column {
                focus(within)
                return true
            }
            if across == side {
                guard wrapping, let far = edgeWindow(direction.opposite), far != focused else { return false }
                focus(far)
                return true
            }
            guard let back = bandReturn(from: side) else { return focusOtherPin(than: side) }
            focus(back)
            return true
        }
        guard let target = neighbor(of: focused, direction) ?? (wrapping ? edgeWindow(direction.opposite) : nil),
              target != focused else { return false }
        focus(target)
        return true
    }

    /// Focus the column pinned opposite `side`, with no band between: false with none.
    private mutating func focusOtherPin(than side: PinSide) -> Bool {
        let other: PinSide = side == .left ? .right : .left
        guard let index = pinnedIndex(other) else { return false }
        let id: WindowID? = switch root.children[index] {
        case .window(let id): id
        case .container(let c): c.mostRecentWindow
        }
        guard let id else { return false }
        focus(id)
        return true
    }

    /// The window snapped to the `side` edge: containers along that axis give their first or last child,
    /// the others their most recently focused one. Adapted from AeroSpace's findLeafWindowRecursive(snappedTo:).
    public func edgeWindow(_ side: Direction) -> WindowID? {
        if case .fixed = algorithm, isFixedTree {
            // A boundary cell may be empty. Find the outermost occupied one instead of descending into a hole.
            let frames = tiledLayout().frames
            let focusedFrame = focused.flatMap { frames[$0] }
            func rank(_ frame: CGRect) -> (CGFloat, CGFloat) {
                let edge: CGFloat = switch side {
                case .left: frame.minX
                case .right: -frame.maxX
                case .up: frame.minY
                case .down: -frame.maxY
                }
                let across = side.orientation == .horizontal
                    ? abs(frame.midY - (focusedFrame?.midY ?? bounds.midY))
                    : abs(frame.midX - (focusedFrame?.midX ?? bounds.midX))
                return (edge, across)
            }
            return frames.keys.min { a, b in
                let first = rank(frames[a]!), second = rank(frames[b]!)
                return first == second ? a < b : first < second
            }
        }
        let layout = tiledLayout()
        var container = root, path: [Int] = []
        while !container.children.isEmpty {
            let index = axisOfContainer(at: path, in: layout) != side.orientation ? container.activeIndex
                : side.isForward ? container.children.count - 1 : 0
            switch container.children[index] {
            case .window(let id): return id
            case .container(let c): (container, path) = (c, path + [index])
            }
        }
        return nil
    }

    /// Give every container in the tree equal ratios.
    public mutating func balanceSizes() {
        endFullscreen()
        root.balance()
        // Pins too, so long as the band keeps room; else they keep their widths.
        let kept = pinnedWindows.map { ($0, columnWidths[$0]) }
        for id in columnWidths.keys { columnWidths[id] = columnWidth }
        if !bandHasRoom { for (id, share) in kept { columnWidths[id] = share } }
        if let focused { reveal(focused) }
    }

    /// The window's parent container, nil if the window is not here.
    public func container(of id: WindowID) -> Container? {
        root.path(of: id).map { root.container(at: Array($0.dropLast())) }
    }

    /// The axis of the window's parent container, `auto` resolved, nil if the window is not here.
    public func containerAxis(of id: WindowID) -> Orientation? {
        root.path(of: id).map { axisOfContainer(at: Array($0.dropLast())) }
    }

    /// The axis the container at `path` runs along now, `auto` resolved from the rectangle it is laid out in,
    /// so minimum sizes count as they do on screen.
    func axisOfContainer(at path: [Int]) -> Orientation {
        axisOfContainer(at: path, in: tiledLayout())
    }

    /// The axis of the container at `path` in `layout`, for callers asking about several containers at once.
    func axisOfContainer(at path: [Int], in layout: Layout) -> Orientation {
        root.container(at: path).axis(in: rect(at: path, in: layout))
    }

    /// The rectangle the container at `path` is laid out in, gaps and minimum sizes applied.
    func rect(at path: [Int], in layout: Layout) -> CGRect {
        layout.containerRects[path] ?? gaps.inset(bounds)
    }

    /// Set the layout mode of the focused window's parent container. Ratios are kept, so tiles come back as they were.
    public mutating func setMode(_ mode: LayoutMode) { setLayout(mode, nil) }

    /// Set the orientation of the focused window's parent container, and remember that it was chosen.
    public mutating func setOrientation(_ orientation: ContainerOrientation) { setLayout(nil, orientation) }

    /// Set the mode, the orientation or both of the focused window's parent container, then tidy the tree once,
    /// so the container is not merged into its parent halfway. With `autoOrientAccordions`, a container becoming
    /// an accordion turns `auto` unless a command chose its orientation.
    public mutating func setLayout(_ mode: LayoutMode?, _ orientation: ContainerOrientation?) {
        endFullscreen()
        // The strip itself stays a row of columns; a window alone in its column has no container to change.
        guard let focused, let path = root.path(of: focused), !(isScrolling && path.count == 1) else { return }
        root.modify(at: Array(path.dropLast())) { c in
            if let mode {
                if mode == .accordion, c.mode != .accordion, autoOrientAccordions, !c.orientationChosen { c.orientation = .auto }
                c.mode = mode
            }
            if let orientation {
                c.orientation = orientation
                c.orientationChosen = true
            }
        }
        normalize()
    }

    /// Toggle fullscreen for the focused window. Turning it off ends it for every window, so the tiles show again;
    /// a window waiting to go fullscreen counts as fullscreen. The tree is not changed.
    public mutating func toggleFullscreen() {
        guard let focused else { return }
        let on = fullscreenWindows.isEmpty && pendingFullscreen == nil
        endFullscreen()
        if on { fullscreenWindows = [focused] }
    }

    /// Whether turning fullscreen on would change nothing, now or later: the focused window is alone, no window is
    /// fullscreen or waiting to be, focusing another would end it anyway (`exit`; `follow` and `keep` hand it on to
    /// the next window), and its tile is already the frame fullscreen gives it, as a lone tile's or column's is.
    public var focusedFillsWorkspace: Bool {
        guard let focused, windows == [focused], fullscreenFocus == .exit,
              fullscreenWindows.isEmpty, pendingFullscreen == nil else { return false }
        var full = self
        full.fullscreenWindows = [focused]
        return layout().frames[focused] == full.layout().frames[focused]
    }

    /// Shows the window waiting to go fullscreen, if it is still `id` and focused. False when there is nothing to do:
    /// focus moved on, or fullscreen ended meanwhile.
    public mutating func promotePendingFullscreen(_ id: WindowID) -> Bool {
        guard pendingFullscreen == id, focused == id else { return false }
        pendingFullscreen = nil
        fullscreenWindows = [id]
        return true
    }

    /// No window fullscreen, nor waiting to be.
    mutating func endFullscreen() {
        fullscreenWindows = []
        pendingFullscreen = nil
    }

    /// The tree as it shows with `id` fullscreen, `on`, or not, whatever it says itself: for a window something else is
    /// still taking there or back, so the others are laid out around where it shows. In front when fullscreen.
    public func showing(_ id: WindowID, fullscreen on: Bool) -> Workspace {
        var copy = self
        copy.fullscreenWindows.removeAll { $0 == id }
        if on { copy.fullscreenWindows.insert(id, at: 0) }
        return copy
    }

    /// Frames and stacking for every window. Fullscreen windows cover the bounds minus outer gaps and come first,
    /// the focused one in front; in a strip that pushes, they fill their widened columns instead, see
    /// `stripLayout(pushed:)`. Scrolled-out windows are parked where macOS lets them be, see `parked(_:)`.
    public func layout() -> Layout {
        var result = pushesFullscreen ? stripLayout(pushed: pushedColumns) : tiledLayout()
        if isScrolling { result.frames = parked(result.frames) }
        let shown = fullscreenWindows.filter { result.frames[$0] != nil }
        // A pinned window fullscreen covers the strip whether it pushes or not: it has no column in the band to widen.
        // Across a seam, the display it is on.
        for id in shown where !pushesFullscreen || pinSide(of: id) != nil {
            result.frames[id] = spansDisplays ? displayInset(at: result.frames[id]!.midX) : gaps.inset(bounds)
        }
        result.order = shown + result.order.filter { !shown.contains($0) }
        if isScrolling {
            result.screen = bounds
            for (id, frame) in result.frames where frame.minX < bounds.minX {
                let width = shownWidth(of: id, frame)
                if width < frame.width { result.narrower[id] = CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height) }
            }
        }
        return result
    }

    /// The layout ignoring fullscreen, used for geometry questions.
    func tiledLayout() -> Layout {
        if isScrolling { return stripLayout() }
        var result = Layout()
        root.layout(in: gaps.inset(bounds), gaps: gaps, padding: accordionPadding, minimums: minimumSizes, into: &result)
        return result
    }

    /// Tidy the tree after an edit, and unwrap a root whose only child is a container. A tree still in its fixed
    /// template is left as it is: tidying would drop its reserved empty cells and unwrap its one-cell columns, so an
    /// edit that keeps the shape, such as reorienting an overflow accordion or a `layout` that changes nothing,
    /// would lose the template.
    mutating func normalize() {
        if case .fixed = algorithm, isFixedTree { return }
        root.normalize()
        settlePins()
        // The strip stays the root even with one column left.
        if !isScrolling, root.children.count == 1, case .container(let only) = root.children[0] { root = only }
    }
}
