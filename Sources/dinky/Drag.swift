import AppKit
import DinkyLayout

// Dragging a tiled window with the mouse. On release, a drag that moved one edge of the window on an axis is a
// resize: the tree takes the new size and the other tiles make room. Any other drag is a move, dropped by the zone
// of the tile under the pointer: in the middle of it the two swap, nearer an edge the tile splits and the window
// takes the half on that side; anywhere else the window goes back. While a move is under way, placeholders outline
// the window's tile and the tile under the pointer, and fill the part of it the window will take. Only frames that
// change while the mouse button is down count as a drag, which keeps dinky's own frame writes and apps moving
// themselves out of it. With `[drag] mouse-modifier` set, only a window grabbed with it held drops onto other tiles
// and shows placeholders: a window moved by its title bar alone goes back, while an edge dragged still resizes. A
// grabbed window is moved by dinky (ModifierDrag.swift), so it starts and ends its drag itself; it only moves, so it
// always drops by the tile under the pointer.
extension Coordinator {
    func noteFrameChange(of id: WindowID) {
        if dragging == id { return showPlaceholders() }
        // Only tiled windows have a Space.
        guard dragging == nil, placements[id]?.space != nil, !isAnimating(id), mouseButtonDown else { return }
        dragging = id
        dragDrops = config.drag.mouseModifier.isEmpty
        showPlaceholders()
        watchDragEnd()
    }

    private func watchDragEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let id = self.dragging else { return }
            if self.mouseButtonDown {
                self.showPlaceholders()
                self.watchDragEnd()
            } else {
                self.finishDrag(id, dropping: self.dragDrops)
            }
        }
    }

    /// Drags a tiled window grabbed with `[drag] mouse-modifier` at `frame` by `pointer`, until `endHeldDrag`.
    func startHeldDrag(of id: WindowID, at frame: CGRect, pointer: CGPoint) {
        dragging = id
        dragDrops = true
        held = (frame, pointer)
        showPlaceholders()
    }

    /// The pointer dragged a window grabbed with `[drag] mouse-modifier` to `pointer`, and it was sent to `frame`. The
    /// feedback follows the drag from here, not the window's frame changes, which come later from the app, if at all.
    func heldDragMoved(_ id: WindowID, to frame: CGRect, pointer: CGPoint) {
        guard dragging == id else { return }
        held = (frame, pointer)
        showPlaceholders()
    }

    /// The button let go of a window grabbed with `[drag] mouse-modifier`: it drops by where it was last sent.
    func endHeldDrag(of id: WindowID) {
        guard dragging == id else { return }
        finishDrag(id, dropping: true)
    }

    private func finishDrag(_ id: WindowID, dropping: Bool) {
        let point = held?.pointer ?? CGEvent(source: nil)?.location
        let frame = held?.frame
        dragging = nil
        held = nil
        shownDrop = nil
        placeholders.hide()
        dropped(id, dropping: dropping, at: point, held: frame)
    }

    private func dropped(_ id: WindowID, dropping: Bool, at point: CGPoint?, held: CGRect?) {
        guard let key = placements[id]?.space, let layout = workspaces[key]?.layout(), let window = model.windows[id],
              let expected = layout.frames[id] else { return }
        let frame = held ?? window.frame
        if frame.isClose(to: expected, within: 2) { return }
        // A held window keeps its size, even one bigger than its tile: it only moved.
        if held == nil, let edges = movedEdges(from: expected, to: frame) {
            let resized = edit(key) { $0.resize(id, to: frame.size, moving: edges) } ?? false
            print("\(stamp()) drag: resized \(id) from \(expected.size) to \(frame.size), edges \(edges.map { "\($0)" }.sorted()), "
                  + (resized ? "taken" : "not taken\(workspaces[key]?.fullscreenWindows.isEmpty == false ? " (fullscreen)" : "")"))
        } else if !dropping {
            print("\(stamp()) drag: \(id) moved without \(config.drag.mouseModifier.name) held, back to its tile")
        } else if let point, let drop = dropTarget(of: id, at: point, in: key, layout: layout) {
            print("\(stamp()) drag: dropped \(id) onto \(drop.target), \(drop.zone)")
            edit(key) { $0.drop(id, onto: drop.target, drop.zone) }
        }
        // Back to its tile, wherever that is now.
        dirty.insert(key)
        flush()
    }

    /// Outline the dragged window's tile and the tile under the pointer, and fill the part of it the window would
    /// take, while the drag is a move that drops.
    func showPlaceholders() {
        guard config.drag.placeholders, dragDrops, let id = dragging, let key = placements[id]?.space, let workspace = workspaces[key],
              let window = model.windows[id] else { return placeholders.hide() }
        let layout = workspace.layout()
        guard let home = layout.frames[id] else { return placeholders.hide() }
        // A held window only moves, even one bigger than its tile.
        let frame = held?.frame ?? window.frame
        if frame.isClose(to: home, within: 2) || (held == nil && movedEdges(from: home, to: frame) != nil) {
            return placeholders.hide()
        }
        let drop = (held?.pointer ?? CGEvent(source: nil)?.location).flatMap { dropTarget(of: id, at: $0, in: key, layout: layout) }
        // One line each time what the drop would do changes, so a bug report shows what the feedback was.
        let described = drop.map { "over \($0.target), \($0.zone)" } ?? "over no tile"
        if described != shownDrop {
            shownDrop = described
            print("\(stamp()) drag: \(id) \(described)")
        }
        placeholders.update(style: config.drag)
        placeholders.show(dragged: id, home: home, outlinesHome: config.drag.homeOutline, target: drop.flatMap { layout.frames[$0.target] },
                          preview: drop.flatMap { workspace.dropPreview(onto: $0.target, $0.zone, in: layout) },
                          swap: drop?.zone == .swap,
                          squareEdge: drop.flatMap { if case .split(let side) = $0.zone { side.opposite } else { nil } },
                          cornerRadius: CGFloat(window.cornerRadius), animated: animates)
    }

    /// The tile at `point`, the pointer, that a dragged window drops onto, the frontmost where tiles overlap, and the
    /// zone of it `point` is in. The placeholders and the drop both ask this, so what is outlined is what happens.
    private func dropTarget(of id: WindowID, at point: CGPoint, in key: UInt64, layout: Layout) -> (target: WindowID, zone: DropZone)? {
        guard let target = layout.order.first(where: { $0 != id && layout.frames[$0]!.contains(point) }) else { return nil }
        return (target, workspaces[key]?.dropZone(at: point, onto: target, in: layout) ?? .swap)
    }

    /// The edges a resize moved, going from the tile to the dropped frame: on each axis, one edge moved more than
    /// 2 pt and the other stayed. Nil for a move, where some axis had both edges move, or nothing did.
    private func movedEdges(from tile: CGRect, to frame: CGRect) -> Set<Direction>? {
        let axes = [((Direction.left, tile.minX, frame.minX), (Direction.right, tile.maxX, frame.maxX)),
                    ((Direction.up, tile.minY, frame.minY), (Direction.down, tile.maxY, frame.maxY))]
        var edges: Set<Direction> = []
        for (lead, trail) in axes {
            let moved = [lead, trail].filter { abs($0.2 - $0.1) > 2 }.map(\.0)
            if moved.count == 2 { return nil }
            edges.formUnion(moved)
        }
        return edges.isEmpty ? nil : edges
    }

    private var mouseButtonDown: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }
}
