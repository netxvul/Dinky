import AppKit
import DinkyCommands
import DinkyConfig
import DinkyLayout
import DinkyPrivate

/// What a command answers: a short line for the CLI, whether it worked, and whether it did nothing, which a binding
/// shows by making the focused window's edge glow.
struct Reply {
    var ok: Bool
    var text: String
    var noop = false

    static func ok(_ text: String) -> Reply { Reply(ok: true, text: text) }
    static func error(_ text: String) -> Reply { Reply(ok: false, text: text) }
    /// A command with nothing to do: `ok` keeps the CLI's exit status what it was before replies said so.
    static func nothing(_ text: String, ok: Bool) -> Reply { Reply(ok: ok, text: text, noop: true) }
}

// Runs commands from bindings, the CLI and the menu against what exists today. Main thread only.
// Workspaces are numbered across displays; `prev` and `next` step through the focused display's.
enum Dispatcher {
    /// `env` is added to the environment of an `exec-and-forget`, for hooks.
    static func run(_ line: String, env: [String: String] = [:]) -> Reply {
        do {
            return run(try Command.parse(line), env: env)
        } catch {
            return .error(error.description)
        }
    }

    /// Runs a command. `window` stands in for the focused window in commands that act on one, for
    /// window rules; bindings and the CLI leave it nil.
    static func run(_ command: Command, window: WindowID? = nil, env: [String: String] = [:]) -> Reply {
        switch command {
        case .workspace(let target):
            return switchWorkspace(target)
        case .workspaceBackAndForth:
            let model = AppState.shared.displays
            guard let display = model.focusedDisplay(), let previous = model.previousSpace(on: display),
                  let n = AppState.shared.numbers.number(of: previous) else {
                return .nothing("no previous workspace", ok: false)
            }
            return switchWorkspace(.number(n))
        case .moveWindowToWorkspace(let target, let follow):
            return moveWindowToWorkspace(target, follow: follow, window: window ?? focusedWindowID())
        case .moveWindowToDisplay(let target, let follow):
            return moveWindowToDisplay(target, follow: follow, window: window ?? focusedWindowID())
        case .focus(let direction, let boundaries, let action):
            return focus(direction, boundaries: boundaries, action: action)
        case .focusMonitor(let target):
            return focusMonitor(target)
        case .focusMonitorNumber(let n):
            return focusMonitor(number: n)
        case .layout(let names):
            return layout(names, window: window)
        case .move(let direction, let points, let floatingOnly):
            let name = "move \(direction)" + (points.map { " \($0)" } ?? "")
            // A floating window already against the edge stays where it is.
            var still = false
            if let reply = floating(name, window: window, { coordinator, id in
                let step = CGFloat(points ?? coordinator.config.floating.moveStep)
                return coordinator.floating(id) { frame, area in
                    let moved = FloatingFrame.moved(frame, direction, by: step, within: area)
                    still = moved == frame
                    return moved
                }
            }) { return still && reply.ok ? .nothing("\(name): nothing to do", ok: true) : reply }
            if floatingOnly { return .nothing("\(name): the focused window does not float", ok: true) }
            return tree(name) { $0.move(direction) }
        case .joinWith(let direction):
            if let reply = floating("join-with \(direction)", window: window, { coordinator, id in
                coordinator.isOnFreeWorkspace(id) ? freeRefusal : "the focused window floats; tile it first"
            }) { return .nothing(reply.text, ok: false) }
            return tree("join-with \(direction)") { $0.join(direction) }
        case .resize(let dimension, let delta, let floatingOnly):
            let axis: Orientation? = switch dimension {
            case .smart: nil
            case .width: .horizontal
            case .height: .vertical
            }
            let name = "resize \(dimension.rawValue) \(delta)"
            var still = false
            if let reply = floating(name, window: window, { coordinator, id in
                let anchor = ResizeAnchor(rawValue: coordinator.config.floating.resizeAnchor.rawValue) ?? .center
                return coordinator.floating(id) { frame, area in
                    let resized = FloatingFrame.resized(frame, by: CGFloat(delta), along: axis, within: area, anchor: anchor)
                    still = resized == frame
                    return resized
                }
            }) { return still && reply.ok ? .nothing("\(name): nothing to do", ok: true) : reply }
            if floatingOnly { return .nothing("\(name): the focused window does not float", ok: true) }
            return tree(name) { $0.resize(by: CGFloat(delta), along: axis) }
        case .fullscreen:
            if let reply = floating("fullscreen", window: window, { $0.toggleFloatingFullscreen($1) }) { return reply }
            // A window already filling its workspace, alone there, would not change.
            var fills = false
            let reply = tree("fullscreen") { workspace in
                fills = workspace.focusedFillsWorkspace
                if !fills { workspace.toggleFullscreen() }
                return true
            }
            return fills ? .nothing("fullscreen: the window already fills the workspace", ok: true) : reply
        case .grid(let placement, let toggle):
            guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
            let id = window ?? coordinator.commandFocusedWindow
            if toggle, coordinator.isFloating(id) == true {
                // A free workspace would float the window again at once, so the toggle goes back to its frame instead.
                if coordinator.isOnFreeWorkspace(id) {
                    if let error = coordinator.toggleGrid(id, on: placement) { return .error("grid: \(error)") }
                    return .ok("grid --toggle \(placement)")
                }
                coordinator.setFloating(id, false)
                return .ok("layout tiling")
            }
            if let error = coordinator.place(id, on: placement) { return .error("grid: \(error)") }
            return .ok("grid \(placement)")
        case .cycleSize(let percents):
            let shares = percents.map { Double($0) / 100 }
            let name = "cycle-size " + percents.map { "\($0)%" }.joined(separator: " ")
            if let reply = floating(name, window: window, { coordinator, id in
                coordinator.floating(id) { frame, area in
                    FloatingFrame.centered(SizeCycle.next(after: Double(frame.width / area.width), in: shares), in: area)
                }
            }) { return reply }
            // A rule's window, which need not have focus yet: its own tree, with it focused there.
            if let window, let coordinator = AppState.shared.coordinator, let key = coordinator.placements[window]?.space {
                let changed = coordinator.command(onSpace: key) { workspace -> Bool in
                    guard workspace.contains(window) else { return false }
                    if workspace.focused != window { workspace.focus(window) }
                    return workspace.cycleWidth(through: shares)
                }
                return changed == true ? .ok(name) : .nothing("\(name): nothing to do", ok: false)
            }
            return tree(name) { $0.cycleWidth(through: shares) }
        case .pin(let side, let toggle):
            // A rule pins only a side no other column holds.
            return pin("pin \(side.rawValue)" + (toggle ? " --toggle" : ""), window: window) {
                $0.pin(side, toggle: toggle, freeSideOnly: window != nil, window: window)
            }
        case .focusPin(let side):
            guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
            guard let id = coordinator.command({ $0.focusPin(side) }) ?? nil else {
                return .nothing("focus-pin \(side.rawValue): nothing is pinned \(side.rawValue)", ok: false)
            }
            return focus(window: id)
        case .unpin(let side):
            return pin("unpin" + (side.map { " \($0.rawValue)" } ?? ""), window: window, unpinning: command) {
                $0.unpin(side, window: window)
            }
        case .flattenWorkspaceTree:
            return tree("flatten-workspace-tree", wholeSpace: true) { $0.flatten(); return true }
        case .balanceSizes:
            return tree("balance-sizes", wholeSpace: true) { $0.balanceSizes(); return true }
        case .rotate(let rotation):
            return rearrange("rotate \(rotation.rawValue)") { $0.rotate(rotation) }
        case .mirror(let axis):
            return rearrange("mirror \(axis.rawValue)") { $0.mirror(axis) }
        case .retile:
            guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
            coordinator.reconcile()
            return .ok("retiled")
        case .windowSwitcher:
            guard AppState.shared.coordinator != nil else { return .error("tiling is not running") }
            guard AppState.shared.config.windowSwitcher.enabled else { return .error("the window switcher is off: enabled = false") }
            return WindowSwitcher.shared.showFromKeyboard() ? .ok("window-switcher")
                : .nothing("the workspace under the pointer has too few windows, as [window-switcher] show-single says, or a layout its layouts leave out", ok: false)
        case .workspaceSwitcher:
            guard AppState.shared.coordinator != nil else { return .error("tiling is not running") }
            guard AppState.shared.config.workspaceSwitcher.enabled else { return .error("the workspace switcher is off: enabled = false") }
            return WorkspaceSwitcher.shared.showFromKeyboard() ? .ok("workspace-switcher")
                : .nothing("fewer than two workspaces to pick from", ok: false)
        case .clearMinimumSizes:
            guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
            coordinator.clearMinimumSizes()
            return .ok("cleared minimum sizes")
        case .mode(let name):
            guard AppState.shared.config.modes[name] != nil else { return .error("no mode '\(name)' in the config") }
            AppState.shared.hotkeys.setMode(name)
            return .ok("mode \(name)")
        case .reloadConfig:
            if let error = AppState.shared.loadConfig() { return .error("config: \(error)") }
            return .ok("reloaded \(Config.userConfigURL.path)")
        case .enable(let toggle):
            let on = toggle == .toggle ? !AppState.shared.enabled : toggle == .on
            AppState.shared.setEnabled(on)
            return .ok(on ? "enabled" : "disabled")
        case .listWindows(let query):
            return listWindows(query)
        case .listWorkspaces(let query):
            return .ok(listWorkspaces(query))
        case .listMonitors(let query):
            return .ok(listMonitors(query))
        case .listModes(let current):
            let state = AppState.shared
            if current { return .ok(state.hotkeys.currentMode) }
            let names = state.config.modes.keys.sorted()
            return .ok((names.filter { $0 == "main" } + names.filter { $0 != "main" }).joined(separator: "\n"))
        case .debugState:
            guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
            return .ok(coordinator.debugState())
        case .execAndForget(let shell):
            exec(["/bin/sh", "-c", shell], env: env)
            return .ok("")
        }
    }

    // MARK: Workspaces

    private struct Refusal: Error {
        let reply: Reply
        /// `noop` for a target that is simply not there from here, as at the last workspace.
        init(_ text: String, noop: Bool = false) { reply = noop ? .nothing(text, ok: false) : .error(text) }
    }

    /// The workspace a target names. `prev` and `next` step through the focused display's workspaces in number
    /// order, without wrapping, from the one it shows or is switching to, so rapid requests add up. `recent` is the
    /// workspace focused before the current one, on any display.
    private static func resolve(_ target: WorkspaceTarget) throws(Refusal) -> Int {
        let model = AppState.shared.displays
        let numbers = AppState.shared.numbers
        model.reconcile()
        switch target {
        case .number(let n):
            guard (1...numbers.count).contains(n) else { throw Refusal("no workspace \(n), there are \(numbers.count)", noop: true) }
            return n
        case .recent:
            guard let n = model.recentSpace.flatMap(numbers.number(of:)) else { throw Refusal("no recent workspace", noop: true) }
            return n
        case .prev, .next:
            guard let display = model.focusedDisplay(), let current = numbers.number(of: targetSpaceID(on: display)) else {
                throw Refusal("not on a numbered workspace")
            }
            let here = numbers.workspaces(on: display)
            guard let at = here.firstIndex(of: current) else { throw Refusal("not on a numbered workspace") }
            let i = at + (target == .next ? 1 : -1)
            guard here.indices.contains(i) else { throw Refusal("no \(target == .next ? "next" : "previous") workspace on this display", noop: true) }
            return here[i]
        }
    }

    private static func switchWorkspace(_ target: WorkspaceTarget) -> Reply {
        do {
            return show(try resolve(target))
        } catch {
            return error.reply
        }
    }

    /// Puts workspace `n` on screen on its display and gives that display focus. `landed` runs once it shows, in
    /// place of focusing the workspace's window.
    private static func show(_ n: Int, landed: (() -> Void)? = nil) -> Reply {
        let model = AppState.shared.displays
        guard let space = AppState.shared.numbers.space(of: n), let display = model.display(containingSpace: space) else {
            return .error("workspace \(n) has no Space; see `dinky doctor`")
        }
        // On screen and staying there; a switch still on its way is not, and takes `arrive` for when it lands.
        let showing = display.currentSpaceID == space && targetSpaceID(on: display) == space
        let elsewhere = model.focusedDisplay()?.uuid != display.uuid
        if showing, !elsewhere, landed == nil { return .ok("already on workspace \(n)") }
        // Arriving on a Space, macOS activates an app, which can be one whose window is on another Space when the
        // workspace has no window of the app that had focus. Focus moves to this Space.
        let arrive = landed ?? {
            model.reconcile()
            guard let shown = model.displays.first(where: { $0.uuid == display.uuid }) else { return }
            if !elsewhere, dinky_window_space_id(frontWindowID()) == shown.currentSpaceID { return }
            _ = focus(shown, window: AppState.shared.coordinator?.workspace(on: shown)?.focused)
        }
        if showing {
            arrive()
            return .ok("workspace \(n)")
        }
        guard switchSpace(toSpaceID: space, on: display, landed: arrive) else { return .error("switch to workspace \(n) failed") }
        return .ok("workspace \(n)")
    }

    /// Puts workspace `n` on screen as `workspace n` does, and focuses window `id` once it shows, for the workspace
    /// switcher's letter keys.
    static func showWorkspace(_ n: Int, focusing id: WindowID) -> Reply {
        show(n) { AppState.shared.coordinator?.focus(id) }
    }

    private static func moveWindowToWorkspace(_ target: WorkspaceTarget, follow: Bool, window wid: WindowID) -> Reply {
        let n: Int
        do {
            n = try resolve(target)
        } catch {
            return error.reply
        }
        guard let space = AppState.shared.numbers.space(of: n),
              let to = AppState.shared.displays.display(containingSpace: space) else {
            return .error("workspace \(n) has no Space; see `dinky doctor`")
        }
        if let reply = relocate(wid, to: space, on: to, destination: "workspace \(n)", follow: follow) { return reply }
        // macOS activates another app when the Space left behind loses the active app's window, so focus the
        // moved window once its workspace shows.
        if follow { _ = show(n) { AppState.shared.coordinator?.focus(wid) } }
        return .ok("moved window \(wid) to workspace \(n)")
    }

    // MARK: Layout tree

    /// Why a command that would tile a window of a `free` workspace does nothing: the workspace floats it again.
    private static let freeRefusal = "the window's workspace is free, so its windows float and none tiles"

    /// For a floating window (`window`, else the focused one), the reply of `run`, which does the command's
    /// floating version and answers nil once done or why not. Nil for any other window, which the tree handles.
    private static func floating(_ name: String, window: WindowID?,
                                 _ run: (Coordinator, WindowID) -> String?) -> Reply? {
        guard let coordinator = AppState.shared.coordinator else { return nil }
        let id = window ?? coordinator.commandFocusedWindow
        guard coordinator.isFloating(id) == true else { return nil }
        if let error = run(coordinator, id) { return .error("\(name): \(error)") }
        return .ok(name)
    }

    /// Runs a change on the focused window's tree; `change` returns false when there was nothing to do.
    /// `wholeSpace` commands act on the tree of the focused window's Space even when that window floats.
    private static func tree(_ name: String, wholeSpace: Bool = false, _ change: (inout Workspace) -> Bool) -> Reply {
        guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
        let id = coordinator.focusedWindow
        // A command can change the layout before finding nothing to do, as move ends fullscreen first: that is no noop.
        var moved = false
        // A pin a move or a join took apart was unpinned by hand: its rule leaves it so.
        var unpinned: Set<WindowID> = []
        func watched(_ workspace: inout Workspace) -> Bool {
            let before = workspace.layout(), pinned = Set(workspace.pinnedWindows)
            let done = change(&workspace)
            moved = !done && workspace.layout() != before
            unpinned = pinned.subtracting(workspace.pinnedWindows)
            return done
        }
        let result = wholeSpace && coordinator.isFloating(id) == true
            ? coordinator.spaceKey(of: id).flatMap { coordinator.command(onSpace: $0, watched) }
            : coordinator.command(watched)
        coordinator.unpinnedByHand.formUnion(unpinned)
        switch result {
        case nil: return .error("\(name): the focused window is not tiled")
        case false?: return moved ? .error("\(name): nothing to do") : .nothing("\(name): nothing to do", ok: false)
        case true?: return .ok(name)
        }
    }

    /// `pin` and `unpin` on the focused window's tree, or for a rule on its window's, which is not focused for it. Done
    /// already, it answers so; refused, it does nothing and says why, as a binding that does nothing.
    private static func pin(_ name: String, window: WindowID?, unpinning: Command? = nil,
                            _ pinning: @escaping (inout Workspace) -> PinChange) -> Reply {
        guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
        // With the minimum sizes the next pass lays out with, so the band's room is judged as it will show.
        let change = { (workspace: inout Workspace) -> PinChange in
            workspace.minimumSizes = coordinator.minimumSizes(in: workspace)
            return pinning(&workspace)
        }
        let id = window ?? coordinator.commandFocusedWindow
        let result: PinChange?
        if let window {
            // A rule's window is pinned in its own tree or not at all, and one the user unpinned is left so.
            guard let key = coordinator.placements[window]?.space else { return .nothing("\(name): the window is not tiled", ok: false) }
            if coordinator.unpinnedByHand.contains(window) { return .ok("\(name): unpinned by hand, left so") }
            result = coordinator.command(onSpace: key) { $0.contains(window) ? change(&$0) : .refused("the window is not tiled") }
        } else if coordinator.isFloating(id) == true {
            // A side named unpins on the floating window's workspace; anything else needs a tiled window.
            guard case .unpin(let side?)? = unpinning, let key = coordinator.spaceKey(of: id) else {
                return .nothing("\(name): the window floats", ok: false)
            }
            let before = coordinator.workspaces[key]?.pinnedWindows ?? []
            result = coordinator.command(onSpace: key) { $0.unpin(side) }
            coordinator.unpinnedByHand.formUnion(Set(before).subtracting(coordinator.workspaces[key]?.pinnedWindows ?? []))
        } else {
            let key = coordinator.placements[id]?.space
            let before = key.flatMap { coordinator.workspaces[$0]?.pinnedWindows } ?? []
            result = coordinator.command { change(&$0) }
            let after = key.flatMap { coordinator.workspaces[$0]?.pinnedWindows } ?? []
            coordinator.unpinnedByHand.formUnion(Set(before).subtracting(after))
            coordinator.unpinnedByHand.subtract(after)
        }
        switch result {
        case nil: return .error("\(name): the focused window is not tiled")
        case .changed?: return .ok(name)
        case .unchanged?: return .ok("\(name): already so")
        case .refused(let why)?: return .nothing("\(name): \(why)", ok: false)
        }
    }

    /// `rotate` and `mirror` on the focused workspace's tree, which fixed and scrolling layouts refuse.
    private static func rearrange(_ name: String, _ change: @escaping (inout Workspace) -> Bool) -> Reply {
        var refused = false
        let reply = tree(name, wholeSpace: true) { workspace in
            guard workspace.rearranges else {
                refused = true
                return false
            }
            return change(&workspace)
        }
        return refused ? .nothing("\(name): not supported in a fixed or scrolling layout", ok: false) : reply
    }

    /// Applies the layout after the last that describes the window now (see `LayoutName.next`): floating or tiling
    /// for the window, scrolling for its workspace, a mode, an orientation or both for its container, which takes a
    /// scrolling workspace back to its tree. Anything but floating tiles a floating window first.
    private static func layout(_ names: [LayoutName], window: WindowID?) -> Reply {
        guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
        let id = window ?? coordinator.commandFocusedWindow
        guard let floating = coordinator.isFloating(id) else { return .error("layout: no window dinky manages is focused") }
        var current: [LayoutName] = floating ? [.floating] : [.tiling]
        if !floating, coordinator.isScrolling(id) {
            current.append(.scrolling)
        } else if !floating, let container = coordinator.container(of: id), let axis = coordinator.containerAxis(of: id) {
            current += LayoutName.describing(container.mode, axis: axis, auto: container.orientation == .auto)
        }
        let name = LayoutName.next(in: names, current: current)
        // Its workspace would float the window again at once, leaving nothing changed.
        if name != .floating, coordinator.isOnFreeWorkspace(id) { return .nothing("layout \(name.rawValue): \(freeRefusal)", ok: false) }
        switch name {
        case .floating, .tiling:
            coordinator.setFloating(id, name == .floating)
        case .scrolling:
            if floating { coordinator.setFloating(id, false) }
            coordinator.setScrolling(true, for: id)
        default:
            if floating { coordinator.setFloating(id, false) }
            if coordinator.isScrolling(id) { coordinator.setScrolling(false, for: id) }
            coordinator.command(on: id) { $0.setLayout(name.mode, name.orientation) }
        }
        Hud.shared.layoutChanged(name.rawValue)
        return .ok("layout \(name.rawValue)")
    }

    // MARK: Windows

    /// Moves a window to the current Space of the next or previous display (wrapping around), or of the display
    /// focused before the focused one, into that Space's tree. A floating window keeps its offset from the
    /// display's corner. Untested with two displays.
    private static func moveWindowToDisplay(_ target: DisplayTarget, follow: Bool, window wid: WindowID) -> Reply {
        let model = AppState.shared.displays
        model.reconcile()
        guard wid != 0, let from = model.display(ofWindow: wid) else { return .error("no focused window") }
        let displays = model.displays
        guard displays.count > 1, let i = displays.firstIndex(of: from) else { return .nothing("no other display", ok: false) }
        let n: Int
        if target == .recent {
            guard let recent = model.recentDisplay, recent != from, let at = displays.firstIndex(of: recent) else {
                return .nothing("no recent display", ok: false)
            }
            n = at
        } else {
            n = (i + (target == .next ? 1 : -1) + displays.count) % displays.count
        }
        let to = displays[n]
        if let reply = relocate(wid, to: to.currentSpaceID, on: to, destination: "display \(n + 1)", follow: follow) {
            return reply
        }
        // The Space is on screen, so there is nothing to show first.
        if follow { AppState.shared.coordinator?.focus(wid) }
        return .ok("moved window \(wid) to display \(n + 1)")
    }

    /// Moves a new window to the current Space of `display`, without telling the coordinator, which is holding it
    /// out of the trees. Nil once moved, else the error.
    static func adopt(_ wid: WindowID, onto display: Display) -> Reply? {
        let from = AppState.shared.displays.display(ofWindow: wid)
        if let error = move(wid, to: display.currentSpaceID, arriving: "display \(display.id)") { return error }
        if let from { keepOffset(of: wid, from: from, to: display, space: display.currentSpaceID) }
        return nil
    }

    /// Moves a window to a Space on display `to` and tells the coordinator, which refocuses the Space left
    /// behind unless the caller follows the window. Nil once moved, else the reply to answer (an error, or ok
    /// when the window is already there).
    private static func relocate(_ wid: WindowID, to space: UInt64, on to: Display, destination: String,
                                 follow: Bool) -> Reply? {
        guard wid != 0 else { return .error("no focused window") }
        guard dinky_window_space_id(wid) != space else { return .nothing("window \(wid) is already on \(destination)", ok: true) }
        let from = AppState.shared.displays.display(ofWindow: wid)
        if let error = move(wid, to: space, arriving: destination) { return error }
        if let from { keepOffset(of: wid, from: from, to: to, space: space) }
        // A tiled window to another display joins the tree there placed at once: a glide would set out from where it was on
        // the other one.
        let coordinator = AppState.shared.coordinator
        let across = from.map { $0.uuid != to.uuid } ?? false
        let joins = across && coordinator?.isFloating(wid) == false && coordinator?.settings(for: space).isFree == false
        if joins { coordinator?.placeAtOnce(space) }
        coordinator?.windowMoved(wid, refocus: !follow)
        if joins { coordinator?.joined(wid, space) }
        return nil
    }

    /// A floating window moved to another display keeps its offset from the display's corner, as does one going to
    /// `space` on a free workspace, which floats it there; the tree places a tiled one.
    private static func keepOffset(of wid: WindowID, from: Display, to: Display, space: UInt64) {
        let coordinator = AppState.shared.coordinator
        guard from.uuid != to.uuid, coordinator?.isFloating(wid) != false || coordinator?.settings(for: space).isFree == true,
              let pid = windowPID(wid), let element = axWindow(pid: pid, wid: wid) else { return }
        let frame = dinky_window_info(wid).frame
        var origin = CGPoint(x: to.frame.minX + max(0, frame.minX - from.frame.minX),
                             y: to.frame.minY + max(0, frame.minY - from.frame.minY))
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    }

    /// Moves a window to a Space and waits for it to arrive: the bridged move is asynchronous, and callers
    /// act on the window's new place. Nil on success, else the error to answer.
    private static func move(_ wid: WindowID, to space: UInt64, arriving destination: String) -> Reply? {
        var ids = [wid]
        guard dinky_move_windows_to_space(&ids, 1, space) else { return .error("move failed") }
        guard waitUntil(0.5, { dinky_window_space_id(wid) == space }) else {
            return .error("window \(wid) did not arrive on \(destination)")
        }
        return nil
    }
}

