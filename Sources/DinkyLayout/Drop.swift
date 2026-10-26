import CoreGraphics

/// Where a window dragged onto a tile lands: in the tile's place, the two swapping, or beside it, the tile split in two.
public enum DropZone: Equatable, Sendable {
    case swap
    /// Beside the target on this side, the target's tile split in two along the direction's axis.
    case split(Direction)

    /// The zone `point` is in over the tile `rect`. The middle `center` share of the tile on both axes swaps;
    /// around it, the diagonals divide the tile into a triangle per side. Measured in shares of the tile, so a
    /// long thin tile divides along its own diagonals too.
    public init(at point: CGPoint, in rect: CGRect, center: CGFloat = 0.5) {
        let x = rect.width > 0 ? (point.x - rect.midX) / (rect.width / 2) : 0
        let y = rect.height > 0 ? (point.y - rect.midY) / (rect.height / 2) : 0
        if abs(x) < center && abs(y) < center {
            self = .swap
        } else if abs(x) >= abs(y) {
            self = .split(x < 0 ? .left : .right)
        } else {
            self = .split(y < 0 ? .up : .down)
        }
    }

    /// The zone `point` is in over a column's tile `rect` in a scrolling strip, where a window mostly goes between
    /// columns: the top and bottom `band` share of the tile stacks it into the column, above or below; across the rest,
    /// the middle `swap` share swaps the two, and either side of it puts the window in a column of its own before or after.
    public init(scrollingAt point: CGPoint, in rect: CGRect, band: CGFloat = 0.2, swap: CGFloat = 0.2) {
        let x = rect.width > 0 ? (point.x - rect.minX) / rect.width : 0.5
        let y = rect.height > 0 ? (point.y - rect.minY) / rect.height : 0.5
        if y < band {
            self = .split(.up)
        } else if y > 1 - band {
            self = .split(.down)
        } else if abs(x - 0.5) < swap / 2 {
            self = .swap
        } else {
            self = .split(x < 0.5 ? .left : .right)
        }
    }
}

/// What a dragged window is over in a tree as it shows: its own place, a tile and the zone of it, or nothing to
/// drop onto.
public enum DropHit: Equatable, Sendable {
    /// The dragged window's own place in the layout: where it came from, or where a drop shown puts it.
    case own
    case tile(WindowID, DropZone)
    /// No window but the dragged one, if that.
    case none
}

/// Dropping a dragged window onto another tile.
extension Workspace {
    /// Whether a drop beside a tile splits it. A fixed layout's template only swaps.
    var splitsOnDrop: Bool {
        if case .fixed = algorithm, isFixedTree { return false }
        return true
    }

    /// The zone of `target`'s tile in `layout` that `point` is in, nil if `target` has no tile there. A strip's column
    /// is measured on the part of it that shows.
    public func dropZone(at point: CGPoint, onto target: WindowID, in layout: Layout) -> DropZone? {
        guard let rect = layout.frames[target] else { return nil }
        if isScrolling { return DropZone(scrollingAt: point, in: rect.intersection(bounds)) }
        return splitsOnDrop ? DropZone(at: point, in: rect) : .swap
    }

    /// What window `id`, dragged with the pointer at `point`, is over in `layout`, this tree's as it shows. The point
    /// counts where it is inside the outer gaps, so over the menu bar, the Dock or an outer gap it is over the tile along
    /// that edge. In a strip, past the columns in view, over a parked sliver or the gutter, it goes beside the nearest
    /// one in view. Over an inner gap it is over the nearest tile, or the window's own place when that is nearest.
    /// Over a tile, the frontmost where tiles overlap, it is over the zone of it there.
    public func dropHit(at point: CGPoint, in layout: Layout, excluding id: WindowID) -> DropHit {
        let area = gaps.inset(bounds)
        guard area.width > 1, area.height > 1 else { return .none }
        let p = CGPoint(x: min(max(point.x, area.minX), area.maxX - 1), y: min(max(point.y, area.minY), area.maxY - 1))
        if layout.frames[id]?.contains(p) == true { return .own }
        if let edge = edgeDrop(at: p, in: layout, excluding: id) { return .tile(edge.target, edge.zone) }
        if let target = layout.order.first(where: { $0 != id && layout.frames[$0]!.contains(p) }) {
            return .tile(target, dropZone(at: p, onto: target, in: layout) ?? .swap)
        }
        // In a gap: the nearest of what shows, the window's own place included.
        let shown = { (id: WindowID) -> CGRect? in
            guard let frame = layout.frames[id] else { return nil }
            let visible = frame.intersection(area)
            return visible.isNull || visible.isEmpty ? nil : visible
        }
        let nearest = layout.order.compactMap { id in shown(id).map { (id, $0) } }
            .min { $0.1.distance(to: p) < $1.1.distance(to: p) }
        guard let (target, rect) = nearest else { return .none }
        if target == id { return .own }
        let inside = CGPoint(x: min(max(p.x, rect.minX), rect.maxX - 1), y: min(max(p.y, rect.minY), rect.maxY - 1))
        return .tile(target, dropZone(at: inside, onto: target, in: layout) ?? .swap)
    }

    /// In a strip, where a window other than `id` dropped at `point` goes when that is past the columns that show, over
    /// the sliver of a parked one or the gutter at a screen edge: beside the nearest column that shows, after the last
    /// on the right, before the first on the left. Nil anywhere else, and for a workspace that is no strip.
    public func edgeDrop(at point: CGPoint, in layout: Layout, excluding id: WindowID) -> (target: WindowID, zone: DropZone)? {
        guard isScrolling, bounds.contains(point) else { return nil }
        // Windows of the columns showing more than the slivers parked ones do.
        let shown = layout.order.filter { $0 != id && layout.frames[$0]!.intersection(bounds).width > 2 * Self.peek }
        guard let first = shown.min(by: { layout.frames[$0]!.minX < layout.frames[$1]!.minX }),
              let last = shown.max(by: { layout.frames[$0]!.maxX < layout.frames[$1]!.maxX }) else { return nil }
        if point.x >= layout.frames[last]!.maxX { return (last, .split(.right)) }
        if point.x < layout.frames[first]!.minX { return (first, .split(.left)) }
        return nil
    }

    /// In a strip, the width of `id`'s column, as a share; nil anywhere else.
    public func columnShare(of id: WindowID) -> Double? {
        guard isScrolling, let path = root.path(of: id) else { return nil }
        return width(ofColumn: path[0])
    }

    /// In a strip, where `id`'s column starts on screen as the strip lays it out, before parking; nil anywhere else.
    public func columnStart(of id: WindowID) -> CGFloat? {
        guard isScrolling, let index = root.path(of: id)?.first else { return nil }
        if pinSide(ofColumn: index) != nil { return pinRect(index).minX }
        let area = stripArea, spans = columnSpans(in: area)
        return area.minX + spans[index].start - offset(for: spans, in: area)
    }

    /// In a strip, scroll so `id`'s column starts at `x` on screen, as near as the strip lets it with the focused
    /// column showing whole: where it showed before a drop moved it along the strip, as taking a column out left of it
    /// does, so it stays under the pointer. With `pastEnds`, the strip can go past its ends for it, as a drop shown
    /// does, till `keepsScroll` is cleared: taking out the first column, the one beside it would otherwise go to the
    /// start and the next come in under the pointer. Not for no more than an end column reaching into its gutter, as it
    /// does within the ends: the drop would land that far from where it showed. Nothing anywhere else.
    public mutating func scroll(columnOf id: WindowID, to x: CGFloat, pastEnds: Bool = false) {
        guard isScrolling, let index = bandIndex(of: id) else { return }
        let area = stripArea, spans = columnSpans(in: area), inset = stripInset
        scrollOffset = area.minX + spans[index].start - x
        keepsScroll = false
        let within = offset(for: spans, in: area)
        keepsScroll = pastEnds
        let past = offset(for: spans, in: area)
        if abs(past - within) <= max(area.minX - inset.minX, inset.maxX - area.maxX) + 0.5 { keepsScroll = false }
        scrollOffset = keepsScroll ? past : within
    }

    /// Drop `id` onto `target`: swap the two, or split `target`'s tile and put `id` in the half on the zone's side,
    /// which takes half of what the tile is once `id` has left its own place. In the scrolling layout, left and
    /// right make `id` a column of its own beside `target`'s, at the width it had. Ends fullscreen, as any layout
    /// change does, and focuses `id`.
    @discardableResult
    public mutating func drop(_ id: WindowID, onto target: WindowID, _ zone: DropZone) -> Bool {
        guard id != target, contains(id), contains(target) else { return false }
        endFullscreen()
        guard case .split(let side) = zone, splitsOnDrop else {
            if isScrolling, hasPins { return swapBesidePins(id, target) }
            guard swap(id, target) else { return false }
            focus(id)
            return true
        }
        if isScrolling, side.orientation == .horizontal {
            dropColumn(id, beside: target, forward: side.isForward)
            normalize()
        } else {
            let share = isScrolling ? root.path(of: target).map { width(ofColumn: $0[0]) } : nil
            splitTile(of: target, with: id, side)
            normalize()
            if let share, let column = root.path(of: id)?.first { setWidth(ofColumn: column, share) }
        }
        focus(id)
        return true
    }

    /// Take `id` from the tree `source`, another Space's, as dropped onto `target` here in `zone`, or, without a
    /// target, as a new window comes in. Swapped, the two trade places, each taking the other's size, and neither tree
    /// keeps a window fullscreen; refused where a pin's holder changing leaves its band short of room. Otherwise `id` goes straight to its place, focused: in a strip a column of its own
    /// keeps the width its column had in a strip it came from, and the strip scrolls once, from where it is, as little
    /// as shows it. False, and nothing changes, when `id` is not in `source`, already here, or `target` is not here.
    @discardableResult
    public mutating func receive(_ id: WindowID, from source: inout Workspace, onto target: WindowID?, _ zone: DropZone) -> Bool {
        guard source.contains(id), !contains(id), target.map({ contains($0) }) ?? true else { return false }
        if let target, zone == .swap {
            var here = self, there = source
            here.endFullscreen()
            there.endFullscreen()
            here.replace(target, with: id)
            here.focus(id)
            there.replace(id, with: target)
            // Not where it changes a pin's holder and so leaves the band short of room.
            if isScrolling, pinSide(of: target) != nil, lacksRoom(after: here) { return false }
            if source.isScrolling, source.pinSide(of: id) != nil, source.lacksRoom(after: there) { return false }
            self = here
            source = there
            return true
        }
        let share = source.columnShare(of: id)
        source.remove(id)
        guard let target else {
            insert(id)
            if let share, isScrolling, let column = root.path(of: id)?.first { setWidth(ofColumn: column, share) }
            return true
        }
        if isScrolling {
            // In at the band's end, out of the way and not scrolled to, so only the drop scrolls.
            root.insert(.window(id), at: bandRange.upperBound)
            columnWidths[id] = share ?? columnWidth
        } else {
            insert(id)
        }
        return drop(id, onto: target, zone)
    }

    /// Take `id` out of its place and split `target`'s tile with it. The new container runs along the side's axis;
    /// normalizing splices it into a parent running the same way, the two keeping the tile's share between them.
    private mutating func splitTile(of target: WindowID, with id: WindowID, _ side: Direction) {
        guard let from = root.path(of: id), var at = root.path(of: target) else { return }
        rekeyPins(leaving: id)
        detach(from, adjusting: &at)
        let pair: [Node] = side.isForward ? [.window(target), .window(id)] : [.window(id), .window(target)]
        root.modify(at: Array(at.dropLast())) {
            $0.replace(at: at.last!, with: .container(Container(ContainerOrientation(side.orientation), .tiles, pair)))
        }
    }

    /// Take `id` out of its column into a new one beside `target`'s, keeping its width.
    private mutating func dropColumn(_ id: WindowID, beside target: WindowID, forward: Bool) {
        guard let from = root.path(of: id), var at = root.path(of: target) else { return }
        let share = width(ofColumn: from[0])
        // Out of a pin, it is a band column now; beside a pin, it goes in the band next to it.
        rekeyPins(leaving: id)
        detach(from, adjusting: &at)
        let band = bandRange
        root.insert(.window(id), at: min(max(at[0] + (forward ? 1 : 0), band.lowerBound), band.upperBound))
        columnWidths[id] = share
    }
}

private extension CGRect {
    /// How far `point` is from the rect: zero inside it.
    func distance(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX), dy = max(minY - point.y, 0, point.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
