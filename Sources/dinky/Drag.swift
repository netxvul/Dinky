import AppKit
import DinkyLayout

// Dragging a tiled window with the mouse. On release, a drag that moved one edge of the window on an axis is a
// resize: the tree takes the new size and the other tiles make room. Any other drag is a move, dropped by the zone
// of the tile under the pointer: in the middle of it the two swap, nearer an edge the tile splits and the window
// takes the half on that side; anywhere else the window goes back. While a move is under way, placeholders outline
// the window's tile and the tile under the pointer, and fill the part of it the window will take. Only frames that
// change while the mouse button is down count as a drag, which keeps dinky's own frame writes and apps moving
// themselves out of it.
extension Coordinator {
    func noteFrameChange(of id: WindowID) {
        if dragging == id { return showPlaceholders() }
        // Only tiled windows have a Space.
        guard dragging == nil, placements[id]?.space != nil, !isAnimating(id), mouseButtonDown else { return }
        dragging = id
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
                self.finishDrag(id, dropping: true)
            }
        }
    }

    private func finishDrag(_ id: WindowID, dropping: Bool) {
        let point = CGEvent(source: nil)?.location
        dragging = nil
        shownDrop = nil
        placeholders.hide()
        dropped(id, dropping: dropping, at: point)
    }

    private func dropped(_ id: WindowID, dropping: Bool, at point: CGPoint?) {
        guard let key = placements[id]?.space, let layout = workspaces[key]?.layout(), let window = model.windows[id],
              let expected = layout.frames[id] else { return }
        if window.frame.isClose(to: expected, within: 2) { return }
        if let edges = movedEdges(from: expected, to: window.frame) {
            let resized = edit(key) { $0.resize(id, to: window.frame.size, moving: edges) } ?? false
            print("\(stamp()) drag: resized \(id) from \(expected.size) to \(window.frame.size), edges \(edges.map { "\($0)" }.sorted()), "
                  + (resized ? "taken" : "not taken\(workspaces[key]?.fullscreenWindows.isEmpty == false ? " (fullscreen)" : "")"))
        } else if dropping, let point, let drop = dropTarget(of: id, at: point, in: key, layout: layout) {
            print("\(stamp()) drag: dropped \(id) onto \(drop.target), \(drop.zone)")
            edit(key) { $0.drop(id, onto: drop.target, drop.zone) }
        }
        // Back to its tile, wherever that is now.
        dirty.insert(key)
        flush()
    }

    /// Outline the dragged window's tile and the tile under the pointer, and fill the part of it the window would
    /// take, while the drag is a move.
    func showPlaceholders() {
        guard config.drag.placeholders, let id = dragging, let key = placements[id]?.space, let workspace = workspaces[key],
              let window = model.windows[id] else { return placeholders.hide() }
        let layout = workspace.layout()
        guard let home = layout.frames[id] else { return placeholders.hide() }
        if window.frame.isClose(to: home, within: 2) || movedEdges(from: home, to: window.frame) != nil {
            return placeholders.hide()
        }
        let drop = CGEvent(source: nil).flatMap { dropTarget(of: id, at: $0.location, in: key, layout: layout) }
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
