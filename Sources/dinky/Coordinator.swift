import AppKit
import DinkyCommands
import DinkyConfig
import DinkyLayout
import DinkyPrivate

/// What the coordinator knows about a window it has classified. `space` is nil off the user Spaces
/// (on a native full-screen Space), where nothing is tiled.
struct Placement {
    let floating: Bool
    var space: UInt64?
}

// The serialized owner of layout state: one Workspace per Space, keyed by Space ID, fed by the window and
// display models, applied through the frame applier. Every change marks the trees it touched dirty; `flush` applies the
// dirty trees that are on screen. Main thread only.
final class Coordinator {
    let model = WindowModel()
    var enabled = true {
        didSet {
            if !enabled { applier.cancel(); animator.cancel(); pushes = [:]; stagingWindows = [:] }
            if enabled, !oldValue { reconcile() }
        }
    }

    let displays: DisplayModel
    private(set) var config: Config
    let applier = FrameApplier()
    private lazy var animator = Animator(applier: applier)
    private var borders: BorderManager?
    func isBorderWindow(_ id: WindowID) -> Bool { borders?.isBorder(id) ?? false }
    private(set) var workspaces: [UInt64: Workspace] = [:]
    var placements: [WindowID: Placement] = [:]
    var dirty: Set<UInt64> = []
    /// Classification attempts for windows whose AX element has not appeared yet.
    var attempts: [WindowID: Int] = [:]
    /// Windows floated because their AX element could not be reached, so dinky could not have moved them into a
    /// tile, with when it last looked again. See `retryUnreachable(_:)`.
    var unreachable: [WindowID: CFTimeInterval] = [:]
    /// By tiled window, how many passes in a row could not read it back.
    private var unread: [WindowID: Int] = [:]
    /// Newly shown windows at the exact frame of a tile of their app, held out of the trees for a moment in case
    /// they are a tab switch: by newcomer, the tile's window. See Tabs.swift.
    var heldTabs: [WindowID: WindowID] = [:]
    /// Newcomers held once and not confirmed as tabs. They are tiled like any window from then on.
    var notTabs: Set<WindowID> = []
    /// New windows not yet classified, and the display that had focus when they first showed. See Adoption.swift.
    var adoptTargets: [WindowID: String] = [:]
    /// New windows on their way to the focused display, kept out of the trees until they arrive.
    var adopting: Set<WindowID> = []
    /// The tiled window being dragged with the mouse, until the button is released. See Drag.swift.
    var dragging: WindowID?
    /// What the drag's feedback last showed, for the log.
    var shownDrop: String?
    lazy var placeholders = DragPlaceholders()
    /// Called when the focused window changes.
    var onFocusChange: (() -> Void)?
    private(set) var lastFocused: WindowID = 0
    /// The focused display just before `lastFocused` took focus.
    private(set) var displayBeforeFocus: String?
    /// A window dinky just focused, and until when focus reads that disagree are taken as stale.
    private var focusing: (id: WindowID, until: Date)?
    /// Trees to place without gliding the next time they are applied: after displays come or go, apps have
    /// moved the windows of Spaces that were not on screen to frames of their own, and a glide from there
    /// would only show the mess.
    private var snap: Set<UInt64> = []
    /// By scrolling tree, its strip frames as last applied, unparked and parked, so the next glide starts each window
    /// where the strip had it rather than where it was parked; and its windows shown fullscreen over the strip then.
    private var lastStrips: [UInt64: (strip: [WindowID: CGRect], placed: [WindowID: CGRect], fullscreen: Set<WindowID>)] = [:]
    /// By tree, its fullscreen windows as last applied, over the tree or pushing a strip: a window that stopped being
    /// fullscreen counts until it has left its fullscreen size. See `ResizeOnce`.
    private var lastFullscreen: [UInt64: Set<WindowID>] = [:]
    /// The width each window was last written at and the width it came out at, which an app that snaps its size
    /// leaves a little narrower. See `observedWidths(in:)`.
    private var landedWidths: [WindowID: (asked: CGFloat, got: CGFloat)] = [:]
    /// By scrolling tree, a glide of snapshots under way or being made ready, and the layout it is gliding to. See
    /// GlideStage.
    private var glides: [UInt64: (token: Int, stage: GlideStage?, layout: Layout)] = [:]
    private var glideTokens = 0
    /// By scrolling tree, a glide driven by the Dock scripting addition: the windows it holds transformed and the
    /// layout it is gliding to, so a superseding pass clears those transforms. See ScriptingAddition.
    private var saGlides: [UInt64: (token: Int, ids: [WindowID], layout: Layout)] = [:]
    private var saGlideTokens = 0
    /// By tree, or by a floating window's animator key, windows going fullscreen being written their whole sizes
    /// before they glide, and the layout they glide to then. See `ResizeOnce`.
    private var pushes: [UInt64: (token: Int, layout: Layout)] = [:]
    private var pushTokens = 0
    /// The windows being written their whole sizes before they glide, by the token of the staging that has them: as
    /// good as gliding, for whatever asks.
    private var stagingWindows: [WindowID: Int] = [:]
    /// Where dinky last sent each floating window, so a command pressed again mid-glide starts from where the
    /// window is going rather than where it is.
    private(set) var floatingTargets: [WindowID: CGRect] = [:]
    /// Floating windows filling their display with `fullscreen`, and the frame each had before. In memory only.
    var filledFrom: [WindowID: CGRect] = [:]
    /// Windows of `float = true` workspaces that `grid --toggle` placed, and the frame each had before. In memory only.
    var griddedFrom: [WindowID: CGRect] = [:]

    init(displays: DisplayModel, config: Config) {
        self.displays = displays
        self.config = config
    }

    func start() {
        model.observe { [weak self] event in self?.handle(event) }
        animator.onArrive = { [weak self] ids in self?.borders?.arrived(ids) }
        var known = Set(displays.displays.map(\.uuid))
        displays.observe { [weak self] displays in
            guard let self else { return }
            let now = Set(displays.displays.map(\.uuid))
            if now != known { snap.formUnion(workspaces.keys) }
            known = now
            reconcile()
        }
        // A hidden app's windows can read as shown when their hide event arrives; re-read them once it is hidden.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reconcile() }
        }
        guard model.start() else {
            fputs("coordinator: no WindowServer events\n", stderr)
            return
        }
        update(config: config)
        reconcile()
    }

    func update(config: Config) {
        self.config = config
        ScriptingAddition.enabled = config.scrolling.glide == .scriptingAddition
        animator.configure(durationMs: config.animations.durationMs,
                           easing: Easing(rawValue: config.animations.curve.rawValue))
        if config.borders.enabled {
            borders = borders ?? BorderManager(config: config.borders, model: model,
                                               isAnimating: { [unowned self] id in animator.isAnimating(id) })
            borders?.update(config: config.borders)
        } else {
            borders = nil
        }
        configureWorkspaces()
        // A workspace switched to/from floating must release/acquire its existing windows too.
        for window in model.windows.values { track(window) }
        fitToDisplays()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    // MARK: Events

    private func handle(_ event: WindowEvent) {
        // Detected here, not in the border manager, so hover focus stands down even with borders off.
        if MissionControl.shared.update(from: model) { borders?.missionControlChanged() }
        borders?.handle(event)
        if let window = event.window {
            event.change == .removed ? forget(window.id) : track(window)
            if [.windowMove, .windowResize].contains(event.kind) { noteFrameChange(of: window.id) }
        }
        if [.frontApp, .windowReorder, .windowCreate].contains(event.kind) { syncFocus() }
        if [.frontApp, .windowReorder].contains(event.kind) {
            // The front window settles a few ms after the event, as the border manager also knows: Cmd-` or a click
            // between one app's windows can report the previous window still in front.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                self?.syncFocus()
                self?.flush()
            }
        }
        flush()
    }

    /// Re-reads every window and display, moves windows to the trees of the Spaces they are on now
    /// (so a window dragged to another Space stays there), and re-applies every tree on screen. The model
    /// publishes every window it re-reads, so `handle` tracks and forgets them. Empty trees of Spaces that
    /// no longer exist are dropped.
    func reconcile() {
        configureWorkspaces()
        model.reconcile()
        fitToDisplays()
        workspaces = workspaces.filter { displays.display(containingSpace: $0.key) != nil || !$0.value.windows.isEmpty }
        syncFocus()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    /// Forgets every minimum size learned and re-applies every tree, so windows are asked for their tiles again.
    func clearMinimumSizes() {
        applier.forgetMinimums()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    /// Bounds and gaps of every tree from the display its Space is on now, which can have moved, resized or become
    /// main, or be another display, as when macOS moves a disconnected display's Spaces. A tree whose Space is on
    /// no display is left as it is.
    private func fitToDisplays() {
        for key in workspaces.keys {
            guard let display = displays.display(containingSpace: key) else { continue }
            workspaces[key]!.bounds = display.visibleArea
            workspaces[key]!.gaps = gaps(on: display)
            workspaces[key]!.walls = walls(of: display)
        }
    }

    /// The sides of a display with another display right against them, which a scrolled-out window must not
    /// hang over.
    private func walls(of display: Display) -> Set<Direction> {
        let frame = display.frame
        var walls: Set<Direction> = []
        for other in displays.displays where other.uuid != display.uuid
            && min(other.frame.maxY, frame.maxY) > max(other.frame.minY, frame.minY) {
            if abs(other.frame.maxX - frame.minX) < 1 { walls.insert(.left) }
            if abs(other.frame.minX - frame.maxX) < 1 { walls.insert(.right) }
        }
        return walls
    }

    /// Carries a Space's tree to another Space, before its windows are moved there, so they arrive in the layout
    /// they had. Kept when the other Space already has a tree with windows.
    func moveTree(from: UInt64, to: UInt64) {
        guard from != to, let display = displays.display(containingSpace: to), workspaces[to]?.windows.isEmpty != false,
              var tree = workspaces.removeValue(forKey: from) else { return }
        tree.bounds = display.visibleArea
        tree.gaps = gaps(on: display)
        tree.walls = walls(of: display)
        workspaces[to] = tree
        for (id, placement) in placements where placement.space == from { placements[id]!.space = to }
    }

    /// Resolve layout settings by a Space's current numbered position, which can change when Spaces are reordered.
    private func configureWorkspaces() {
        for key in workspaces.keys {
            workspaces[key]!.accordionPadding = CGFloat(config.accordion.padding)
            workspaces[key]!.autoOrientAccordions = config.accordion.orientation == .auto
            workspaces[key]!.columnWidth = config.scrolling.columnWidth
            workspaces[key]!.fullscreenFocus = fullscreenFocus
            workspaces[key]!.fullscreenFollowsLater = config.fullscreen.followDelayMs > 0
            workspaces[key]!.fullscreenPushesStrip = config.fullscreen.scrolling == .push
            workspaces[key]!.setAlgorithm(workspaces[key]!.chosenAlgorithm ?? algorithm(settings(for: key)))
        }
    }

    func gaps(on display: Display) -> DinkyLayout.Gaps {
        DinkyLayout.Gaps(config.gaps(for: displays.monitor(display)))
    }

    /// The settings of the Space's workspace, by its current number.
    func settings(for space: UInt64) -> WorkspaceSettings {
        config.settings(forWorkspace: AppState.shared.numbers.number(of: space))
    }

    func algorithm(_ settings: WorkspaceSettings) -> TilingAlgorithm {
        let expand: FixedExpansion = switch settings.expand {
        case .rows: .rows
        case .columns: .columns
        case .accordion: .accordion
        }
        return switch settings.layout {
        case .tiles, .dwindle: .dwindle(.tiles)
        case .accordion: .dwindle(.accordion)
        case .fixed: .fixed(rows: settings.rows, columns: settings.columns, expand: expand)
        case .scrolling: .scrolling
        }
    }

    /// Classifies a window the first time it is on screen, then keeps it in the tree of its current Space
    /// while it is shown: minimized windows, windows of hidden apps and inactive tabs read as minimized.
    func track(_ window: Window) {
        retryUnreachable(window)
        if placements[window.id] == nil {
            // AX only lists windows on a Space that is on screen; the rest are classified when theirs is.
            guard window.isNormal, isVisible(window.spaceID) else { return }
            // Once, on the first classification attempt, not again on its retries.
            if attempts[window.id] == nil { noteFirstShowing(window) }
            guard let classification = classify(window) else { return }
            placements[window.id] = Placement(floating: classification.floating, space: nil)
            if !classification.runsRules, adopt(window) { return }
        }
        if !placements[window.id]!.floating, settings(for: window.spaceID).float { float(window.id) }
        guard !adopting.contains(window.id), !placements[window.id]!.floating else { return }
        let old = placements[window.id]!.space
        if let old, window.isMinimized || !window.isOrderedIn, takeOverTile(of: window.id, in: old) {
            placements[window.id]!.space = nil
            return
        }
        let new = window.isMinimized ? nil : key(of: window)
        guard old != new, heldTabs[window.id] == nil else { return }
        if let old { edit(old) { $0.remove(window.id) } }
        // A window coming from another Space's tree is moving, not switching tabs: tabs share a Space.
        if let new, old == nil, holdAsTab(window, in: new) { return }
        if let new { edit(new) { $0.insert(window.id) } }
        placements[window.id]!.space = new
    }

    /// Floats tiled windows that two passes in a row could not read back: their AX element is gone (an app that
    /// stopped answering Accessibility), so they would hold a tile they never move into. They are looked at again
    /// when they take focus.
    private func noteUnread(_ results: [FrameResult]) {
        for result in results {
            let id = result.job.id
            guard result.got == nil, placements[id]?.floating == false, model.windows[id] != nil else { unread[id] = nil; continue }
            unread[id, default: 0] += 1
            guard unread[id]! >= 2 else { continue }
            unread[id] = nil
            NSLog("dinky: window %u cannot be read through Accessibility; floating it until it can", id)
            float(id)
            unreachable[id] = CACurrentMediaTime()
        }
    }

    /// Looks again at a window floated because its AX element could not be reached, at most every few seconds, and
    /// classifies it afresh once it can be, so it tiles as any window would.
    func retryUnreachable(_ window: Window) {
        guard let since = unreachable[window.id], CACurrentMediaTime() - since > 3 else { return }
        unreachable[window.id] = CACurrentMediaTime()
        guard axWindow(pid: window.pid, wid: window.id, timeout: 0.25) != nil else { return }
        unreachable[window.id] = nil
        attempts[window.id] = nil
        placements[window.id] = nil
        track(window)
        flush()
    }

    /// Floats a window that reached a `float = true` workspace, out of the tree it was tiled in. It floats from then
    /// on, wherever it goes, as `layout floating` would leave it.
    private func float(_ id: WindowID) {
        if let space = placements[id]?.space { edit(space) { $0.remove(id) } }
        heldTabs[id] = nil
        placements[id] = Placement(floating: true, space: nil)
    }

    private func forget(_ id: WindowID) {
        stagingWindows[id] = nil
        pushes[Self.floatingKey(id)] = nil
        attempts[id] = nil
        adoptTargets[id] = nil
        adopting.remove(id)
        applier.forget(id)
        animator.forget(id)
        landedWidths[id] = nil
        unreachable[id] = nil
        unread[id] = nil
        heldTabs[id] = nil
        notTabs.remove(id)
        floatingTargets[id] = nil
        filledFrom[id] = nil
        griddedFrom[id] = nil
        guard let placement = placements.removeValue(forKey: id), let space = placement.space,
              !takeOverTile(of: id, in: space) else { return }
        edit(space) { $0.remove(id) }
    }

    /// The front app's frontmost document window on a current Space.
    var focusedWindow: WindowID { dinky_border_focused_window() }

    /// Focuses a window, raising it and activating its app. For a moment after, focus events that still
    /// report the previous window are ignored, so they do not pull the trees back to it.
    func focus(_ id: WindowID) {
        guard let window = model.windows[id] else { return }
        focusing = (id, Date() + 0.5)
        focusWindow(pid: window.pid, id: id)
    }

    /// Follows focus into the trees, so new windows land beside the focused one and accordions show it.
    private func syncFocus() {
        let id = focusedWindow
        if id != lastFocused {
            // Before the override goes: a new window can take focus before it shows. See Adoption.swift.
            displayBeforeFocus = displays.focusedDisplay(window: lastFocused)?.uuid
            WindowSwitcher.shared.focusLeft(lastFocused)
            WorkspaceSwitcher.shared.focusLeft(lastFocused)
            lastFocused = id
            if let window = model.windows[id] { retryUnreachable(window) }
            // Only a window takes focus from a display focused without one, not an app with no window here.
            if id != 0 { displays.focusOverride = nil }
            displays.noteFocus()
            onFocusChange?()
        }
        if let focusing, focusing.id != id, Date() < focusing.until { return }
        focusing = nil
        guard let key = placements[id]?.space, workspaces[key]?.focused != id else { return }
        edit(key) { $0.focus(id) }
    }

    /// The tree of a user Space, numbered workspace or not, created on first use. Nil for full-screen Spaces.
    private func key(of window: Window) -> UInt64? {
        guard let display = displays.display(containingSpace: window.spaceID),
              display.userSpaces.contains(window.spaceID) else { return nil }
        let settings = settings(for: window.spaceID)
        guard settings.tiling else { return nil }
        let key = window.spaceID
        if workspaces[key] == nil {
            workspaces[key] = Workspace(bounds: display.visibleArea, gaps: gaps(on: display),
                                        accordionPadding: CGFloat(config.accordion.padding),
                                        autoOrientAccordions: config.accordion.orientation == .auto,
                                        algorithm: algorithm(settings))
            workspaces[key]!.columnWidth = config.scrolling.columnWidth
            workspaces[key]!.fullscreenFocus = fullscreenFocus
            workspaces[key]!.fullscreenFollowsLater = config.fullscreen.followDelayMs > 0
            workspaces[key]!.fullscreenPushesStrip = config.fullscreen.scrolling == .push
            workspaces[key]!.walls = walls(of: display)
        }
        return key
    }

    /// What focusing another window does to fullscreen, from `[fullscreen] focus-change`.
    private var fullscreenFocus: FullscreenFocus {
        FullscreenFocus(rawValue: config.fullscreen.focusChange.rawValue) ?? .exit
    }

    /// Runs `change` on a tree and marks it dirty if its layout changed. Returns what `change` returned.
    @discardableResult
    func edit<T>(_ key: UInt64, _ change: (inout Workspace) -> T) -> T? {
        guard var workspace = workspaces[key] else { return nil }
        let before = workspace.layout(), pending = workspace.pendingFullscreen
        let result = change(&workspace)
        workspaces[key] = workspace
        if workspace.layout() != before { dirty.insert(key) }
        if let waiting = workspace.pendingFullscreen, waiting != pending { promoteLater(waiting, in: key) }
        return result
    }

    /// With `[fullscreen] focus-change = 'follow'` and a delay: the window that took focus from a fullscreen one
    /// goes fullscreen once the delay is up, if it still has focus and is still waiting.
    private func promoteLater(_ id: WindowID, in key: UInt64) {
        let delay = Double(config.fullscreen.followDelayMs) / 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, edit(key, { $0.promotePendingFullscreen(id) }) == true else { return }
            flush()
        }
    }

    // MARK: Applying

    func flush() {
        let keys = dirty
        dirty = []
        guard enabled else { return }
        for key in keys where isVisible(key) { apply(key) }
    }

    /// Whether the Space is a display's current one.
    func isVisible(_ space: UInt64) -> Bool {
        displays.displays.contains { $0.currentSpaceID == space }
    }

    /// Writes the tree's frames around the minimum sizes windows have shown, then lets the applier raise
    /// overlapping windows (accordion, fullscreen) into the tree's stacking, with its focused window on top.
    /// Nothing is activated: the tree follows macOS's focus (`syncFocus`) and commands that choose a window
    /// focus it themselves, so a pass, which may have started before the latest focus change, must not.
    /// Minimum sizes found in a pass are laid out around all at once, when that moves anything.
    private func apply(_ key: UInt64) {
        guard var workspace = workspaces[key] else { return }
        workspace.minimumSizes = minimumSizes(in: workspace)
        workspace.observedWidths = observedWidths(in: workspace)
        workspaces[key] = workspace
        let layout = workspace.layout()
        // A glide of snapshots already heading for this layout carries on; one heading elsewhere gives way to this pass,
        // its windows on the places it wrote them to.
        if let glide = glides[key] {
            if glide.layout == layout { return }
            glides[key] = nil
            glide.stage?.remove(fading: false)
            animator.stop(key)
        }
        // A scripting-addition glide heading for this layout carries on; one heading elsewhere clears its transforms,
        // so the windows show at the real frames this pass is about to write.
        if let sa = saGlides[key] {
            if sa.layout == layout { return }
            saGlides[key] = nil
            ScriptingAddition.reset(sa.ids)
            animator.stop(key)
        }
        // Windows taking their whole fullscreen frames before the strip glides to this layout carry on; for another
        // layout, this pass takes them from wherever they have got to.
        if let push = pushes[key] {
            if push.layout == layout { return }
            pushes[key] = nil
        }
        let pids = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in model.windows[id].map { (id, $0.pid) } })
        // Windows shown fullscreen over the strip. A strip that pushes has none: its fullscreen windows are part of it.
        let fullscreen = workspace.pushesFullscreen ? [] : Set(workspace.fullscreenWindows)
        // Windows filling their widened columns, pushing their neighbours off.
        let pushed: Set<WindowID> = workspace.pushesFullscreen ? Set(workspace.fullscreenWindows) : []
        let strip = workspace.stripFrames, previous = lastStrips[key]
        let display = displays.display(containingSpace: key)
        // A window going fullscreen, or coming back, or fullscreen and changing size, does not resize as it glides
        // where that would show: its app takes a size far slower than a move, and a size and a move one after the other.
        // - One that pushes a strip, whose neighbours move with it and would leave its edge behind, or one shown over the
        //   others that moves as well as resizing, which its app would show half done on every step, changes size once,
        //   where that cannot be seen, and only moves as it glides (see ResizeOnce): growing, it is first staged at its
        //   size where it is; shrinking, it takes its size once there, with the pass's write.
        //   One growing mostly to the left, as the right column does, grows as if dragged by its left edge instead, its
        //   right edge just past the screen's (see `ResizeOnce.anchored`): unless another display or the Dock is past
        //   that edge.
        // - Where its frames on the way would show where they must not (`ResizeOnce.applies`), or, in a strip, out of
        //   view or sharing its column, which the others in it would leave uncovered, one that pushes takes its whole
        //   frame first, growing, or holds its frame until the others are back, shrinking, and the strip glides around it.
        // - Any other keeps to resizing as it glides.
        // Read where the window server has them: just after a glide the window model can be a move or two behind. A
        // window counts as coming back until it has its size.
        let frameOf = { [self] (id: WindowID) -> CGRect? in
            let info = dinky_window_info(id)
            return info.exists ? info.frame : model.windows[id]?.frame
        }
        let edge = display.map { $0.visibleArea.maxX < $0.frame.maxX - 0.5 ? $0.visibleArea.maxX : $0.frame.maxX } ?? 0
        let dock = display.map { $0.visibleArea.maxX < $0.frame.maxX - 0.5 } ?? false
        enum Change { case once, whole, none }
        let change = { [self] (id: WindowID, pushing: Bool) -> Change in
            guard id != dragging, display != nil, let target = layout.frames[id], model.windows[id] != nil,
                  let frame = frameOf(id), !animator.rests(id, at: frame, askedFor: target),
                  ResizeOnce.resizes(frame, target) else { return .none }
            let fits = (strip[id] == nil || workspace.isInView(id) && workspace.columns(around: id).own.count == 1)
                && ResizeOnce.applies(from: frame, to: target, edge: edge, wall: workspace.walls.contains(.right), dock: dock)
            if fits, pushing || ResizeOnce.movesAndResizes(frame, target) { return .once }
            return pushing ? .whole : .none
        }
        let grows = { (id: WindowID) -> Bool in
            guard let frame = frameOf(id), let target = layout.frames[id] else { return false }
            return ResizeOnce.grows(frame, target)
        }
        let growsLeft = { (id: WindowID) -> Bool in
            guard let frame = frameOf(id), let target = layout.frames[id] else { return false }
            return ResizeOnce.growsLeft(frame, target) && !workspace.walls.contains(.right) && !dock
        }
        let fullscreenNow = Set(workspace.fullscreenWindows)
        let changing = Dictionary(uniqueKeysWithValues: fullscreenNow.map { ($0, change($0, pushed.contains($0))) })
        let leavingChange = Dictionary(uniqueKeysWithValues: (lastFullscreen[key] ?? []).subtracting(fullscreenNow).map {
            ($0, change($0, workspace.pushesFullscreen && strip[$0] != nil))
        })
        // Any other window changing size and moving, as a column or tile `cycle-size` widens or narrows: one growing to
        // the left grows by its left edge as one going fullscreen does, one narrowing from the left glides at its size
        // and takes its own with the write, so neither shows its right side pulled in.
        let resizing = Set(layout.order.filter { id in
            !fullscreenNow.contains(id) && leavingChange[id] == nil && change(id, false) == .once
        })
        let narrowing = resizing.filter { id in
            guard let frame = frameOf(id), let target = layout.frames[id] else { return false }
            return ResizeOnce.shrinksRight(frame, target)
        }
        let growing = Set(changing.filter { $0.value == .once && grows($0.key) }.keys)
        let growLeft = growing.filter(growsLeft).union(resizing.filter(growsLeft))
        let growOnce = growing.subtracting(growLeft)
        let growWhole = Set(changing.filter { $0.value == .whole && grows($0.key) }.keys)
        let staged = growOnce.union(growWhole)
        // Shrinking, or growing on one side while shrinking on the other, the window glides at its size and takes its
        // own with the write; held, it stays where it is till then.
        let entering = staged.union(growLeft)
        let shrinkOnce = Set(changing.filter { $0.value == .once && !grows($0.key) }.keys)
            .union(entering.isEmpty ? Set(leavingChange.filter { $0.value == .once }.keys) : []).union(narrowing)
        let held = Set(changing.filter { $0.value == .whole && !grows($0.key) }.keys)
            .union(entering.isEmpty ? Set(leavingChange.filter { $0.value == .whole }.keys) : [])
        let leavingAll = Set(leavingChange.filter { $0.value != .none }.keys)
        let writeThen = { [weak self] (landed: @escaping () -> Void) in
            guard let self else { return }
            applier.apply(layout, pids: pids, front: workspace.focused) { [weak self] results in
                DispatchQueue.main.async {
                    landed()
                    guard let self, self.enabled else { return }
                    self.animator.noteLanded(results)
                    // Windows coming back from fullscreen that have their sizes now no longer count as coming back.
                    let landed = Set(results.filter { $0.got != nil }.map(\.job.id))
                    let back = leavingAll.intersection(landed).subtracting(self.workspaces[key]?.fullscreenWindows ?? [])
                    if !back.isEmpty { self.lastFullscreen[key]?.subtract(back) }
                    for result in results { if let got = result.got { self.landedWidths[result.job.id] = (result.job.frame.width, got.width) } }
                    self.noteUnread(results)
                    let untucked = layout.screen.map { Self.untucked(results, on: $0) } ?? []
                    let unconfirmed = self.applier.unconfirmedMinimums
                    // A window that came out narrower than its tile is placed by its width from now on, at once.
                    self.edit(key) { workspace in
                        workspace.minimumSizes = self.minimumSizes(in: workspace)
                        workspace.observedWidths = self.observedWidths(in: workspace)
                        workspace.untuckable.formUnion(untucked.filter { workspace.contains($0) && !unconfirmed.contains($0) })
                    }
                    self.flush()
                    // A refusal counts on the second pass; run it soon rather than on the next event.
                    if !self.applier.unconfirmedMinimums.isDisjoint(with: layout.order) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            self?.dirty.insert(key)
                            self?.flush()
                        }
                    }
                }
            }
        }
        let write = { writeThen {} }
        lastStrips[key] = strip.isEmpty ? nil : (strip, layout.frames, fullscreen)
        lastFullscreen[key] = fullscreenNow.union(leavingAll)
        guard animates, snap.remove(key) == nil else { return write() }
        // Stacking first, so the window coming to the front of an accordion slides in on top.
        applier.raiseIntoOrder(layout, pids: pids, front: workspace.focused)
        let sized = staged.union(shrinkOnce), special = sized.union(held).union(growLeft)
        let frameNow = { [self] (id: WindowID) -> CGRect? in special.contains(id) ? frameOf(id) : model.windows[id]?.frame }
        // Those growing to the left are taken past the screen edge first, then held there as their left edges glide to
        // their targets, taking longer.
        func anchors(to targets: [WindowID: CGRect]) -> [WindowID: ResizeOnce.Anchor] {
            Dictionary(uniqueKeysWithValues: growLeft.compactMap { id in
                targets[id].map { (id, ResizeOnce.Anchor(target: $0, edge: edge)) }
            })
        }
        let drawn = Dictionary(uniqueKeysWithValues: growLeft.map { ($0, ResizeOnce.drawn) })
        // Those changing size once glide to their places at the size they have, their steps moves; those held stay put.
        // One still gliding has the size its steps write now, which the window server shows a step or so later.
        func hold(_ targets: inout [WindowID: CGRect], from starts: [WindowID: CGRect]) {
            for id in sized {
                guard let start = starts[id], let target = targets[id] else { continue }
                targets[id] = ResizeOnce.glideTarget(target, size: animator.frame(of: id)?.size ?? start.size)
            }
            for id in held { if let start = starts[id] { targets[id] = start } }
        }

        /// Glides a tree that is no strip to `layout`.
        func glideTree() {
            let starts = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in
                id == dragging ? nil : frameNow(id).map { (id, $0) }
            })
            var targets = layout.frames
            hold(&targets, from: starts)
            applier.assume(starts.filter { special.contains($0.key) }.mapValues(\.size), pids: pids)
            animator.animate(key, from: starts, to: targets, pids: pids, slower: drawn, anchors: anchors(to: targets),
                             then: write)
        }

        /// Glides the strip to `layout`.
        func glideStrip() {
            var starts = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in
                id == dragging ? nil : frameNow(id).map { (id, $0) }
            })
            // A strip glides as a whole, in strip coordinates, parked on every frame. A window resting where the last pass
            // put it starts where the strip had it then, even an app's that snapped to a grid or kept a minimum size a few
            // points off, which would otherwise glide apart from the rest; one still gliding carries on from where it is.
            // A new window, or one the user moved or resized, starts from where it is.
            // Windows shown fullscreen over the strip (`[fullscreen] scrolling = 'over'`) glide to the screen as usual; the
            // strip still parks the others around where it has them. Pushing fullscreen windows glide with the strip.
            var targets = layout.frames
            for (id, frame) in strip where !fullscreen.contains(id) {
                targets[id] = frame
                // Start a resting window where the strip had it, for a continuous scroll — but not one that was
                // fullscreen last pass: it rests at its fullscreen frame, not a strip one, and must glide down from there.
                // One changing size once or held keeps the size it has: only where it starts goes back to the strip's.
                if let start = starts[id], let was = previous?.strip[id], let placed = previous?.placed[id],
                   !(previous?.fullscreen.contains(id) ?? false),
                   animator.isAnimating(id) || animator.rests(id, at: start, askedFor: placed) {
                    starts[id] = special.contains(id) ? CGRect(origin: was.origin, size: start.size) : was
                }
            }
            hold(&targets, from: starts)
            // Nothing of the strip to glide, as on arriving at a Space: written at once, with no stage put up over windows
            // that are already where they go, which would only flash their snapshots' shadows over the real ones. Not
            // while a glide is under way, which this pass takes over and finishes before its write.
            let anyMoves = targets.contains { id, target in
                guard let start = starts[id] else { return false }
                return !start.isClose(to: target, within: 1) && !animator.rests(id, at: start, askedFor: target)
            }
            guard anyMoves || strip.keys.contains(where: animator.isAnimating) else { return write() }
            // A long scroll takes longer, a little more for each column it passes, so a window an app is slow to move
            // falls less far behind the others in a frame.
            let moved = strip.compactMap { id, frame in starts[id].map { abs(frame.minX - $0.minX) } }.max() ?? 0
            let column = max(workspace.bounds.width * CGFloat(workspace.columnWidth), 1)
            let stretch = AnimationCurve.stripStretch(base: Double(config.animations.durationMs) / 1000,
                                                      columns: Double(moved / column))
            applier.assume(Dictionary(uniqueKeysWithValues: strip.keys.compactMap { id in
                id == dragging ? nil : frameNow(id).map { (id, $0.size) }
            }), pids: pids)
            // Where the strip's windows that are not gliding are now: where the last pass put them. Parking follows the
            // columns in front, so one of them can still have to move while the others glide.
            let resting = (previous?.placed ?? [:]).filter { id, _ in strip[id] != nil && id != dragging && !fullscreen.contains(id) }
            // A window not resizing as it glides and the columns beside it move together, and each move of theirs is a
            // move only, which apps keep up with; but one can take a frame or two longer over a move now and then, just
            // after a resize most of all, so on every frame the one moving away from the other is held at the other's edge
            // as the window server shows it. A gap of the inner gap, the nudge and a point is let be. Only a window in
            // view with its column to itself, where strip and screen agree.
            let leads = special.filter { id in
                strip[id] != nil && !fullscreen.contains(id) && workspace.isInView(id) && workspace.columns(around: id).own.count == 1
            }.map { ($0, workspace.columns(around: $0)) }
            let guardGap = workspace.gaps.horizontal + ResizeOnce.nudge + 1
            let place = { (frames: [WindowID: CGRect]) -> [WindowID: CGRect] in
                var input = strip
                for (id, frame) in frames where !fullscreen.contains(id) { input[id] = frame }
                for (lead, beside) in leads {
                    input = ResizeOnce.guarded(input, lead: lead, left: beside.left, right: beside.right, gap: guardGap,
                                               anchored: growLeft.contains(lead)) { id in
                        let info = dinky_window_info(id)
                        return info.exists ? info.frame : nil
                    }
                }
                var placed = workspace.placeStrip(input)
                // Placed as the guard has it: hanging past the screen edge at its size, such a window is no window
                // scrolled out to be parked.
                for (lead, _) in leads where input[lead] != nil { placed[lead] = input[lead] }
                for id in fullscreen where frames[id] != nil { placed[id] = frames[id] }
                return placed
            }
            // With the scripting addition, the strip glides by moving the real windows through Dock's connection each
            // frame: no snapshots, no Screen Recording, and windows slide past the screen edges that Accessibility clamps.
            // The real frames go to their places underneath at once; the transforms clear once the glide ends and those
            // frames have landed. Every strip window is placed every frame, the moving ones over the resting ones.
            // The transforms only translate, so a window whose size also changes this pass (restoring from a filled or
            // enlarged state, a column width change) must resize through Accessibility, where its app re-renders, rather
            // than be stretched by a transform; such a pass is left to the snapshot or window glide below. So is one with a
            // window staged at its size just now, whose snapshot, taken before, would come out stretched, or held.
            let saResizing = !special.isEmpty || strip.contains { id, frame in
                guard let size = frameNow(id)?.size else { return false }
                return abs(size.width - frame.width) > 1 || abs(size.height - frame.height) > 1
            }
            if fullscreen.isEmpty, !saResizing, ScriptingAddition.available {
                let stripIDs = Array(strip.keys)
                saGlideTokens += 1
                let token = saGlideTokens
                saGlides[key] = (token, stripIDs, layout)
                let saGlide = SAGlide { [weak self] in self?.endSAGlide(key, token) }
                var initial: [WindowID: CGRect] = [:]
                for id in stripIDs { initial[id] = starts[id] ?? strip[id] }
                ScriptingAddition.transform(initial)
                writeThen { saGlide.framesLanded() }
                return animator.animate(key, from: starts, to: targets, pids: pids, stretch: stretch,
                                        sink: { ScriptingAddition.transform(strip.merging($0) { $1 }) }) { saGlide.glideEnded() }
            }
            // Snapshots are fixed bitmaps, so a window resizing this pass (restoring from a filled or enlarged state, a
            // width change) would be stretched by them just as a transform would; such a pass glides the windows directly.
            let glidesSnapshots = (config.scrolling.glide == .snapshots || config.scrolling.glide == .scriptingAddition)
                && fullscreen.isEmpty && !saResizing && Thumbnails.shared.permitted
            // A window moving away from the columns beside it, as one coming back from fullscreen does, takes a little
            // longer than they do, so it follows them rather than being held at their edges: an app coming back into view
            // can be slow over its first moves, and the window held at its edge would lurch along in its steps. A window
            // growing to the left, and the columns it pushes, take longer too (see `ResizeOnce.drawn`).
            var slower = Dictionary(uniqueKeysWithValues: leads.compactMap { lead, _ in
                shrinkOnce.union(held).contains(lead) ? (lead, ResizeOnce.trailing) : nil
            }).merging(drawn) { $1 }
            for (lead, beside) in leads where growLeft.contains(lead) {
                for id in (beside.left + beside.right).joined() { slower[id] = ResizeOnce.drawn }
            }
            guard glidesSnapshots, let display = displays.display(containingSpace: key) else {
                return animator.animate(key, from: starts, to: targets, pids: pids, place: place, resting: resting,
                                        stretch: stretch, slower: slower, anchors: anchors(to: targets), then: write)
            }
            // Snapshots of the strip glide over a snapshot of what is behind it, while the windows go to their places
            // underneath at once. Without the snapshots in time, the windows glide. The snapshots are parked as the
            // windows are at an edge with nothing beyond it, so the peeks there stay through the glide; past a wall,
            // where a window hides behind the columns, a snapshot glides on in strip coordinates, where the stage does
            // not reach, rather than over the column in view.
            animator.stop(key)
            glideTokens += 1
            let token = glideTokens
            glides[key] = (token, nil, layout)
            let corners = Dictionary(uniqueKeysWithValues: strip.keys.compactMap { id in
                model.windows[id].map { (id, CGFloat($0.cornerRadius)) }
            })
            GlideStage.capture(Array(strip.keys), on: display) { [weak self] stage in
                guard let self, glides[key]?.token == token else { stage?.remove(fading: false); return }
                guard let stage else {
                    glides[key] = nil
                    animator.animate(key, from: starts, to: targets, pids: pids, place: place, resting: resting,
                                     stretch: stretch, then: write)
                    return
                }
                glides[key]!.stage = stage
                stage.onRemoved = { [weak self] in
                    if self?.glides[key]?.token == token { self?.glides[key] = nil }
                }
                var current = starts.filter { strip[$0.key] != nil }
                let (bounds, walls) = (workspace.bounds, workspace.walls)
                let parked = { (frames: [WindowID: CGRect]) -> [WindowID: CGRect] in
                    let placed = place(frames)
                    return Dictionary(uniqueKeysWithValues: frames.map { id, frame in
                        let pastWall = frame.minX < bounds.minX - 1 && walls.contains(.left)
                            || frame.maxX > bounds.maxX + 1 && walls.contains(.right)
                        return (id, pastWall ? frame : placed[id] ?? frame)
                    })
                }
                stage.show(at: parked(current), order: layout.order, corners: corners)
                // A frame later, so the stage is up before the windows move under it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { writeThen { stage.windowsLanded() } }
                animator.animate(key, from: starts, to: targets, pids: pids, stretch: stretch, sink: { frames in
                    current.merge(frames) { $1 }
                    stage.move(parked(current))
                }) {
                    stage.glideEnded()
                }
            }
        }

        let glide = strip.isEmpty ? glideTree : glideStrip
        // Raised over what they grow over, the others where they are now.
        if !entering.isEmpty {
            var over = layout
            for id in layout.order where !entering.contains(id) { if let frame = model.windows[id]?.frame { over.frames[id] = frame } }
            applier.raiseIntoOrder(over, pids: pids, front: workspace.focused)
        }
        guard !staged.isEmpty else { return glide() }
        // A glide still under way, as after a focus change just before, would go on moving them, and write its layout
        // over their sizes once it ends.
        animator.stop(key)
        pushTokens += 1
        let token = pushTokens
        pushes[key] = (token, layout)
        var staging: [WindowID: CGRect] = [:]
        for id in staged {
            guard let current = frameOf(id), let target = layout.frames[id] else { continue }
            staging[id] = growOnce.contains(id) ? ResizeOnce.staging(from: current, to: target, edge: edge) : target
        }
        stage(staging, token: token, order: layout.order, front: workspace.focused, pids: pids,
              live: { [weak self] in self?.pushes[key]?.token == token }) { [weak self] in
            guard let self else { return }
            pushes[key] = nil
            glide()
        }
    }

    /// Writes the windows in `staging` their frames there, stacked as `order` has them with `front` in front, then,
    /// once they show there or where their apps keep them instead, as the write's readback finds them, or after two
    /// seconds all the same, for an app not answering, runs `then`. Not before the write has been read back, which is
    /// also when the apps' queues are free again: a glide set off sooner would have its steps wait behind it, and stand
    /// still, then jump. Looked at on every display frame through the window server, which shows a frame as soon as its
    /// app does: a readback alone is no sign, an app that answers late still has to show the frame. Meanwhile the
    /// windows count as gliding, under `token`. Nothing more once `live` is false or dinky is off.
    private func stage(_ staging: [WindowID: CGRect], token: Int, order: [WindowID], front: WindowID?,
                       pids: [WindowID: pid_t], live: @escaping () -> Bool, then done: @escaping () -> Void) {
        for id in staging.keys { stagingWindows[id] = token }
        var settled: [WindowID: CGRect] = [:], answered = false
        let layout = Layout(frames: staging, order: order.filter { staging[$0] != nil })
        applier.apply(layout, pids: pids, front: front) { [weak self] results in
            DispatchQueue.main.async {
                self?.animator.noteLanded(results)
                for result in results { if let got = result.got { settled[result.job.id] = got } }
                answered = true
            }
        }
        let started = CACurrentMediaTime()
        func ended() {
            for id in staging.keys where stagingWindows[id] == token { stagingWindows[id] = nil }
        }
        func check() {
            guard live(), enabled else { return ended() }
            let shown = answered && staging.allSatisfy { id, frame in
                let info = dinky_window_info(id)
                guard info.exists, let got = settled[id] else { return true }
                return ResizeOnce.shows(info.frame, staging: frame) || info.frame.isClose(to: got, within: 2)
            }
            guard shown || CACurrentMediaTime() - started > 2 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120) { check() }
                return
            }
            ended()
            done()
        }
        check()
    }
    /// Windows of a strip that were asked to tuck under the nearest parked column, with less than `peek` on `screen`,
    /// but whose app moved them back with more than that showing, at the width asked for: AppKit does so with a
    /// window asked to leave less than a point on screen. They park at `peek` from then on. One that came out at
    /// another width is placed by that width next time instead (`observedWidths`).
    private static func untucked(_ results: [FrameResult], on screen: CGRect) -> [WindowID] {
        results.compactMap { result in
            guard let got = result.got, abs(got.width - result.job.frame.width) <= 1 else { return nil }
            let asked = result.job.frame
            let left = asked.maxX - screen.minX, right = screen.maxX - asked.minX
            if asked.minX < screen.minX, left < Workspace.peek, got.minX > asked.minX + 1,
               got.maxX - screen.minX > Workspace.peek { return result.job.id }
            if asked.maxX > screen.maxX, right < Workspace.peek, got.minX < asked.minX - 1,
               screen.maxX - got.minX > Workspace.peek { return result.job.id }
            return nil
        }
    }

    /// Each window's width as it came out the last time it was written at the width its tile has now, for the windows
    /// of a strip. A width seen at another tile width says nothing about this one.
    private func observedWidths(in workspace: Workspace) -> [WindowID: CGFloat] {
        guard workspace.isScrolling else { return [:] }
        let strip = workspace.stripFrames
        return Dictionary(uniqueKeysWithValues: strip.compactMap { id, frame in
            landedWidths[id].flatMap { $0.asked == frame.width ? (id, $0.got) : nil }
        })
    }

    /// Ends a scripting-addition glide, clearing the Dock transforms it held, unless a newer pass has already taken
    /// those windows over (its token differs).
    private func endSAGlide(_ key: UInt64, _ token: Int) {
        guard let sa = saGlides[key], sa.token == token else { return }
        saGlides[key] = nil
        ScriptingAddition.reset(sa.ids)
    }

    /// Moves a floating window to `frame`: gliding there from where it is when passes glide, then written with
    /// readback and raised as a pass's windows are. With `resizingOnce`, as for filling the display, a window that
    /// moves as well as resizing changes size once, where that cannot be seen, and only moves as it glides (see
    /// ResizeOnce): growing, it takes its whole size first; shrinking, it takes its new size once there.
    func placeFloating(_ id: WindowID, at frame: CGRect, resizingOnce: Bool = false) {
        guard let window = model.windows[id] else { return }
        floatingTargets[id] = frame
        let key = Self.floatingKey(id)
        pushes[key] = nil
        let pids = [id: window.pid]
        let layout = Layout(frames: [id: frame], order: [id])
        let write = { [weak self] in
            guard let self else { return }
            applier.apply(layout, pids: pids, front: id) { [weak self] results in
                DispatchQueue.main.async { self?.animator.noteLanded(results) }
            }
        }
        guard animates else { return write() }
        let info = dinky_window_info(id)
        let start = info.exists ? info.frame : window.frame
        let display = displays.display(ofWindow: id)
        let dock = display.map { $0.visibleArea.maxX < $0.frame.maxX - 0.5 } ?? false
        let edge = display.map { dock ? $0.visibleArea.maxX : $0.frame.maxX } ?? 0
        guard resizingOnce, ResizeOnce.movesAndResizes(start, frame), let display,
              ResizeOnce.applies(from: start, to: frame, edge: edge, wall: walls(of: display).contains(.right), dock: dock) else {
            return animator.animate(key, from: [id: start], to: [id: frame], pids: pids, then: write)
        }
        guard ResizeOnce.grows(start, frame) else {
            // Still gliding, at the size its steps write, which the window server shows a step or so later.
            let size = animator.frame(of: id)?.size ?? start.size
            applier.assume([id: size], pids: pids)
            return animator.animate(key, from: [id: start], to: [id: ResizeOnce.glideTarget(frame, size: size)],
                                    pids: pids, then: write)
        }
        // Growing mostly to the left, it grows as if dragged by its left edge, as a tile does (see `apply`).
        if ResizeOnce.growsLeft(start, frame), !walls(of: display).contains(.right), !dock {
            return animator.animate(key, from: [id: start], to: [id: frame], pids: pids, slower: [id: ResizeOnce.drawn],
                                    anchors: [id: ResizeOnce.Anchor(target: frame, edge: edge)], then: write)
        }
        animator.stop(key)
        pushTokens += 1
        let token = pushTokens
        pushes[key] = (token, layout)
        let staging = ResizeOnce.staging(from: start, to: frame, edge: edge)
        stage([id: staging], token: token, order: [id], front: id, pids: pids,
              live: { [weak self] in self?.pushes[key]?.token == token }) { [weak self] in
            guard let self else { return }
            pushes[key] = nil
            guard placements[id]?.floating == true, model.windows[id] != nil else { return }
            let now = dinky_window_info(id)
            let staged = now.exists ? now.frame : staging
            applier.assume([id: staged.size], pids: pids)
            animator.animate(key, from: [id: staged], to: [id: ResizeOnce.glideTarget(frame, size: staged.size)],
                             pids: pids, then: write)
        }
    }

    /// Stops a floating window's staging for a glide, as when it stops floating: the glide is no longer its to take.
    func endFloatingStage(_ id: WindowID) {
        pushes[Self.floatingKey(id)] = nil
    }

    /// Where a floating window is, or where it is gliding to.
    func floatingFrame(of id: WindowID) -> CGRect? {
        if animator.isAnimating(id) || stagingWindows[id] != nil, let target = floatingTargets[id] { return target }
        let info = dinky_window_info(id)
        return info.exists ? info.frame : model.windows[id]?.frame
    }

    /// The animator's key for one floating window's glide, apart from every Space ID, which keys a tree's.
    private static func floatingKey(_ id: WindowID) -> UInt64 { 1 << 63 | UInt64(id) }

    /// Whether passes glide windows to their tiles.
    var animates: Bool {
        config.animations.enabled && config.animations.durationMs > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Whether dinky is gliding the window to its tile right now.
    func isAnimating(_ id: WindowID) -> Bool { animator.isAnimating(id) || stagingWindows[id] != nil }

    /// The windows dinky is gliding to their tiles right now.
    var animatingWindows: [WindowID] { animator.animating }

    private func minimumSizes(in workspace: Workspace) -> [WindowID: CGSize] {
        var sizes: [WindowID: CGSize] = [:]
        for id in workspace.windows { sizes[id] = applier.minimumSize(of: id, app: model.windows[id]?.bundleID) }
        return sizes
    }
}
