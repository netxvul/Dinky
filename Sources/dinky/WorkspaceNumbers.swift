import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// Workspace numbers: which native Space each workspace is. Workspaces are numbered across displays and live
// where `[workspace-to-display]` puts them, else on the main display. `arrange()` makes the Spaces match: it
// runs `WorkspacePlan`'s steps (create a Space, move a Space's windows, remove an empty Space) until there are
// none left. It runs at launch, on config reload, and a moment after displays or Spaces come and go. Between
// runs a workspace stays on its Space by ID, wherever macOS moves that Space.
// A display that goes away has macOS pour the windows of its Spaces onto another display's first Space, which
// is workspace 1's. So the workspace of every window is noted while the displays are settled, and once the
// Spaces are arranged after a display change, windows found off their workspace go back to it. Main thread only.
final class WorkspaceNumbers {
    /// Workspace number to Space.
    private(set) var binding: [Int: UInt64] = [:]
    private var observers: [() -> Void] = []
    private var pending: DispatchWorkItem?
    private var arranging = false
    /// Spaces this removed, whose `spaceDestroyed` events are not news.
    private var removed: Set<UInt64> = []
    /// The workspace each window was on while the displays were settled. See `noteHomes()`.
    private var homes: [UInt32: Int] = [:]
    /// The last note of homes, kept only if the displays are still the same at the next one.
    private var pendingHomes: [UInt32: Int]?
    /// Each scrolling workspace's strip while the displays were settled, its order, widths and pins, to put back once a
    /// display change has poured its windows elsewhere and they return (`returnDisplaced`). Noted as `homes` is.
    private var strips: [Int: NotedStrip] = [:]
    private var pendingStrips: [Int: NotedStrip]?
    /// A strip as noted, with the Space it was on and that Space's display.
    private struct NotedStrip {
        let tree: Workspace
        let space: UInt64
        let display: String?
    }
    /// The displays that came or went since the displays were last settled.
    private var changedDisplays: Set<String> = []
    /// Workspaces some of whose windows were seen off them while displaced: macOS may put them back before the Spaces
    /// are arranged, and the strip has lost its shape by then.
    private var awayWhileDisplaced: Set<Int> = []
    /// The displays as the last display change left them.
    private var knownDisplays: Set<String> = []
    /// Set by a display coming or going, until an arrangement completes and windows are back on their workspaces.
    private var displaced = false

    var count: Int { AppState.shared.config.workspaces }

    func space(of n: Int) -> UInt64? { binding[n] }
    func number(of space: UInt64) -> Int? { binding.first { $0.value == space }?.key }
    /// The workspaces on a display, in number order.
    func workspaces(on display: Display) -> [Int] { binding.filter { display.userSpaces.contains($0.value) }.keys.sorted() }
    /// The display's current workspace, nil on a Space that is none (full-screen, or a display without any).
    func current(on display: Display) -> Int? { number(of: display.currentSpaceID) }
    /// "3", or "" off the numbered workspaces, as hooks and logs print it.
    func label(of space: UInt64) -> String { number(of: space).map { "\($0)" } ?? "" }

    /// Calls `handler` whenever the numbering changes.
    func observe(_ handler: @escaping () -> Void) { observers.append(handler) }

    /// Starts following display and Space changes. Call once, after the first `arrange()`.
    func start() {
        let model = AppState.shared.displays
        knownDisplays = Set(model.displays.map(\.uuid))
        var main = model.displays.first(where: \.isMain)?.uuid
        // A display coming or going, or another becoming main, moves workspaces.
        model.observe { [weak self] model in
            guard let self else { return }
            let now = Set(model.displays.map(\.uuid))
            let nowMain = model.displays.first(where: \.isMain)?.uuid
            guard now != knownDisplays || nowMain != main else { return }
            let (connected, disconnected) = (now.subtracting(knownDisplays), knownDisplays.subtracting(now))
            (knownDisplays, main) = (now, nowMain)
            if !connected.isEmpty { print("displays: connected \(connected.sorted())") }
            if !disconnected.isEmpty { print("displays: disconnected \(disconnected.sorted())") }
            fflush(stdout)
            if !connected.isEmpty || !disconnected.isEmpty {
                displaced = true
                changedDisplays.formUnion(connected.union(disconnected))
            }
            arrangeSoon()
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.noteHomes() }
        // A Space removed in Mission Control leaves its workspace without one.
        EventHub.shared.subscribe { [weak self] event in
            guard let self, event.kind == .spaceDestroyed, !arranging, removed.remove(event.spaceID) == nil else { return }
            arrangeSoon()
        }
    }

    /// Arranges once things have been quiet for `delay` seconds: the Spaces of a display that just came or went
    /// take a moment to settle in WindowServer, and docking changes several displays in a row.
    func arrangeSoon(after delay: Double = 1) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.arrange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Runs the plan's steps until the Spaces match the config. Blocks the main thread while it works; each step
    /// waits for WindowServer to show its result, normally within a poll or two.
    func arrange() {
        guard !arranging else { return }
        // A swipe in flight would land on a Space this may remove.
        guard !SpaceSwitcher.shared.switching else { return arrangeSoon(after: 0.3) }
        arranging = true
        defer { arranging = false }
        let model = AppState.shared.displays
        let plan = WorkspacePlan(AppState.shared.config)
        let start = binding
        // The plan forgets a workspace whose Space is not listed. One that is only between displays, listed by
        // WindowServer while CoreGraphics already calls its display offline, gets a moment to reappear.
        func unlisted() -> Bool {
            model.reconcile()
            return !Set(binding.values).isSubset(of: model.displays.flatMap(\.userSpaces))
        }
        if unlisted() { _ = waitUntil(2) { !unlisted() } }
        var completed = false
        for _ in 0..<50 {
            model.reconcile()
            let displays = model.displays.map {
                PlanDisplay(uuid: $0.uuid, monitor: model.monitor($0), spaces: $0.userSpaces, current: $0.currentSpaceID)
            }
            guard !displays.isEmpty else { break }
            let occupied = occupiedSpaces(among: displays.flatMap(\.spaces))
            let before = binding
            let step = plan.step(displays, binding: binding, occupied: occupied)
            binding = step.binding
            guard let action = step.action else {
                completed = true
                break
            }
            guard perform(action) else {
                // A workspace whose windows did not all move stays where they are, so the next run moves it again.
                if case .move = action { binding = before }
                print("workspaces: stopped; the next display change or config reload tries again")
                break
            }
        }
        if displaced, completed {
            returnDisplaced()
            displaced = false
        }
        // Observers hear the result once, not every step on the way.
        if binding != start {
            print("workspaces: " + binding.keys.sorted().map { "\($0)=\(binding[$0]!)" }.joined(separator: " "))
            observers.forEach { $0() }
        }
        fflush(stdout)
        AppState.shared.coordinator?.reconcile()
    }

    /// The displays connected now, as WindowServer lists them. The display model hears of a change a moment
    /// after macOS has started moving windows for it.
    private var onlineDisplays: Set<String> {
        Set(dinky_displays().filter { $0.displayID != 0 && CGDisplayIsOnline($0.displayID) != 0 }.map(\.uuid))
    }

    /// Notes which workspace each window is on, once a second. A note is kept only when the displays are the
    /// same a second later, so windows macOS is pouring off a display that is going away are never noted there.
    private func noteHomes() {
        if displaced {
            // Which workspaces' windows macOS has poured off them, while it does.
            for (id, n) in homes where binding[n].map({ dinky_window_space_id(id) != $0 }) ?? false {
                awayWhileDisplaced.insert(n)
            }
        }
        guard !displaced, !arranging, onlineDisplays == knownDisplays, let coordinator = AppState.shared.coordinator else {
            pendingHomes = nil
            pendingStrips = nil
            return
        }
        if let pendingHomes { homes = pendingHomes }
        if let pendingStrips { strips = pendingStrips }
        var noted: [UInt32: Int] = [:]
        for window in coordinator.model.windows.values where window.isNormal && !window.isMinimized {
            if let n = number(of: dinky_window_space_id(window.id)) { noted[window.id] = n }
        }
        pendingHomes = noted
        let displays = AppState.shared.displays
        pendingStrips = binding.compactMapValues { space in
            coordinator.workspaces[space].flatMap { tree in
                tree.isScrolling && !tree.windows.isEmpty
                    ? NotedStrip(tree: tree, space: space, display: displays.display(containingSpace: space)?.uuid) : nil
            }
        }
    }

    /// Moves windows that a display change left off their workspace back onto it.
    private func returnDisplaced() {
        let model = AppState.shared.displays
        var targets: [UInt32: UInt64] = [:]
        for (id, n) in homes {
            let space = dinky_window_space_id(id)
            // A window on a full-screen Space, or gone, stays put.
            guard let target = binding[n], space != target,
                  model.display(containingSpace: space)?.userSpaces.contains(space) == true else { continue }
            targets[id] = target
        }
        let changed = changedDisplays, away = awayWhileDisplaced
        changedDisplays = []
        awayWhileDisplaced = []
        var restored: Set<UInt64> = []
        // A strip none of whose windows has to move back goes back as it was too, where the display change left it on a
        // new Space, or macOS put its windows back as new columns: only on a display the change touched.
        if let coordinator = AppState.shared.coordinator {
            for (n, noted) in strips {
                guard let space = binding[n], !targets.values.contains(space), let tree = coordinator.workspaces[space],
                      tree.needsRestore(to: noted.tree, displayChanged: noted.display.map(changed.contains) ?? false,
                                        spaceChanged: space != noted.space, windowsAway: away.contains(n)) else { continue }
                coordinator.restoreStrip(noted.tree, on: space, returning: [])
                restored.insert(space)
            }
        }
        guard !targets.isEmpty else {
            for space in restored { AppState.shared.coordinator?.placeAtOnce(space) }
            return
        }
        for (target, moving) in Dictionary(grouping: targets.keys, by: { targets[$0]! }) {
            // A strip goes back as it was before its windows move, so they arrive in it.
            if let n = number(of: target), let strip = strips[n] {
                AppState.shared.coordinator?.restoreStrip(strip.tree, on: target, returning: moving)
                restored.insert(target)
            }
            var ids = moving
            _ = dinky_move_windows_to_space(&ids, Int32(ids.count), target)
        }
        let arrived = { targets.filter { dinky_window_space_id($0.key) == $0.value }.count }
        _ = waitUntil(1) { arrived() == targets.count }
        // Strips put back are placed at once now their windows are home, the snap not spent while they were away.
        for target in restored { AppState.shared.coordinator?.placeAtOnce(target) }
        print("workspaces: returned \(arrived()) of \(targets.count) windows a display change moved off their workspace")
    }

    /// The Spaces among `spaces` with windows dinky would tile or restore there: helper windows some apps keep
    /// on every Space don't count. Without a window model to ask, any window counts.
    private func occupiedSpaces(among spaces: [UInt64]) -> Set<UInt64> {
        guard let model = AppState.shared.coordinator?.model, !model.windows.isEmpty else {
            return Set(spaces.filter { !dinky_space_window_ids($0, true).isEmpty })
        }
        let occupied = model.windows.values.filter { $0.isNormal || $0.isMinimized }.map { dinky_window_space_id($0.id) }
        return Set(occupied).intersection(spaces)
    }

    /// Whether a Space has windows dinky would tile or restore there.
    private func occupied(_ space: UInt64) -> Bool { !occupiedSpaces(among: [space]).isEmpty }

    private func perform(_ action: PlanAction) -> Bool {
        let model = AppState.shared.displays
        switch action {
        case .create(let uuid):
            let name = model.displays.first { $0.uuid == uuid }.map(displayName) ?? uuid
            let space = dinky_create_space(uuid as CFString)
            guard space != 0, waitUntil(2, { model.reconcile(); return model.display(containingSpace: space) != nil }) else {
                print("workspaces: could not create a Space on \(name)")
                return false
            }
            print("workspaces: created Space \(space) on \(name)")
            return true

        case .move(let from, let to):
            // Every window goes, helper windows included; only the ones `occupied` counts must arrive.
            var ids = dinky_space_window_ids(from, true).map(\.uint32Value)
            AppState.shared.coordinator?.moveTree(from: from, to: to)
            if !ids.isEmpty, dinky_move_windows_to_space(&ids, Int32(ids.count), to) {
                _ = waitUntil(1) { !occupied(from) }
            }
            guard !occupied(from) else {
                AppState.shared.coordinator?.moveTree(from: to, to: from)
                print("workspaces: windows stayed on Space \(from) instead of moving to \(to)")
                return false
            }
            AppState.shared.coordinator?.fitMovedTree(to)
            print("workspaces: moved the windows of Space \(from) to \(to)")
            return true

        case .remove(let space):
            // Removing the Space a display shows drops it to its first Space; leave for a workspace first.
            if let display = model.displays.first(where: { $0.currentSpaceID == space }) {
                let previous = model.previousSpace(on: display).flatMap { display.userSpaces.contains($0) && number(of: $0) != nil ? $0 : nil }
                if let target = previous ?? workspaces(on: display).first.flatMap(space(of:)), target != space,
                   switchSpace(toSpaceID: target, on: display) {
                    _ = waitUntil(1.5) { dinky_current_space_id(display.uuid as CFString) == target }
                }
            }
            guard dinky_destroy_space(space),
                  waitUntil(2, { model.reconcile(); return model.display(containingSpace: space) == nil }) else {
                print("workspaces: could not remove Space \(space)")
                return false
            }
            removed.insert(space)
            print("workspaces: removed Space \(space)")
            return true
        }
    }

    private func displayName(_ display: Display) -> String {
        display.name.isEmpty ? "display \(display.id)" : display.name
    }
}
