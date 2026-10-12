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

    /// The part of the tile `rect` a drop here shows as taken: all of it for a swap, the half on that side for a
    /// split, `gap` apart from the other half.
    public func preview(of rect: CGRect, gap: CGFloat) -> CGRect {
        guard case .split(let side) = self else { return rect }
        let half = ((side.orientation == .horizontal ? rect.width : rect.height) - gap) / 2
        return switch side {
        case .left: CGRect(x: rect.minX, y: rect.minY, width: half, height: rect.height)
        case .right: CGRect(x: rect.maxX - half, y: rect.minY, width: half, height: rect.height)
        case .up: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: half)
        case .down: CGRect(x: rect.minX, y: rect.maxY - half, width: rect.width, height: half)
        }
    }
}

/// Dropping a dragged window onto another tile.
extension Workspace {
    /// Whether a drop beside a tile splits it. A fixed layout's template only swaps.
    var splitsOnDrop: Bool {
        if case .fixed = algorithm, isFixedTree { return false }
        return true
    }

    /// The zone of `target`'s tile in `layout` that `point` is in, nil if `target` has no tile there.
    public func dropZone(at point: CGPoint, onto target: WindowID, in layout: Layout) -> DropZone? {
        guard let rect = layout.frames[target] else { return nil }
        return splitsOnDrop ? DropZone(at: point, in: rect) : .swap
    }

    /// What a drop in `zone` of `target`'s tile in `layout` outlines: the tile, or the half of it the dropped
    /// window takes.
    public func dropPreview(onto target: WindowID, _ zone: DropZone, in layout: Layout) -> CGRect? {
        guard let rect = layout.frames[target] else { return nil }
        guard case .split(let side) = zone else { return rect }
        return zone.preview(of: rect, gap: gaps.inner(side.orientation))
    }

    /// Drop `id` onto `target`: swap the two, or split `target`'s tile and put `id` in the half on the zone's side,
    /// which takes half of what the tile is once `id` has left its own place. In the scrolling layout, left and
    /// right make `id` a column of its own beside `target`'s, at the width it had. Focuses `id` after a split.
    @discardableResult
    public mutating func drop(_ id: WindowID, onto target: WindowID, _ zone: DropZone) -> Bool {
        guard id != target, contains(id), contains(target) else { return false }
        guard case .split(let side) = zone, splitsOnDrop else { return swap(id, target) }
        endFullscreen()
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

    /// Take `id` out of its place and split `target`'s tile with it. The new container runs along the side's axis;
    /// normalizing splices it into a parent running the same way, the two keeping the tile's share between them.
    private mutating func splitTile(of target: WindowID, with id: WindowID, _ side: Direction) {
        guard let from = root.path(of: id), var at = root.path(of: target) else { return }
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
        detach(from, adjusting: &at)
        root.insert(.window(id), at: at[0] + (forward ? 1 : 0))
        columnWidths[id] = share
    }
}
