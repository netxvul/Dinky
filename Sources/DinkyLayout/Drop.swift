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

extension DropHit {
    /// Whether this hit, in the tree as it is, asks for its own drop although the pointer is over the dragged window's
    /// place in a drop shown beside a tile (`shown` split left or right, `shows` the hit in the tree as that drop leaves
    /// it, `.own`). Making room for that drop slides a strip column aimed at out from under the pointer, or shrinks a
    /// tile to half of itself, so the pointer goes on over the preview where the tile showed: its top or bottom band
    /// there, the stacking zone of a tile as the tree is, asks to stack onto it. Anywhere else over the preview the drop
    /// shown stays, as it does for every other drop shown, so windows making room cannot send it back and forth.
    public func stacks(overBeside shown: DropZone, shows: DropHit) -> Bool {
        guard shows == .own, case .split(let side) = shown, side.orientation == .horizontal,
              case .tile(_, .split(let way)) = self else { return false }
        return way.orientation == .vertical
    }
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
    /// Over a tile, the frontmost where tiles overlap, it is over the zone of it there; over its own place, that, but
    /// where a pin is in front of it hanging under.
    public func dropHit(at point: CGPoint, in layout: Layout, excluding id: WindowID) -> DropHit {
        let area = gaps.inset(bounds)
        guard area.width > 1, area.height > 1 else { return .none }
        let p = CGPoint(x: min(max(point.x, area.minX), area.maxX - 1), y: min(max(point.y, area.minY), area.maxY - 1))
        // Over its own place, that, unless another column's pin is in front of it there, as one is of a band window
        // hanging under it: only a pin, which is in front whatever the tree's focus says yet, not an accordion's window,
        // say, in front of one grabbed from behind before its app is active, nor one of its own pinned stack.
        let front = layout.order.first { layout.frames[$0]!.contains(p) }
        if layout.frames[id]?.contains(p) == true,
           front.map({ $0 == id || pinSide(of: $0) == nil || pinSide(of: $0) == pinSide(of: id) }) ?? true { return .own }
        if let edge = edgeDrop(at: p, in: layout, excluding: id) { return .tile(edge.target, edge.zone) }
        if let target = front {
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
    /// right make `id` a column of its own beside `target`'s, at the width it had; up and down stack it in `target`'s
    /// column with its share of it, 1/n of n, the others keeping their proportions (`shareStack`), and where it is
    /// already, just there, nothing changes. Ends fullscreen, as any layout change does, and focuses `id`.
    @discardableResult
    public mutating func drop(_ id: WindowID, onto target: WindowID, _ zone: DropZone) -> Bool {
        guard id != target, contains(id), contains(target) else { return false }
        endFullscreen()
        guard case .split(let side) = zone, splitsOnDrop else {
            if isScrolling, hasPins { return swapBesidePins(id, target) }
            let shares = columnShares(id, target)
            guard swap(id, target) else { return false }
            if let shares { keepColumnShares(shares) }
            focus(id)
            return true
        }
        if isScrolling, side.orientation == .horizontal {
            dropColumn(id, beside: target, forward: side.isForward)
            normalize()
        } else {
            // Already just there in the same stack: nothing to move, nor any height to share out again.
            if isScrolling, stackedAlready(id, side, of: target) {
                focus(id)
                return true
            }
            var stacked = self
            let share = isScrolling ? root.path(of: target).map { width(ofColumn: $0[0]) } : nil
            stacked.splitTile(of: target, with: id, side)
            stacked.normalize()
            if isScrolling { stacked.shareStack(with: id, besides: target) }
            if let share, let column = stacked.root.path(of: id)?.first { stacked.setWidth(ofColumn: column, share) }
            // Into a pin, not where the pin then leaves the band too little room.
            if isScrolling, stacked.pinSide(of: id) != nil, lacksRoom(after: stacked) { return false }
            self = stacked
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
            // Each takes the minimum it had with it, which the room each tree keeps depends on.
            here.minimumSizes[id] = source.minimumSizes[id]
            there.minimumSizes[target] = minimumSizes[target]
            // Not where it changes a pin's holder and so leaves the band short of room.
            if isScrolling, pinSide(of: target) != nil, lacksRoom(after: here) { return false }
            if source.isScrolling, source.pinSide(of: id) != nil, source.lacksRoom(after: there) { return false }
            self = here
            source = there
            return true
        }
        let share = source.columnShare(of: id)
        // Worked out on copies: a drop refused, as one into a pin left short of room, changes neither tree.
        var here = self, there = source
        // Its minimum comes with it, before the source forgets it, so the room this tree keeps is judged with it.
        let minimum = there.minimumSizes[id]
        there.remove(id)
        here.minimumSizes[id] = minimum
        if let target {
            if isScrolling {
                // In at the band's end, out of the way and not scrolled to, so only the drop scrolls.
                here.root.insert(.window(id), at: here.bandRange.upperBound)
                here.columnWidths[id] = share ?? columnWidth
            } else {
                here.insert(id)
            }
            guard here.drop(id, onto: target, zone) else { return false }
        } else {
            here.insert(id)
            if let share, isScrolling, let column = here.root.path(of: id)?.first { here.setWidth(ofColumn: column, share) }
        }
        self = here
        source = there
        return true
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

    /// Whether `id` already sits right beside `target` on `side`, up or down, in the same stacked container.
    private func stackedAlready(_ id: WindowID, _ side: Direction, of target: WindowID) -> Bool {
        guard side.orientation == .vertical, let a = root.path(of: id), let b = root.path(of: target), a.count > 1,
              Array(a.dropLast()) == Array(b.dropLast()) else { return false }
        let parent = root.container(at: Array(a.dropLast()))
        guard parent.orientation == .vertical, parent.mode == .tiles else { return false }
        return a.last! == b.last! + (side.isForward ? 1 : -1)
    }

    /// In a strip, `id` just stacked beside `target` in a column, the two sharing what `target` had: `id` takes its
    /// share of the column instead, 1/n of n, and the others keep theirs among themselves, scaled to the rest, so a
    /// column of thirds stays thirds, and dropping a window back where it already is changes nothing. Only where the two
    /// sit one over the other in the same container.
    private mutating func shareStack(with id: WindowID, besides target: WindowID) {
        guard let path = root.path(of: id), let other = root.path(of: target), path.count > 1,
              Array(path.dropLast()) == Array(other.dropLast()) else { return }
        let parent = Array(path.dropLast())
        root.modify(at: parent) { column in
            guard column.orientation == .vertical, column.children.count > 2 else { return }
            let n = Double(column.children.count), mine = path.last!, theirs = other.last!
            var ratios = column.ratios
            ratios[theirs] += ratios[mine]
            ratios[mine] = 0
            ratios = ratios.map { $0 * (n - 1) / n }
            ratios[mine] = 1 / n
            column.setRatios(ratios)
        }
    }

    /// In a strip, the shares of the columns of `a` and `b` where a swap of the two would leave a column with windows of
    /// two widths: one of them holds more than one window. Nil anywhere else.
    func columnShares(_ a: WindowID, _ b: WindowID) -> [(column: Int, share: Double)]? {
        guard isScrolling, let x = root.path(of: a)?.first, let y = root.path(of: b)?.first, x != y,
              root.children[x].windows.count > 1 || root.children[y].windows.count > 1 else { return nil }
        return [(x, width(ofColumn: x)), (y, width(ofColumn: y))]
    }

    /// Gives each column back its share, every window of it the same width, after a swap that moved windows between
    /// them, as `columnShares` read them.
    mutating func keepColumnShares(_ shares: [(column: Int, share: Double)]) {
        for (column, share) in shares { setWidth(ofColumn: column, share) }
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
