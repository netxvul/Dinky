import CoreGraphics
import DinkyLayout

// What commands ask of the coordinator: tree commands on the focused window's Space, floating, and
// taking in a window dinky moved to another Space.
extension Coordinator {
    /// Whether dinky floats the window; nil for a window it has not classified.
    func isFloating(_ id: WindowID) -> Bool? { placements[id]?.floating }

    /// The tree of the display's current Space, if dinky has one.
    func workspace(on display: Display) -> Workspace? {
        workspaces[display.currentSpaceID]
    }

    /// The container holding a tiled window.
    func container(of id: WindowID) -> Container? {
        placements[id]?.space.flatMap { workspaces[$0]?.container(of: id) }
    }

    /// Whether a tiled window's workspace is laid out as a scrolling strip.
    func isScrolling(_ id: WindowID) -> Bool {
        placements[id]?.space.flatMap { workspaces[$0]?.isScrolling } ?? false
    }

    /// Whether the window shows whole: false only for a column scrolled partly or wholly out of view.
    func isInView(_ id: WindowID) -> Bool {
        placements[id]?.space.flatMap { workspaces[$0]?.isInView(id) } ?? true
    }

    /// Switches a tiled window's workspace to the scrolling strip, or back to the tree its config gives it
    /// (tiles when that is scrolling too). The choice holds until switched again.
    func setScrolling(_ on: Bool, for id: WindowID) {
        guard let key = placements[id]?.space else { return }
        let configured = algorithm(settings(for: key))
        let new: TilingAlgorithm = on ? .scrolling : configured == .scrolling ? .dwindle(.tiles) : configured
        edit(key) {
            $0.chosenAlgorithm = new == configured ? nil : new
            $0.setAlgorithm(new)
            $0.focus(id)
        }
        flush()
    }

    /// The axis the container holding a tiled window runs along now, `auto` resolved.
    func containerAxis(of id: WindowID) -> Orientation? {
        placements[id]?.space.flatMap { workspaces[$0]?.containerAxis(of: id) }
    }

    /// AeroSpace's name for how a window is laid out: `h_tiles`, `v_tiles`, `h_accordion` or `v_accordion`
    /// from its container (an `auto` one by the axis it follows now), `fullscreen` for dinky's fullscreen,
    /// `floating` for any window that is not tiled.
    func layoutName(of id: WindowID) -> String {
        guard let key = placements[id]?.space, let workspace = workspaces[key],
              let container = workspace.container(of: id), let axis = workspace.containerAxis(of: id) else { return "floating" }
        if workspace.fullscreen == id { return "fullscreen" }
        return (axis == .horizontal ? "h_" : "v_") + (container.mode == .accordion ? "accordion" : "tiles")
    }

    /// Runs a command on the tree of a window (the focused one by default), focused in that tree, and applies
    /// what changed. Nil if the window is not tiled.
    func command<T>(on id: WindowID? = nil, _ change: (inout Workspace) -> T) -> T? {
        let id = id ?? focusedWindow
        guard let key = placements[id]?.space else { return nil }
        edit(key) { $0.focus(id) }
        let result = edit(key, change)
        flush()
        return result
    }

    /// Floats a tiled window where it stands, or tiles a floating one beside the focused tile of its Space.
    /// A window held as a possible tab is released, so it cannot take over a tile once floated.
    /// False for a window dinky has not classified.
    @discardableResult
    func setFloating(_ id: WindowID, _ floating: Bool) -> Bool {
        guard let placement = placements[id], let window = model.windows[id] else { return false }
        if let space = placement.space { edit(space) { $0.remove(id) } }
        heldTabs[id] = nil
        filledFrom[id] = nil
        placements[id] = Placement(floating: floating, space: nil)
        track(window)
        flush()
        return true
    }

    /// Floats a tiled window, then glides it to cells of a grid over its display's visible area, inside the
    /// display's gaps; the tiles it leaves close up at the same time. Nil once placed, else why not.
    func place(_ id: WindowID, on grid: GridPlacement) -> String? {
        guard enabled else { return "dinky is off" }
        guard let placement = placements[id], model.windows[id] != nil else { return "no window dinky manages is focused" }
        guard let display = displays.display(ofWindow: id) else { return "window \(id) is on no display" }
        if !placement.floating { setFloating(id, true) }
        placeFloating(id, at: grid.frame(in: display.visibleArea, gaps: gaps(on: display)))
        return nil
    }

    // MARK: Floating windows

    /// The tiling commands on a floating window: `change` gets where the window is (or is gliding to) and the
    /// display's visible area inside its gaps, and returns where it goes, or nil to leave it. Nil once done or
    /// left, else why not.
    func floating(_ id: WindowID, _ change: (_ frame: CGRect, _ area: CGRect) -> CGRect?) -> String? {
        guard enabled else { return "dinky is off" }
        guard placements[id]?.floating == true else { return "the focused window does not float" }
        guard let display = displays.display(ofWindow: id), let frame = floatingFrame(of: id) else {
            return "window \(id) is on no display"
        }
        if let target = change(frame, gaps(on: display).inset(display.visibleArea)), target != frame {
            placeFloating(id, at: target)
        }
        return nil
    }

    /// `fullscreen` for a floating window: fill the display, or go back to the frame it had before.
    func toggleFloatingFullscreen(_ id: WindowID) -> String? {
        floating(id) { frame, area in
            let filled = FloatingFrame.filling(area)
            // By where dinky sent it: an app that snaps to a grid (Terminal) never lands on the frame exactly.
            if let before = filledFrom[id], floatingTargets[id] == filled {
                filledFrom[id] = nil
                return before
            }
            filledFrom[id] = frame
            return filled
        }
    }

    /// The tree of the Space a window is on now, tiled or not, for workspace-wide commands. Nil if it has none.
    func spaceKey(of id: WindowID) -> UInt64? {
        placements[id]?.space ?? displays.display(ofWindow: id).map(\.currentSpaceID)
    }

    /// Runs a change on a whole Space's tree and applies it. Nil if the Space has no tree.
    func command<T>(onSpace key: UInt64, _ change: (inout Workspace) -> T) -> T? {
        let result = edit(key, change)
        flush()
        return result
    }

    /// Moves a window dinky just moved to another Space into that Space's tree now, rather than on the next event.
    /// macOS leaves keyboard focus with the moved window, so unless we are about to follow it, focus the window
    /// that took its place in the tree it left.
    func windowMoved(_ id: WindowID, refocus: Bool = true) {
        guard model.windows[id] != nil else { return }
        // The tree's own record: by now macOS has already re-pointed the app's frontmost window elsewhere.
        let from = placements[id]?.space
        let hadFocus = from.flatMap { workspaces[$0]?.focused } == id
        // Re-reads its Space; the update it publishes reaches handle, which tracks the window and flushes.
        model.refresh(id)
        guard refocus, hadFocus, let from, let successor = workspaces[from]?.focused, successor != id else { return }
        focus(successor)
    }
}
