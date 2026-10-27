import AppKit
import DinkyLayout
import DinkyPrivate

// Dragging a tiled window with the mouse. On release, a drag that moved one edge of the window on an axis is a resize:
// the tree takes the new size and the other tiles make room. Any other drag is a move, dropped by what is under the
// pointer (`Workspace.dropHit`): over a tile, in the middle of it the two swap, nearer an edge the tile splits and the
// window takes the half on that side; over an inner gap, the nearest tile; over the menu bar, the Dock or an outer gap,
// the tile along that edge; over its own place, or nowhere to drop, the window goes back. Only frames that change while
// the mouse button is down, with the pointer on the window, count as a drag, which keeps dinky's own frame writes and
// apps moving themselves out of it, and so does macOS taking the window to another display's Space with the button down
// and the pointer on that display, which an app can tell of before any frame change. A frame change on its own display
// counts only once the window has gone more than a press's drift from where it was as the button went down, other than
// into its tile (`WindowPress`): an app can tell of its window moving as a click activates it without moving it, a hand
// pressing drifts a point or so, and focusing the window can lay its tile out elsewhere, as a strip that centres the
// focused column does when the focus comes too late for the click to hold it still, while the window stays where it
// was pressed till the button is up. A drag that leaves the window back there, with no drop shown, was a click too.
// With `[drag] mouse-modifier` set, only a window grabbed with it held drops on its own display: a window moved by its
// title bar alone goes back there, while an edge dragged still resizes. A grabbed window is moved by dinky
// (ModifierDrag.swift), so it starts and ends its drag itself; it only moves, so it always drops by what is under the
// pointer.
//
// In a scrolling strip a window goes between columns, before or after the one under the pointer by the side it is on,
// swaps with it in a narrow band down its middle, or stacks into it at its top or bottom; past the columns in view,
// over a parked sliver or the gutter, it goes beside the nearest one in view.
//
// The tile under the pointer is looked for in the tree shown on the display under it, so a window dragged over another
// display drops into that tree by the same zones as in its own: in a tile's place, the tile going to the window's own
// place, or beside it, the tile split; into a tree with no tile, as a new window goes. There a drag without
// `[drag] mouse-modifier` drops too.
//
// What a drop does is worked out once, on copies of the trees it changes (`DropPlan`), and that is what shows and what
// happens. Once the pointer has rested on a drop for a moment, the windows of those trees go where it leaves them,
// making room, a strip scrolling as it will, and a placeholder the shape of a window fills the frame the dragged window
// will have, between them (DragPlaceholders.swift). The trees themselves change only on release, when they take the
// drop as it shows; while it would go back, the windows are where the trees have them. Wherever the trees as they are
// ask for the drop shown, and till the pointer has moved a little from where it last asked for it, the drop stays, so
// the windows making room cannot put another under a pointer at rest for it to ask for; anywhere else it is over what
// shows, where over the frame the drop shown gives the window the drop stays, unless it is a swap and the tile swapped
// with is under the pointer as the trees are, whose zones still count, or it is beside a tile and the trees as they are
// have the pointer in the top or bottom band of a tile there, slid or shrunk from under it to make room, which stacks
// onto it (`DropHit.stacks`), in tiles and strip columns alike. In a strip, the column the window drops into or
// beside stays where it shows as far as the strip scrolls, so the drop does not move it from under the pointer, as
// taking a column out left of it would. macOS moves a window dragged over another display to its Space on the way, more
// than once if it goes back and forth: the tree keeps the window till the drop (`track`), which then moves it to the
// Space of the tree it ends up in, and puts it in its tile again a moment later if it is not there, as when the window
// server was still settling it on its new Space. One macOS takes to another Space of its own display, as switching
// Spaces holding it does, or Mission Control, drops only where the pointer asks it to there, its own Space out of
// sight, and not in a swap, which would send the window swapped with there; with nothing to drop onto, it stays, as one
// moved there would. While Mission Control is open, it would go back.

/// A tiled window being dragged with the mouse, from the first frame change that takes it from where it was pressed,
/// or the grab with `[drag] mouse-modifier`, until the button comes up.
struct DragSession {
    let id: WindowID
    /// The Space of the tree the window came from.
    let home: UInt64
    /// Whether it drops wherever the pointer is: any drag without `[drag] mouse-modifier`, and one with it held. Any
    /// other drops only over another display, and goes back anywhere else.
    let drops: Bool
    /// Where a window grabbed with `[drag] mouse-modifier` was last sent, and the pointer that sent it there; nil while
    /// the system drags one. The pointer is the drag's own: the session never sees the swallowed drag, so asking it for
    /// the pointer can answer with where the button went down.
    var held: (frame: CGRect, pointer: CGPoint)?
    /// Where the window was as it was grabbed: as the button went down on it, or as `[drag] mouse-modifier` took it.
    /// While it shows there, give or take a press's drift, the drag is a click, whatever focusing it lays its tile out
    /// to. Nil for one macOS took to another display's Space, which is dragged wherever it was pressed.
    var grabbed: CGRect?
    /// When the drag began, which tells it from the next.
    var began = CACurrentMediaTime()
    /// The drop shown, whose trees are laid out in place of the real ones; nil while the window would go back.
    var shown: DropPlan?
    /// Where the pointer was as it last asked for the drop shown: till it has gone `stir` from there, what the windows
    /// making room have put under it asks for nothing.
    var askedAt: CGPoint?
    /// Another drop the pointer has asked for since `since`, nil for going back: it shows once asked for `settle`.
    var asked: (plan: DropPlan?, since: CFTimeInterval)?
    /// When the drop shown last changed.
    var changed: CFTimeInterval = 0
    /// What the log last said the drag would do.
    var logged: String?
    /// The Space a held window was last seen on, to raise it when macOS moves it to another display's.
    var space: UInt64?
    /// Why the drag would go back, for the log.
    var why: String?

    /// How long the pointer asks for another drop before it shows: windows make room for a drop rested on, not for each
    /// tile passed over.
    static let settle: CFTimeInterval = 0.1
    /// How long a drop shows at least, so windows making room under a still pointer cannot send it back and forth.
    static let hold: CFTimeInterval = 0.25
    /// How far the pointer goes from where it last asked for the drop shown before what shows under it counts.
    static let stir: CGFloat = 8
}

/// What dropping a dragged window does, worked out on copies of the trees it changes: the feedback shows it, and the
/// drop applies it.
struct DropPlan: Equatable {
    /// The Space of the tree the window drops into: onto `target` in `zone`, or, without one, as a new window goes.
    let key: UInt64
    let target: WindowID?
    let zone: DropZone
    /// In a strip, where the column the window drops into or beside starts on screen: where it shows under the pointer
    /// that asked for the drop, so the drop leaves it there rather than scroll it from under the pointer, as taking a
    /// column out left of it would. Nil, the strip scrolls as the drop scrolls it.
    let anchor: CGFloat?
    /// The trees the drop changes, as it leaves them: the window's own, and the one it drops into.
    let trees: [UInt64: Workspace]
    /// Windows the drop takes to another Space's tree, by that Space: the dragged one, and one it swaps with.
    let moving: [WindowID: UInt64]
    /// The dragged window's frame once dropped.
    let frame: CGRect

    /// The same drop: what it leaves, whatever zone led there.
    static func == (a: DropPlan, b: DropPlan) -> Bool { a.key == b.key && a.trees == b.trees }

    /// For the log, from a drag out of the tree of `home`.
    func described(home: UInt64) -> String {
        let space = key == home ? "" : " on Space \(key)"
        return (target.map { "over \($0), \(zone)\(space)" } ?? "into Space \(key)") + ", to \(frame)"
    }
}

extension Coordinator {
    /// How far outside a window the pointer can be and still have its frame changes count as a drag of it: the edges
    /// macOS resizes a window by reach a little outside it.
    private static let grip: CGFloat = 12
    /// How far a window macOS has moved to another display's Space can trail the pointer and still count as dragged:
    /// one dragged fast over the display is seen first well behind the pointer, as the window server catches up.
    private static let trail: CGFloat = 400

    /// Window `id` moved or resized from `before`, where the model had it. With the button down on it, tiled, that is a
    /// drag once the window has gone from where it was pressed (`notePress`), or at once when macOS has taken it to
    /// another display's Space.
    func noteFrameChange(of id: WindowID, from before: CGRect?) {
        // A window held with `[drag] mouse-modifier` shows as the pointer moves it (`heldDragMoved`), not again as it
        // tells of each frame dinky sent it.
        if dragging == id { return drag?.held == nil ? showDrag() : () }
        // Only tiled windows have a Space.
        guard dragging == nil, !mouseDragsStrip, let home = placements[id]?.space, !isAnimating(id), mouseButtonDown,
              !MissionControl.shared.active, let window = model.windows[id], let pointer = CGEvent(source: nil)?.location
        else { return }
        let away = window.spaceID != home
            && displays.display(containingSpace: window.spaceID)?.frame.contains(pointer) == true
        let reach = away ? Self.trail : Self.grip
        // Where the window server has it too: an app can tell of a window the system drags late, the pointer gone on
        // from where the app had it.
        let live = dinky_window_info(id)
        guard ([window.frame] + (live.exists ? [live.frame] : [])).contains(where: {
            $0.insetBy(dx: -reach, dy: -reach).contains(pointer)
        }) else { return }
        // On another display's Space, it is dragged, however little its app has told of it moving yet.
        guard !away else { return startDrag(of: id) }
        notePress(on: id, at: window.frame, from: before ?? window.frame, home: home)
    }

    /// The button is down on window `id`, tiled on `home`, which has gone from `before` to `frame`: a drag from where
    /// it was pressed once it has gone from there, other than into its tile; till then a click, whatever focusing it
    /// has laid its tile out to (`WindowPress`). The first change a press brings is logged, and the press watched.
    private func notePress(on id: WindowID, at frame: CGRect, from before: CGRect, home: UInt64) {
        let known = windowPress
        let press = WindowPress.of(id, at: pressedAt, from: before, known: known)
        let tile = workspaces[home]?.layout().frames[id].map { restingFrame(of: id, at: $0) }
        windowPress = press.after(frame, tile: tile)
        guard windowPress != nil else { return startDrag(of: id, grabbed: press.frame) }
        guard press != known else { return }
        print("\(stamp()) drag: \(id) at \(frame) under a press, at \(press.frame) as it was pressed: a click so far")
        watchPressEnd(press)
    }

    /// Looks at a press that has not dragged its window every 50 ms till the button comes up, then lays the window's
    /// tree out again if the press left the window off its tile, as a drag that goes back does. A drag the press turns
    /// into, or a newer press, takes over from it.
    private func watchPressEnd(_ press: WindowPress) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, windowPress?.id == press.id, windowPress?.at == press.at else { return }
            guard !mouseButtonDown else { return watchPressEnd(press) }
            windowPress = nil
            // Pins the press held off raising.
            defer { raiseCoveredPins() }
            guard let key = placements[press.id]?.space, !isAnimating(press.id), let window = model.windows[press.id],
                  let tile = workspaces[key]?.layout().frames[press.id],
                  !window.frame.isClose(to: restingFrame(of: press.id, at: tile), within: 2) else { return }
            dirty.insert(key)
            flush()
        }
    }

    /// Window `id`, tiled, has gone to `space`, on another display, as macOS takes a window dragged over one. With the
    /// mouse button down and the pointer on that display, that is a drag, from the tree it is still in: an app can tell
    /// of the window moving only now, or of a fast drag only once it is there, the pointer gone on from where it had it.
    func noteDisplayChange(of id: WindowID, to space: UInt64) {
        guard dragging == nil, let pointer = CGEvent(source: nil)?.location,
              displays.display(containingSpace: space)?.frame.contains(pointer) == true else { return }
        startDrag(of: id)
    }

    /// Starts the drag of window `id` the system has, from `grabbed`, where the window was as the button went down on
    /// it; from nowhere in particular for one macOS took to another display's Space.
    private func startDrag(of id: WindowID, grabbed: CGRect? = nil) {
        guard dragging == nil, let home = placements[id]?.space, !isAnimating(id), mouseButtonDown,
              !MissionControl.shared.active else { return }
        windowPress = nil
        drag = DragSession(id: id, home: home, drops: config.drag.mouseModifier.isEmpty, grabbed: grabbed)
        // From where it was pressed to where it is, so a bug report shows how far a press went before it was a drag.
        let from = grabbed.flatMap { start in model.windows[id].map { ", from \(start) to \($0.frame)" } } ?? ""
        print("\(stamp()) drag: \(id) moved with the mouse, tiled on Space \(home)" + from
              + (config.drag.mouseModifier.isEmpty ? "" : ", without \(config.drag.mouseModifier.name) held"))
        showDrag()
        watchDragEnd()
    }

    /// Looks at the drag every 50 ms till it ends, so what it shows follows the trees under a pointer at rest too: a drop
    /// asked for shows once it has been for long enough, and the drop shown takes in a minimum size a window making room
    /// for it has just shown, which moves where it puts the dragged window. One the system has ends here, as the button
    /// comes up; a held one, at `endHeldDrag`.
    private func watchDragEnd(_ began: CFTimeInterval? = nil) {
        guard let began = began ?? drag?.began else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let id = dragging, drag?.began == began else { return }
            if drag?.held != nil || mouseButtonDown {
                showDrag()
                watchDragEnd(began)
            } else {
                finishDrag(id)
            }
        }
    }

    /// Drags a tiled window grabbed with `[drag] mouse-modifier` at `frame` by `pointer`, until `endHeldDrag`.
    func startHeldDrag(of id: WindowID, at frame: CGRect, pointer: CGPoint) {
        guard dragging == nil, let home = placements[id]?.space else { return }
        drag = DragSession(id: id, home: home, drops: true, held: (frame, pointer), grabbed: frame)
        showDrag()
        watchDragEnd()
    }

    /// The pointer dragged a window grabbed with `[drag] mouse-modifier` to `pointer`, and it was sent to `frame`. The
    /// feedback follows the drag from here, not the window's frame changes, which come later from the app, if at all.
    func heldDragMoved(_ id: WindowID, to frame: CGRect, pointer: CGPoint) {
        guard dragging == id else { return }
        drag?.held = (frame, pointer)
        showDrag()
    }

    /// The button let go of a window grabbed with `[drag] mouse-modifier`: it drops by where it was last sent.
    func endHeldDrag(of id: WindowID) {
        guard dragging == id else { return }
        finishDrag(id)
    }

    private func finishDrag(_ id: WindowID) {
        guard let session = drag, session.id == id else { return }
        drag = nil
        placeholders.hide()
        dropped(session)
    }

    private func dropped(_ session: DragSession) {
        let id = session.id
        // The trees laid out in place of the real ones are laid out again: as the drop leaves them, or as they are.
        if let shown = session.shown { dirty.formUnion(shown.trees.keys) }
        var stays = false
        defer {
            if stays {
                // Out of its tree, and into the one of the Space it is on if dinky tiles it, as any window moved there.
                model.refresh(id)
            } else if let space = placements[id]?.space {
                // Back to its tile, wherever that is now, on the Space of its tree: macOS may have moved it on the way.
                bring([id: space])
                dirty.insert(space)
            }
            // A strip a click held still for the drag scrolls to the window the click focused, now the drag is over;
            // while the click still holds the passes, its release does that.
            revealClickedFocus()
            flush()
            // Pins the drag held off raising, once it is over.
            DispatchQueue.main.async { [weak self] in self?.raiseCoveredPins() }
        }
        // The drop shown, worked out again on the trees as they are now, unless the pointer has asked for another for
        // `DragSession.settle` and still does; when none showed yet, the one the pointer was asking for; with no feedback
        // at all, the one under the pointer as the button came up. None into a Space out of
        // sight by now, as one switched away from holding the window: that would take the window there.
        func chosen() -> DropPlan? {
            let pointer = session.held?.pointer ?? CGEvent(source: nil)?.location
            let unshown = config.drag.placeholders ? nil
                : pointer.flatMap { point -> DropPlan? in
                    if case .plan(let plan) = asked(by: session, at: point) { return plan }
                    return nil
                }
            // A drop the pointer has asked for a while and still asks for, though the one shown has not had its time yet
            // to give way to it: the one let go over.
            // Going back, too: settled and still asked for, nil.
            let pending = session.asked.flatMap { asked -> DropPlan?? in
                guard CACurrentMediaTime() - asked.since >= DragSession.settle, let pointer else { return nil }
                switch self.asked(by: session, at: pointer) {
                case .plan(let now) where asked.plan == now: return .some(now)
                case .back where asked.plan == nil: return .some(nil)
                default: return nil
                }
            }
            switch pending {
            case .some(.none): return nil
            case .some(.some(let plan)):
                if let plan = replan(plan, of: session) { return inSight(plan.key) ? plan : nil }
            case .none: break
            }
            let plan = (session.shown ?? session.asked?.plan).flatMap({ replan($0, of: session) }) ?? unshown
            return plan.flatMap { inSight($0.key) ? $0 : nil }
        }
        if let space = carried(session) {
            // Not into its own Space, even in sight, as Mission Control leaves it: that would take it back.
            if let plan = chosen(), plan.key != session.home {
                print("\(stamp()) drag: dropped \(id) \(plan.described(home: session.home)), taken along to Space \(space)")
                commit(plan, of: id)
            } else {
                print("\(stamp()) drag: \(id) taken along to Space \(space), out of sight of its own, left there")
                stays = true
            }
            return
        }
        guard let key = placements[id]?.space, let window = model.windows[id],
              let tile = workspaces[key]?.layout().frames[id] else { return }
        let frame = session.held?.frame ?? window.frame
        let resting = restingFrame(of: id, at: tile)
        // Nothing shown, on its tile or still where it was grabbed: a click, whatever focusing laid its tile out to.
        if session.shown == nil, frame.isClose(to: resting, within: 2) || stillWhereGrabbed(session) { return }
        // A held window keeps its size, even one bigger than its tile: it only moved.
        if session.held == nil, session.shown == nil, let edges = movedEdges(from: resting, to: frame) {
            // The window shows it goes down to this size: a minimum it was laid out around that is bigger was wrong.
            let lowered = applier.saw(frame.size, of: id, app: window.bundleID)
            let resized = edit(key) { tree in
                tree.minimumSizes = minimumSizes(in: tree)
                return tree.resize(id, to: frame.size, moving: edges)
            } ?? false
            print("\(stamp()) drag: resized \(id) from \(resting.size) to \(frame.size), edges \(edges.map { "\($0)" }.sorted()), "
                  + (resized ? "taken" : "not taken\(workspaces[key]?.fullscreenWindows.isEmpty == false ? " (fullscreen)" : "")")
                  + (lowered ? ", the minimum it was laid out around lowered to it" : ""))
            return
        }
        guard let plan = chosen() else {
            print("\(stamp()) drag: \(id) " + (session.drops ? "back to its tile" : "moved without \(config.drag.mouseModifier.name) held, back to its tile")
                  + (session.why.map { ", \($0)" } ?? ""))
            return
        }
        print("\(stamp()) drag: dropped \(id) \(plan.described(home: session.home))"
              + (session.drops ? "" : " without \(config.drag.mouseModifier.name) held"))
        commit(plan, of: id)
    }

    /// The Space macOS has taken the dragged window to, out of its own: any while its own is out of sight, as after
    /// switching Spaces holding it, where going back would hide it; another of its own display's, as Mission Control
    /// puts it on, whatever the display shows, which the model can be late to tell of; one the model does not know yet,
    /// as Mission Control makes for a window dropped on its new desktop; or any while Mission Control is open. Nil on its
    /// own Space, or another display's it was dragged over.
    private func carried(_ session: DragSession) -> UInt64? {
        let space = dinky_window_space_id(session.id)
        guard space != 0, space != session.home else { return nil }
        guard inSight(session.home), !MissionControl.shared.active,
              let display = displays.display(containingSpace: space) else { return space }
        return display.spaces.contains(session.home) ? space : nil
    }

    /// Whether the dragged window is still where it was grabbed, give or take a press's drift: where it was last sent,
    /// for one grabbed with `[drag] mouse-modifier`, or where the window model last read it.
    private func stillWhereGrabbed(_ session: DragSession) -> Bool {
        guard let grabbed = session.grabbed,
              let frame = session.held?.frame ?? model.windows[session.id]?.frame else { return false }
        return frame.isClose(to: grabbed, within: WindowPress.slack)
    }

    /// Whether `space` is the one its display shows, as the window server has it: the model can be late to tell of a
    /// switch.
    private func inSight(_ space: UInt64) -> Bool {
        guard let display = displays.display(containingSpace: space) else { return false }
        return dinky_current_space_id(display.uuid as CFString) == space
    }

    /// Gives the trees what `plan` leaves them, making a tree for a Space that has none yet, and takes the windows it
    /// moves to the Spaces of their new trees.
    private func commit(_ plan: DropPlan, of id: WindowID) {
        for (key, tree) in plan.trees {
            if let display = displays.display(containingSpace: key) { makeWorkspace(key, on: display) }
            // A pin the drop took apart was unpinned by hand: its rule leaves it so.
            let before = Set(workspaces[key]?.pinnedWindows ?? [])
            unpinnedByHand.formUnion(before.subtracting(tree.pinnedWindows))
            // Dropped, the strip scrolls back within its ends, the column under the pointer with it.
            edit(key) { $0 = tree; $0.keepsScroll = false }
            dirty.insert(key)
        }
        guard !plan.moving.isEmpty else {
            // On its own display too, a pass the drop shown left gliding may have skipped it, held out of that glide
            // while the button was down: it is checked as one taken across is.
            if let space = placements[id]?.space { for delay in [0.4, 1.0] { checkLanding(of: [id: space], after: delay) } }
            return
        }
        for (window, space) in plan.moving {
            placements[window]?.space = space
            arriving[window] = space
            // One going to the display the dragged window came from is placed there at once: a glide would set out from
            // where it is, on the other display.
            if window != id { placeAtOnce(space) }
        }
        bring(plan.moving, refreshing: true)
        for delay in [0.3, 1.0] { checkLanding(of: plan.moving, after: delay) }
    }

    /// The strip of the workspace on Space `key` as `snapshot` had it before a display change poured its windows onto
    /// another display, put back as `returning`, those windows, are moved home: in its order, at its widths, its pins
    /// pinned, without windows gone since and with any its Space has now that it did not. They leave the trees they
    /// were poured into at once, and arrive in it rather than come in as new windows (`arriving`).
    func restoreStrip(_ snapshot: Workspace, on key: UInt64, returning: [WindowID]) {
        guard let display = displays.display(containingSpace: key) else { return }
        makeWorkspace(key, on: display)
        let current = workspaces[key]!, coming = Set(returning)
        // Not a window floated by hand since: it stays floating, out of the strip.
        let present = Set(snapshot.windows.filter { id in
            model.windows[id] != nil && (coming.contains(id) || current.contains(id))
                && !(placements[id].map { $0.floating && !$0.freed } ?? false)
        })
        var tree = snapshot.restored(keeping: present, adding: current.windows.filter { !snapshot.contains($0) })
        (tree.bounds, tree.gaps, tree.walls) = (current.bounds, current.gaps, current.walls)
        // On a display of another size, or gaps, its pins and band are fitted to it as a pass would.
        if snapshot.bounds != tree.bounds || snapshot.gaps != tree.gaps {
            tree.minimumSizes = minimumSizes(in: tree)
            tree.fitBand()
            tree.fitPins()
        }
        // A display put beside it, moved away or resized meanwhile: lined up with the walls it has now, where it shows.
        if snapshot.walls != tree.walls || snapshot.bounds != tree.bounds || snapshot.gaps != tree.gaps {
            tree.alignToWalls()
        }
        let back = returning.filter { tree.contains($0) && placements[$0]?.space != key }
        for (old, ids) in Dictionary(grouping: back.filter { placements[$0]?.space != nil }, by: { placements[$0]!.space! }) {
            edit(old) { workspace in for id in ids { workspace.remove(id) } }
        }
        edit(key) { $0 = tree }
        for id in back {
            // One floating only because a free workspace had it (`freed`) is tiled again, as `track` takes it back; one
            // with no placement yet gets one, so it is watched as it lands like the rest.
            if placements[id]?.floating != false {
                placements[id] = Placement(floating: false, space: key)
                filledFrom[id] = nil
                griddedFrom[id] = nil
                heldTabs[id] = nil
            } else {
                placements[id]?.space = key
            }
        }
        print("\(stamp()) workspaces: strip on Space \(key) put back as it was, \(back.count) windows returning"
              + (tree.pins.isEmpty ? "" : ", pinned \(tree.pins.values.sorted())"))
        // Not taken in again as they come: watched as they land, and laid out at once, once they are home
        // (`WorkspaceNumbers.returnDisplaced`), not glided across from where macOS poured them.
        for id in back { arriving[id] = key }
        dirty.insert(key)
    }

    /// Windows already in the trees of their Spaces in `moves` while macOS still moves them there: not taken in again as
    /// they arrive, and looked at a moment later, as a drop's are, all together, put right if they did not land.
    func watchArrival(_ moves: [WindowID: UInt64]) {
        guard !moves.isEmpty else { return }
        arriving.merge(moves) { $1 }
        for delay in [0.3, 1.0] { checkLanding(of: moves, after: delay) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            for (id, space) in moves where self?.arriving[id] == space { self?.arriving[id] = nil }
        }
    }

    /// After `delay`, puts each window that is not on its tree's Space or in its tile yet there again, saying so: one
    /// just moved to another display's Space can refuse its first frames while the window server settles it there. The
    /// last look gives up on one still on another Space, which then joins the tree of the Space it is on.
    private func checkLanding(of moves: [WindowID: UInt64], after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            var astray: [WindowID: UInt64] = [:]
            // Not one moved on since to another Space, whose own check that is.
            for (id, space) in moves where placements[id]?.space == space && dragging != id
                && arriving[id].map({ $0 == space }) ?? true {
                let info = dinky_window_info(id)
                guard info.exists else {
                    arriving[id] = nil
                    continue
                }
                let on = dinky_window_space_id(id)
                if on != 0, on != space {
                    astray[id] = space
                    continue
                }
                guard !isAnimating(id), let tile = workspaces[space]?.layout().frames[id] else { continue }
                let resting = restingFrame(of: id, at: tile)
                // Nor one where its app last put it for that tile, a few points off as some snap to their own grid: at the
                // tile's corner, only its size off. One that stayed where it was let go refused the write, and goes again.
                let snaps = abs(info.frame.minX - resting.minX) <= 2 && abs(info.frame.minY - resting.minY) <= 2
                    && rests(id, at: info.frame, askedFor: tile)
                guard !info.frame.isClose(to: resting, within: 2), !snaps else { continue }
                print("\(stamp()) drag: \(id) at \(info.frame) on Space \(on) \(delay)s after the drop, "
                      + "not where its tile leaves it, \(resting), on Space \(space): placed again")
                dirty.insert(space)
            }
            if !astray.isEmpty {
                print("\(stamp()) drag: \(astray.keys.sorted()) not on the Spaces of their trees \(delay)s after the drop, moved again")
                bring(astray)
                if delay >= 1 {
                    for id in astray.keys where arriving.removeValue(forKey: id) != nil {
                        print("\(stamp()) drag: \(id) did not reach Space \(astray[id]!), left on Space \(dinky_window_space_id(id))")
                        model.refresh(id)
                    }
                }
                dirty.formUnion(astray.values)
            }
            flush()
        }
    }

    /// Moves each window to its Space if it is not on it, all at once, waits a moment for them to get there, and has
    /// the model read them again: every one with `refreshing`, so the model has the Space macOS moved it to on the way.
    /// A window on its Space is no longer arriving.
    private func bring(_ moves: [WindowID: UInt64], refreshing: Bool = false) {
        var away: [WindowID: UInt64] = [:]
        for (id, space) in moves {
            let now = dinky_window_space_id(id)
            if now != 0, now != space { away[id] = now }
        }
        for (space, ids) in Dictionary(grouping: away.keys, by: { moves[$0]! }) {
            var ids = ids
            if !dinky_move_windows_to_space(&ids, Int32(ids.count), space) {
                print("\(stamp()) drag: could not ask for \(ids.sorted()) to move to Space \(space)")
            }
        }
        // Each done once it is there, or once it has left for another Space, where macOS put it instead.
        if !away.isEmpty {
            _ = waitUntil(0.5) {
                away.allSatisfy { id, was in
                    let now = dinky_window_space_id(id)
                    return now == moves[id] || now != 0 && now != was
                }
            }
        }
        for (id, was) in away {
            let now = dinky_window_space_id(id)
            print("\(stamp()) drag: \(id) on Space \(was), \(now == moves[id] ? "moved" : "could not move") to Space \(moves[id]!)")
        }
        for (id, space) in moves where dinky_window_space_id(id) == space { arriving[id] = nil }
        for id in moves.keys where refreshing || away[id] != nil { model.refresh(id) }
    }

    // MARK: Feedback

    /// Shows what the drag does from where it is now. The drop under the pointer shows once the pointer has asked for it
    /// for `DragSession.settle`, and not sooner than `DragSession.hold` after the last: the windows of the trees it
    /// changes go where it leaves them, and the placeholders fill the frame the dragged window will have, and where a
    /// window it swaps with from another display will go. While it would go back, the windows are where the trees have
    /// them, and a quiet outline shows where it goes back to, for a drag that drops, unless macOS has taken it along to
    /// another Space of its display, where it stays.
    func showDrag() {
        guard var session = drag else { return }
        guard config.drag.placeholders else { return placeholders.hide() }
        guard let window = model.windows[session.id], let tile = workspaces[session.home]?.layout().frames[session.id] else {
            return placeholders.hide()
        }
        let now = CACurrentMediaTime()
        let frame = session.held?.frame ?? window.frame
        let home = restingFrame(of: session.id, at: tile)
        // Moved off its tile and from where it was grabbed, not resized: a held window only moves, even one bigger than
        // its tile.
        let still = stillWhereGrabbed(session)
        let moved = !still && !frame.isClose(to: home, within: 2) && (session.held != nil || movedEdges(from: home, to: frame) == nil)
        if session.held != nil { raiseOnNewSpace(&session) }
        let before = session.shown
        // The drop shown as it is on the trees now, which can have changed under it, as when focus moved.
        session.shown = before.flatMap { replan($0, of: session) }
        var wanted: DropPlan?, asking: CGPoint?
        if moved, let pointer = session.held?.pointer ?? CGEvent(source: nil)?.location {
            switch asked(by: session, at: pointer) {
            case .keep: wanted = session.shown
            case .back(let why): session.why = why
            case .plan(let plan): (wanted, asking) = (plan, pointer)
            }
        } else {
            session.why = moved ? "no pointer" : still ? "where it was grabbed"
                : frame.isClose(to: home, within: 2) ? "on its tile" : "resized, not moved"
        }
        if wanted == session.shown {
            // The same drop, maybe by another zone or tile: the look and the log follow the one the pointer is over.
            if let wanted { session.shown = wanted }
            if let asking { session.askedAt = asking }
            session.asked = nil
        } else if let asked = session.asked, asked.plan == wanted {
            if now >= max(asked.since + DragSession.settle, session.changed + DragSession.hold) {
                session.shown = wanted
                session.askedAt = asking
                session.changed = now
                session.asked = nil
            }
        } else {
            session.asked = (wanted, now)
        }
        // One line each time what the drop would do changes, so a bug report shows what the feedback was.
        let described = session.shown.map { $0.described(home: session.home) + ", making room" }
            ?? "goes back" + (session.why.map { ", \($0)" } ?? "")
        if described != session.logged, session.shown != nil || session.logged != nil {
            print("\(stamp()) drag: \(session.id) \(described)")
            session.logged = described
        }
        drag = session
        if session.shown != before {
            if let before { dirty.formUnion(before.trees.keys) }
            if let shown = session.shown { dirty.formUnion(shown.trees.keys) }
            flush()
        }
        place(session, moved: moved, home: home)
    }

    /// The placeholders for what `session` shows.
    private func place(_ session: DragSession, moved: Bool, home: CGRect) {
        let radius = { [self] (id: WindowID) in CGFloat(model.windows[id]?.cornerRadius ?? 0) }
        placeholders.update(style: config.drag)
        if let plan = session.shown {
            let partner = plan.moving.first { $0.key != session.id }.flatMap { other, space in
                plan.trees[space]?.layout().frames[other].map { (frame: restingFrame(of: other, at: $0), radius: radius(other)) }
            }
            placeholders.show(dragged: session.id, preview: (restingFrame(of: session.id, at: plan.frame), radius(session.id)),
                              partner: partner, home: nil, swap: plan.target != nil && plan.zone == .swap)
        } else if moved, session.drops, config.drag.homeOutline, carried(session) == nil {
            placeholders.show(dragged: session.id, preview: nil, partner: nil, home: (home, radius(session.id)), swap: false)
        } else {
            placeholders.hide()
        }
    }

    /// The tree to lay out for the Space `key` while a drag makes room on it: as the drop shown leaves it. Nil, the tree
    /// itself.
    func dragShows(_ key: UInt64) -> Workspace? { drag?.shown?.trees[key] }

    /// The windows no pass may write while a drag is under way: the one dragged, which the user has, and one the drop
    /// shown takes to another display, which stays on its own till the drop (`dragWaiting`).
    var dragFrozen: Set<WindowID> {
        guard let drag else { return [] }
        return Set(drag.shown.map { Array($0.moving.keys) } ?? []).union([drag.id])
    }

    /// Where the window the drop shown swaps from the tree of `key` to another display's waits till the drop: in the
    /// tile it leaves the dragged window, as the tree shows, under its placeholder, at the size it comes to rest at there
    /// and wholly on its display, past which macOS would take it to another display's Space; not where an earlier drop
    /// shown had it, nor in its tile as the tree is, which a strip scrolled otherwise shows over another column.
    func dragWaiting(on key: UInt64) -> [WindowID: CGRect] {
        guard let drag, let shown = drag.shown, let tree = workspaces[key], let shows = shown.trees[key],
              let slot = shows.layout().frames[drag.id] else { return [:] }
        let leaving = shown.moving.keys.filter { $0 != drag.id && tree.contains($0) }
        return Dictionary(uniqueKeysWithValues: leaving.map { id -> (WindowID, CGRect) in
            var frame = shows.keptOffWalls(restingFrame(of: id, at: slot))
            frame.origin.y = max(min(frame.minY, shows.bounds.maxY - frame.height), shows.bounds.minY)
            return (id, frame)
        })
    }

    private enum Ask {
        /// The drop shown: the pointer is over where it puts the window.
        case keep
        /// Going back, and why.
        case back(String)
        case plan(DropPlan)
    }

    /// What the pointer at `point` asks of the drag, by what it is over in the tree of the display under it. Where that
    /// tree as it is asks for the drop shown, that drop, whatever the windows making room have put there; so too till
    /// the pointer has gone `stir` from where it last asked for it. Anywhere else, by what it is over in the tree as it
    /// shows: over the frame the drop shown gives the window, that drop, unless it is a swap and the window it swaps with
    /// is under the pointer as the trees are: its zones still count, so the pointer can go on from the middle of a lone
    /// window, which a swap covers, to beside it; or unless it is beside a tile and the tree as it is has the pointer in
    /// the top or bottom band of a tile there, the column making room having slid from under it (`DropHit.stacks`).
    /// A strip can show that frame over another window's tile, the dragged
    /// window's width in place of the one it swaps with, or its own, and those count for nothing there. Over its own
    /// tile as the trees are, from a drop shown on another display, going back, whatever that drop puts there; so too
    /// between displays, over a Space dinky does not tile, or in Mission Control.
    private func asked(by session: DragSession, at point: CGPoint) -> Ask {
        guard !MissionControl.shared.active else { return .back("in Mission Control") }
        guard let space = tiledSpace(at: point) else { return .back("over no Space dinky tiles") }
        guard session.drops || space.key != session.home else {
            return .back("on its own display without \(config.drag.mouseModifier.name) held")
        }
        let key = space.key
        let tree = prepared(workspaces[key] ?? newWorkspace(on: space.display, settings(for: key)))
        let real = tree.dropHit(at: point, in: tree.layout(), excluding: session.id)
        // Till the pointer stirs from where it asked for the drop shown, that drop, whatever the tree as it is asks for:
        // known before working any drop out, but where it goes back over its own place on another display.
        if let shown = session.shown, shown.trees[key] != nil, !(real == .own && shown.key != key),
           let at = session.askedAt, hypot(point.x - at.x, point.y - at.y) < DragSession.stir { return .keep }
        let asIs = ask(session, into: key, over: real, in: tree)
        guard let shown = session.shown, let shows = shown.trees[key] else { return asIs }
        if case .plan(let plan) = asIs, plan == shown { return .keep }
        if real == .own, shown.key != key { return asIs }
        if let at = session.askedAt, hypot(point.x - at.x, point.y - at.y) < DragSession.stir { return .keep }
        let hit = shows.dropHit(at: point, in: shows.layout(), excluding: session.id)
        guard hit == .own else { return ask(session, into: key, over: hit, in: shows) }
        // Over the dragged window's place in a drop beside a column, where that column showed: its top or bottom band
        // as the tree is stacks onto it.
        if real.stacks(overBeside: shown.zone, shows: hit) { return asIs }
        guard shown.zone == .swap, let partner = shown.target, case .tile(partner, _) = real else { return .keep }
        return asIs
    }

    /// What the pointer over `hit` in `shows`, the tree of `key` as it is or as the drop shown leaves it, asks for: over
    /// a tile, the drop onto it, unless that leaves everything as it is; over the window's own tile, going back; over
    /// nothing, the drop into the tree of another Space, or going back on its own.
    private func ask(_ session: DragSession, into key: UInt64, over hit: DropHit, in shows: Workspace) -> Ask {
        switch hit {
        case .own:
            return .back("over its own tile")
        case .none:
            guard key != session.home else { return .back("over nothing to drop onto") }
            guard let plan = plan(of: session, into: key, onto: nil, .swap) else { return .back("no drop into Space \(key)") }
            return .plan(plan)
        case .tile(let target, let zone):
            // Over a window the drop shown brings from another display: that is where it goes, so the drop stays.
            guard workspaces[key]?.contains(target) == true else {
                return session.shown == nil ? .back("over \(target), in no tree yet") : .keep
            }
            guard let plan = plan(of: session, into: key, onto: target, zone) else {
                return .back("over \(target), \(zone), no such drop")
            }
            guard !leavesAsIs(plan) else { return .back("over \(target), \(zone), where it is") }
            // In a strip, the column it drops into or beside stays where it shows, under the pointer.
            guard let x = shows.columnStart(of: target) else { return .plan(plan) }
            return .plan(self.plan(of: session, into: key, onto: target, zone, keeping: x) ?? plan)
        }
    }

    /// What dropping the dragged window into the tree of `key`, onto `target` in `zone`, does: worked out on copies of
    /// the trees, laid out as a pass lays them out, with a strip scrolled so the column it drops into or beside starts at
    /// `anchor` on screen, as near as it can. Nil when there is no such drop.
    private func plan(of session: DragSession, into key: UInt64, onto target: WindowID?, _ zone: DropZone,
                      keeping anchor: CGFloat? = nil) -> DropPlan? {
        let id = session.id, home = session.home
        guard var from = workspaces[home] else { return nil }
        var trees: [UInt64: Workspace], moving: [WindowID: UInt64] = [:]
        if key == home {
            guard let target, from.drop(id, onto: target, zone) else { return nil }
            trees = [home: from]
        } else {
            // No swap while the window's own Space is out of sight, as after switching Spaces holding it: the window
            // swapped with would go there.
            if target != nil, zone == .swap, !inSight(home) { return nil }
            guard var to = workspaces[key] ?? displays.display(containingSpace: key).map({ newWorkspace(on: $0, settings(for: key)) }),
                  to.receive(id, from: &from, onto: target, zone) else { return nil }
            trees = [home: from, key: to]
            moving[id] = key
            if let target, zone == .swap { moving[target] = home }
        }
        for (space, tree) in trees { trees[space] = prepared(tree) }
        // A swap puts the window in the column of the one it swaps with; any other drop keeps that one's column.
        if let anchor, let target { trees[key]?.scroll(columnOf: zone == .swap ? id : target, to: anchor, pastEnds: true) }
        guard let frame = trees[key]?.layout().frames[id] else { return nil }
        return DropPlan(key: key, target: target, zone: zone, anchor: anchor, trees: trees, moving: moving, frame: frame)
    }

    /// `plan` worked out again on the trees as they are now.
    private func replan(_ plan: DropPlan, of session: DragSession) -> DropPlan? {
        self.plan(of: session, into: plan.key, onto: plan.target, plan.zone, keeping: plan.anchor)
    }

    /// Whether `plan` leaves every window where it is, as dropping a window back beside the one it was beside does. A
    /// strip a click holds still counts as scrolled to the window the click focused: the drop focuses it too, and so
    /// scrolls to it as the click will.
    private func leavesAsIs(_ plan: DropPlan) -> Bool {
        plan.moving.isEmpty && plan.trees.allSatisfy { key, tree in
            workspaces[key].map { (real: Workspace) -> Bool in
                var asIs = real
                asIs.revealFocus()
                return prepared(asIs).layout().frames == tree.layout().frames
            } ?? false
        }
    }

    /// The tree as a pass lays it out: around the minimum sizes its windows have shown, and the widths a strip's came out at.
    private func prepared(_ tree: Workspace) -> Workspace {
        var tree = tree
        tree.minimumSizes = minimumSizes(in: tree)
        tree.observedWidths = observedWidths(in: tree)
        return tree
    }

    /// Where a window asked for `tile` comes to rest: grown from its top-left to the smallest size it has shown it keeps,
    /// where the layout could not make that room.
    private func restingFrame(of id: WindowID, at tile: CGRect) -> CGRect {
        guard let minimum = applier.minimumSize(of: id, app: model.windows[id]?.bundleID) else { return tile }
        return CGRect(origin: tile.origin, size: CGSize(width: max(tile.width, minimum.width), height: max(tile.height, minimum.height)))
    }

    /// Raises a held window each time macOS moves it to another Space, which it does as the window goes over another
    /// display, leaving it behind that display's windows.
    private func raiseOnNewSpace(_ session: inout DragSession) {
        let id = session.id, space = dinky_window_space_id(id)
        guard space != 0, space != session.space else { return }
        defer { session.space = space }
        guard session.space != nil, let pid = model.windows[id]?.pid else { return }
        print("\(stamp()) drag: \(id) moved to Space \(space) by macOS, raised")
        DispatchQueue.global(qos: .userInteractive).async {
            if let element = axWindow(pid: pid, wid: id, timeout: 0.5) { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
        }
    }

    /// The Space shown on the display under `point`, and the display, if dinky tiles it.
    private func tiledSpace(at point: CGPoint) -> (key: UInt64, display: Display)? {
        guard let display = displays.displays.first(where: { $0.frame.contains(point) }) else { return nil }
        let key = display.currentSpaceID, settings = settings(for: key)
        guard display.userSpaces.contains(key), settings.tiling, !settings.isFree else { return nil }
        return (key, display)
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

    /// When the left button last went down, in `CACurrentMediaTime` seconds: what tells one press from the next.
    private var pressedAt: CFTimeInterval {
        CACurrentMediaTime() - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
    }
}
