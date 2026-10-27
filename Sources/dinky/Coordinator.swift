import AppKit
import DinkyCommands
import DinkyConfig
import DinkyLayout
import DinkyPrivate

/// What the coordinator knows about a window it has classified. `space` is nil off the user Spaces
/// (on a native full-screen Space), where nothing is tiled. `freed` marks a window floating only because a `free`
/// workspace floated it, which tiles again on a workspace with another layout.
struct Placement {
    let floating: Bool
    var space: UInt64?
    var freed = false
}

// The serialized owner of layout state: one Workspace per Space, keyed by Space ID, fed by the window and
// display models, applied through the frame applier. Every change marks the trees it touched dirty; `flush` applies the
// dirty trees that are on screen. Main thread only.
final class Coordinator {
    let model = WindowModel()
    var enabled = true {
        didSet {
            if !enabled {
                applier.cancel(); animator.cancel(); pushes = [:]; stagingWindows = [:]; systemTiling = [:]
                // Dock's glides too, their windows back at their real frames: one left would carry on for good.
                for sa in saGlides.values { ScriptingAddition.reset(sa.ids) }
                saGlides = [:]
                PeekClicks.shared.clear()
                dropStripScroll()
            }
            if enabled, !oldValue { reconcile() }
        }
    }

    let displays: DisplayModel
    private(set) var config: Config
    let applier = FrameApplier()
    private lazy var animator = Animator(applier: applier)
    private var borders: BorderManager?
    /// The noop flash's glow, over any window and its border: borders on or off, its app excluded or not.
    private lazy var noopGlow = NoopGlow { [weak self] id in self?.borders?.border(above: id) }
    /// The glow along a display's side as fingers push its strip on past an end.
    private lazy var edgeGlow = EdgeGlow()
    func isBorderWindow(_ id: WindowID) -> Bool { borders?.isBorder(id) == true || noopGlow.isBorder(id) }

    /// Makes a window's edge glow once, for a binding that did nothing, unless `[borders] noop-flash` is off.
    func flashBorder(of id: WindowID) {
        guard config.borders.noopFlash, let window = model.windows[id], window.isDocument else { return }
        noopGlow.flash(id, config: config.borders, model: model)
    }
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
    /// When a display last came, went, moved or changed size. While macOS rearranges the displays, Accessibility cannot
    /// read some windows for a moment, so until `displaySettle` after this a window it cannot read keeps its tile. See
    /// `noteUnread(_:)`.
    private var displaysChangedAt: CFTimeInterval = 0
    private static let displaySettle: CFTimeInterval = 10
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
    var drag: DragSession?
    var dragging: WindowID? { drag?.id }
    /// Whether dinky is moving windows now: a glide, a staging or system tiling still settling, a push, a strip held
    /// by fingers or the mouse, or a drag.
    var movesWindows: Bool {
        !animator.animating.isEmpty || !stagingWindows.isEmpty || !systemTiling.isEmpty || !pushes.isEmpty
            || stripScroll != nil || drag != nil
    }
    /// The tiled window the mouse button is down on, from the first frame change the press brings till the window has
    /// gone from where it was pressed, which makes the press a drag, or the button comes up. See Drag.swift.
    var windowPress: WindowPress?
    /// Windows the user unpinned, which their rules do not pin again as they run once more (see `retryUnreachable`).
    var unpinnedByHand: Set<WindowID> = []
    /// Each app's window the user focused last, by process.
    private var lastUsed: [pid_t: WindowID] = [:]
    /// Pins dinky raised while their app was in the background: raising made each its app's main window, so the app
    /// coming to the front would open on it rather than on the window the user had (see `syncFocus`).
    private var raisedInBackground: Set<WindowID> = []
    /// The last pin `frontWindow` read in front, the window its app had focused, and when.
    private var frontRead: (read: WindowID, focused: WindowID, at: CFTimeInterval)?
    /// Watches the left button come up anywhere, for a click into a pin (see `start`).
    private var clickMonitor: Any?
    /// A fresh read of focus is waiting to run after window events, and another came meanwhile.
    private var focusReadPending = false
    private var focusReadAgain = false
    /// A pin its app said was its focused window, which `frontWindow` may then read straight while it stays focused.
    private var confirmedPin: WindowID?
    /// Apps that did not answer `frontWindow` in time, till when they are not asked.
    private var frontBackoff: [pid_t: CFTimeInterval] = [:]
    /// Trees `moveTree` took to a display of another size or other gaps, whose pins are fitted once the move holds.
    private var pendingPinFit: Set<UInt64> = []
    /// A raise of the pins of a strip fingers hold is under way.
    private var pinRaiseInFlight = false
    /// A pass of `raiseCoveredPins` is waiting to run after window events.
    private var pinRaisePending = false
    /// Windows a drop took to another Space's tree, by that Space, until they are on it: macOS can report one on the
    /// Space it left for a moment, which must not take it out of its new tree.
    var arriving: [WindowID: UInt64] = [:]
    /// A window taken out of the tree of a Space as it moved to another (`WorkspaceNumbers`).
    var onWindowLeft: ((WindowID, UInt64) -> Void)?
    lazy var placeholders = DragPlaceholders()
    /// Grabs windows pressed anywhere with `[drag] mouse-modifier` held.
    private lazy var modifierDrag = ModifierDrag(coordinator: self)
    /// Called when the focused window changes.
    var onFocusChange: (() -> Void)?
    private(set) var lastFocused: WindowID = 0
    /// The focused display just before `lastFocused` took focus.
    private(set) var displayBeforeFocus: String?
    /// A window dinky just focused, and until when focus reads that disagree are taken as stale.
    private var focusing: (id: WindowID, until: Date, activated: Bool)?
    /// Set from a focus change a click made until `clickQuiet` after its button comes up: nothing is laid out
    /// meanwhile. See `holdForClick()`.
    private var clickHold = false
    /// How long after the button of a click that moved focus comes up before the pass it held runs.
    private static let clickQuiet: CFTimeInterval = 0.1
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
    /// By scrolling tree, a glide driven by the Dock scripting addition: the windows it holds transformed and the
    /// layout it is gliding to, so a superseding pass clears those transforms. See ScriptingAddition.
    private var saGlides: [UInt64: (token: Int, ids: [WindowID], carry: GlideCarry)] = [:]
    private var saGlideTokens = 0
    /// By tree, or by a floating window's animator key, windows going fullscreen being written their whole sizes
    /// before they glide, and the layout they glide to then. See `ResizeOnce`.
    private var pushes: [UInt64: (token: Int, carry: GlideCarry)] = [:]
    private var pushTokens = 0
    /// The windows being written their whole sizes before they glide, by the token of the staging that has them: as
    /// good as gliding, for whatever asks.
    private var stagingWindows: [WindowID: Int] = [:]
    /// Windows macOS is filling or putting back itself (see SystemTiling), by the token of the request and whether it is
    /// filling: as good as gliding, left alone by passes until they land, and fullscreen meanwhile as the system is
    /// taking them, whatever the tree says, so the pass after they land takes them on from there.
    private var systemTiling: [WindowID: (token: Int, filling: Bool, pressed: Bool)] = [:]
    private var systemTilingTokens = 0
    /// Windows Fill took to fullscreen, and the frame each had before, for Return to Previous Size to bring them back to.
    private var systemFilled: [WindowID: CGRect] = [:]
    /// Windows macOS still has tiled, which only Return to Previous Size undoes: frames dinky writes do not. Picking a
    /// window in Mission Control puts every such window on its display back where macOS's tiling has it, filling the
    /// screen or side by side, over the strip (see `missionControlClosed`). Fill tiles a window, and one Mission Control
    /// moved as it closed is taken to be tiled; a tree's window here is put back through the system the next time it is
    /// focused out of fullscreen, then laid out from there.
    private var systemTiled: Set<WindowID> = []
    private let tiler = SystemTiler()
    /// The `strip` lines of the log. See StripTelemetry.swift.
    private let telemetry = StripTelemetry()
    /// Where dinky last sent each floating window, so a command pressed again mid-glide starts from where the
    /// window is going rather than where it is.
    private(set) var floatingTargets: [WindowID: CGRect] = [:]
    /// Floating windows filling their display with `fullscreen`, and the frame each had before. In memory only.
    var filledFrom: [WindowID: CGRect] = [:]
    /// Windows of `free` workspaces that `grid --toggle` placed, and the frame each had before. In memory only.
    var griddedFrom: [WindowID: CGRect] = [:]
    /// Fingers holding a strip to scroll it (`[gestures.scroll]`). See `beginStripScroll()`.
    private struct StripScroll {
        /// The strip's tree, by its Space.
        let key: UInt64
        /// The display it shows on, by its UUID.
        let display: String
        /// When the fingers were last heard from.
        var heard: CFTimeInterval
        /// Whether its windows follow the fingers through Dock's connection rather than Accessibility.
        let throughDock: Bool
        /// When the trackpad ticks as columns pass under the fingers.
        var ticker = StripTicker(target: nil, offset: 0)
        /// Which hold this is, so a tick checked again at its gap's end knows the fingers are still on the same one.
        var hold = 0
        /// A tick is checked again at the end of its gap.
        var tickPending = false
    }
    private var stripScroll: StripScroll?
    /// Counts the holds of a strip, numbering each (`StripScroll.hold`).
    private var stripHolds = 0
    /// By tree, a strip the fingers just let go of, its windows still moving at their speed, and whether through Dock
    /// (true) or Accessibility (false), so its next pass glides them on that way, from where they are.
    private var flung: [UInt64: Bool] = [:]
    /// Looks every `stripScrollCheck` while fingers hold a strip, as SlideScroll does, for its Space going from under
    /// them.
    private var stripScrollWatch: Timer?
    private static let stripScrollCheck: TimeInterval = 0.1
    /// How long fingers holding a strip may go unheard before they count as lifted: a trackpad gone, its frames lost.
    private static let stripScrollQuiet: CFTimeInterval = 1
    /// How far a strip coasts once the fingers lift: as far as their speed would take it in this many seconds.
    private static let stripScrollFling = 0.15
    /// Bumped as fingers let go of a strip, so only the last let-go's glance waits for its strip to rest.
    private var stripGlance = 0

    init(displays: DisplayModel, config: Config) {
        self.displays = displays
        self.config = config
    }

    func start() {
        // The display focus is on, as dinky tracks focus, not as a pin Dock ordered in front would have it.
        displays.frontWindow = { [weak self] in self?.trackedFront() ?? dinky_border_focused_window() }
        // A click into a pin of the app in front, ordered in front of its other windows, makes it key with no event to
        // say so: once the click has landed, focus is read again where the pin is in front.
        // The press notes the window it went down on, which `frontWindow` takes for focus while a strip moves.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let point = event.cgEvent?.location else { return }
            if event.type == .leftMouseDown {
                // A window list read a click: only where a strip that shows has pins.
                guard let self, workspaces.contains(where: { self.isVisible($0.key) && !$0.value.pinnedWindows.isEmpty }) else { return }
                lastPress = (CACurrentMediaTime(), frontmostWindow(at: point, in: onScreenWindowInfo())?.id)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { self?.recheckClickedPin(at: point) }
        }
        model.isGliding = { [weak self] id in self?.animator.isAnimating(id) ?? false }
        model.observe { [weak self] event in self?.handle(event) }
        // Frames held while an app was not answering are written as a pass of their own, which reports to no one:
        // lay its windows out again, so their landing, stacking and minimum sizes are taken in as after any pass.
        PeekClicks.shared.onClick = { [weak self] id in self?.reveal(id) }
        telemetry.name = { [unowned self] id in "\(id) \(model.windows[id]?.appName ?? "?")" }
        PeekClicks.shared.start()
        applier.onRecovered = { [weak self] pid in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let windows = model.windows
                for (key, workspace) in workspaces where workspace.windows.contains(where: { windows[$0]?.pid == pid }) {
                    dirty.insert(key)
                }
                flush()
            }
        }
        // Focus read on a window while it was being raised into order was passed over (see `syncFocus`): once the raise
        // has settled, read it again, in case the user did bring that window forward meanwhile.
        applier.onRaised = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.syncFocus()
                self?.flush()
            }
        }
        animator.onArrive = { [weak self] ids in self?.borders?.arrived(ids) }
        animator.displayOf = { [unowned self] key in
            // A floating window's glide has its id in its key (see `floatingKey`); any other is a Space's.
            key & (1 << 63) != 0 ? displays.display(ofWindow: UInt32(truncatingIfNeeded: key))?.id
                                 : displays.display(containingSpace: key)?.id
        }
        var known = Set(displays.displays.map(\.uuid))
        var arrangement = Self.arrangement(of: displays)
        displays.observe { [weak self] displays in
            guard let self else { return }
            let now = Set(displays.displays.map(\.uuid))
            if now != known { snap.formUnion(workspaces.keys) }
            known = now
            let arranged = Self.arrangement(of: displays)
            if arranged != arrangement {
                displaysChangedAt = CACurrentMediaTime()
                // Once they have settled, every tree is laid out again, so a window that could not be read meanwhile
                // goes back into its tile.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.displaySettle) { [weak self] in self?.reconcile() }
            }
            arrangement = arranged
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
        ScriptingAddition.enabled = config.scriptingAddition
        animator.configure(durationMs: config.animations.durationMs,
                           easing: Easing(rawValue: config.animations.curve.rawValue),
                           damping: config.animations.damping)
        modifierDrag.update(modifiers: config.drag.mouseModifier, sides: config.modifiers)
        // Pinned windows' rings are drawn by the border manager too, focus borders on or off.
        if config.borders.enabled || config.borders.pinned {
            borders = borders ?? BorderManager(config: config.borders, model: model,
                                               front: { [unowned self] fresh in frontWindow(fresh: fresh) },
                                               rereads: false,
                                               isAnimating: { [unowned self] id in animator.isAnimating(id) })
            borders?.update(config: config.borders)
        } else {
            borders = nil
        }
        configureWorkspaces()
        // A workspace switched to/from free or untiled must release/acquire its existing windows too.
        for window in model.windows.values { track(window) }
        fitToDisplays()
        dirty.formUnion(workspaces.keys)
        flush()
    }

    // MARK: Events

    /// Raises the pins of the strips on screen that a band window of their own is in front of, where they overlap:
    /// macOS stacks windows by focus, and a band window focused last would cover the pin it slides under. So also for a
    /// band window in front of a pin that is about to sweep across it (`sweeping`, by pin), as a glide sets off, and for
    /// any band window in front of one as fingers take hold of the strip (`takingHold`). `raising` are windows the same
    /// pass is about to raise, counted as in front of every pin. `stack` is the window server's list of the windows
    /// shown, front to back, when the caller has read it already (`onScreenStack`). Never over a window outside the tree
    /// at the pin's level
    /// or lower in front of it, a dialog or a floating window in use, nor while a click, a drag or a press is under way,
    /// or a window is fullscreen over the pins. A pinned column is raised whole once any of its windows is covered, as it
    /// stacks, its shown window last; and a window of a pinned app that has focus, or that the tree is focusing, is
    /// raised after them, so it keeps its app's focus: it is not counted as covering a pin, as it would cover it again.
    func raiseCoveredPins(in only: UInt64? = nil, sweeping: [WindowID: Set<WindowID>] = [:], raising: Set<WindowID> = [],
                          takingHold: Bool = false, stack shown: [(id: WindowID, layer: Int, frame: CGRect?)]? = nil) {
        guard enabled, !clickHold, drag == nil, windowPress == nil else { return }
        var keys = workspaces.keys.filter { key in
            (only.map { $0 == key } ?? isVisible(key)) && !(workspaces[key]?.pinnedWindows.isEmpty ?? true)
        }
        // One raise of a held strip at a time: the next check comes once it is done. Other trees go on.
        let heldKey = stripScroll?.key
        if pinRaiseInFlight, let heldKey { keys.removeAll { $0 == heldKey } }
        guard !keys.isEmpty else { return }
        // The windows shown, front to back, where the window server shows them: the window model hears late of moves
        // through Dock, which a strip's glides and the fingers' scrolls make.
        let stack = (shown ?? onScreenStack()).compactMap { shown -> StackedWindow? in
            guard let window = model.windows[shown.id], window.isVisible else { return nil }
            return StackedWindow(id: shown.id, layer: shown.layer, frame: shown.frame ?? window.frame, pid: window.pid)
        }
        // Dock's scripting addition orders pins in front of any window, the active app's too, and leaves every app's
        // main and key window as they were. Accessibility cannot put one in front of the active app's windows, and makes
        // the window it raises its app's main one, so the focused window of a pinned app is raised after it and the
        // window its app had put back.
        let ordering = ScriptingAddition.available && ScriptingAddition.orders
        // The focused window, read once, and through Dock only once there is something to order.
        var frontCache: WindowID?
        func frontNow() -> WindowID {
            if let frontCache { return frontCache }
            let front = focusedWindow
            frontCache = front
            return front
        }
        // The app in front as the window server has it, not the one dinky is about to focus: its windows are the ones
        // Accessibility cannot raise a window over.
        let asked = dinky_border_focused_window()
        let shownFront = model.windows[asked]?.pid ?? dinky_window_info(asked).pid
        var raise: [WindowID] = [], fronts: [WindowID] = [], raisedBy: [(key: UInt64, pins: [WindowID], cause: String)] = []
        for key in keys {
            let workspace = workspaces[key]!
            // The windows raised after the pins to keep their apps' focus: the focused one, and the tree's own only
            // where it is of the front app, as one of another app focuses nothing raised.
            var candidates: [WindowID] = []
            // Only on the Space of the front window: another display's tree raises nothing to keep focus.
            if !ordering {
                let front = frontNow(), frontApp = model.windows[front]?.pid
                if (placements[front]?.space ?? model.windows[front]?.spaceID) == key {
                    candidates = ([workspace.focused].compactMap { $0 }.filter { model.windows[$0]?.pid == frontApp } + [front])
                        .filter { workspace.pinSide(of: $0) == nil }
                }
            }
            // While fingers hold the strip, its windows move through Dock without the window model hearing, so any
            // band window in front of a pin counts, as when they took hold.
            let held = takingHold || heldKey == key
            let reach: Set<Int32> = ordering || shownFront == 0 ? [] : [shownFront]
            let raised = workspace.pinsToRaise(stack: stack, candidates: candidates, raising: raising, sweeping: sweeping,
                                               takingHold: held, beyondReach: reach)
            guard !raised.isEmpty else { continue }
            raise += raised
            let cause = takingHold ? "fingers took hold" : held ? "while fingers hold the strip"
                : sweeping.isEmpty ? "after window events" : "a glide sweeping under"
            raisedBy.append((key, raised, cause))
            let raisedApps = Set(raised.compactMap { model.windows[$0]?.pid })
            for id in candidates where !raise.contains(id) && !fronts.contains(id)
                && model.windows[id].map({ raisedApps.contains($0.pid) }) == true { fronts.append(id) }
        }
        guard !raise.isEmpty else { return }
        let front = frontNow(), frontApp = model.windows[front]?.pid
        let holding = heldKey.map { held in raisedBy.contains { $0.key == held } } ?? false
        if holding { pinRaiseInFlight = true }
        // Logged, rings put back and pins taken for raised in the background only for those it raised or ordered: none
        // where it could move focus, nor a pin of an app come to the front meanwhile.
        let report = { [weak self] (done: [WindowID], background: [WindowID], how: String) in
            guard let self else { return }
            if holding { pinRaiseInFlight = false }
            let hit = Set(done)
            guard !hit.isEmpty else { return }
            for (key, pins, cause) in raisedBy where pins.contains(where: hit.contains) {
                telemetry.pinsRaised(key, pins.filter(hit.contains), cause + how)
            }
            borders?.replaceRings(raise.filter(hit.contains))
            let focused = dinky_border_focused_window()
            let live = self.model.windows[focused]?.pid ?? dinky_window_info(focused).pid
            raisedInBackground.formUnion(background.filter { hit.contains($0) && self.model.windows[$0]?.pid != live })
        }
        if ordering {
            let pids = Dictionary(raise.compactMap { id in model.windows[id].map { (id, $0.pid) } }) { first, _ in first }
            // In front of its own app's windows, a pin of an app in the background is the one that app comes to the
            // front on, as with Cmd-Tab: `syncFocus` takes it back to the window that app had.
            let background = raise.filter { pids[$0] != nil && pids[$0] != shownFront }
            let pinned = Set(workspaces.values.flatMap(\.pinnedWindows))
            return applier.raisePins(raise, pids: pids, front: front, frontPid: frontApp ?? 0, asked: asked, pinned: pinned,
                                     ordering: true) { done in
                report(done, background, ", through Dock")
            }
        }
        // A pin of an app in the background becomes its main window as it is raised: the window of that app the user
        // had goes back on top of its app's after it, where it covers no pin, so the app comes to the front on it. Not
        // while fingers hold or take hold of the strip: the two would swap places at every check.
        var restore: [WindowID] = [], background: [WindowID] = []
        for pin in raise {
            guard let pid = model.windows[pin]?.pid, pid != frontApp else { continue }
            background.append(pin)
            guard let used = lastUsed[pid], used != pin, !raise.contains(used), !fronts.contains(used), !restore.contains(used),
                  let key = placements[used]?.space, !takingHold, heldKey != key,
                  let workspace = workspaces[key], workspace.pinSide(of: used) == nil,
                  workspace.isInView(used) || workspace.hangsUnderPin(used), let frame = model.windows[used]?.frame,
                  !PinSide.allCases.contains(where: { workspace.pinFrame($0)?.intersects(frame) == true }),
                  let at = stack.firstIndex(where: { $0.id == used }) else { continue }
            // Nor under anything in front of it at its level or lower, an accordion sibling, a window fullscreen or
            // floating over it: that is left to `syncFocus`, which follows the app back to it as it comes to the front.
            let level = stack[at].layer
            guard !stack.prefix(at).contains(where: { $0.layer <= level && $0.frame.intersects(frame) }) else { continue }
            restore.append(used)
        }
        let ownPins = raise.filter { model.windows[$0]?.pid == frontApp }, otherPins = raise.filter { !ownPins.contains($0) }
        let ids = pinRaiseOrder(ownPins: ownPins, fronts: fronts, front: front,
                                keepsFront: fronts.contains(front) || !ownPins.isEmpty, otherPins: otherPins, restore: restore)
        let pids = Dictionary(ids.compactMap { id in model.windows[id].map { (id, $0.pid) } }) { first, _ in first }
        applier.raisePins(ids, pids: pids, front: front) { done in report(done, background, "") }
    }

    private func handle(_ event: WindowEvent) {
        // Detected here, not in the border manager, so hover focus stands down even with borders off.
        // Only Mission Control's own windows, or a window coming, going, hiding, showing or changing level, can open or
        // close it: not the moves of a glide.
        let mayShowMissionControl = event.window?.bundleID == "com.apple.WindowManager"
            || [.windowCreate, .windowDestroy, .windowClose, .windowHide, .windowUnhide, .windowLevel].contains(event.kind)
        if mayShowMissionControl, MissionControl.shared.update(from: model) {
            borders?.missionControlChanged()
            noopGlow.missionControlChanged()
            if !MissionControl.shared.active { missionControlClosed() }
        }
        borders?.handle(event)
        noopGlow.handle(event)
        if event.kind == .spaceChange {
            edgeGlow.dismiss()
            // Peeks of a Space no longer shown would catch clicks on the one shown now.
            for key in workspaces.keys where !isVisible(key) { PeekClicks.shared.update([], space: key) }
        }
        if let window = event.window {
            // A drag first, then the Space: macOS moves a window dragged over another display to its Space, often in
            // the first move dinky hears of, and the drag keeps it in its tree (Drag.swift) only once it is one.
            let moved = event.change != .removed && [.windowMove, .windowResize].contains(event.kind)
            if moved { noteFrameChange(of: window.id, from: event.frameBefore) }
            event.change == .removed ? forget(window.id) : track(window)
            if moved, dragging != window.id { noteFrameChange(of: window.id, from: event.frameBefore) }
            if moved { noteSize(of: window.id) }
            if moved { ScriptingAddition.noteShown(window.id, at: window.frame.origin) }
        }
        // An app come to the front or a new window: what it focuses is read afresh.
        if [.frontApp, .windowCreate].contains(event.kind) { forgetFrontRead() }
        // Another app in front: what a command read of the one before is past. Not a new window, which may come while
        // the strip still moves.
        if event.kind == .frontApp { readWhileMoving = nil }
        if [.frontApp, .windowReorder, .windowCreate].contains(event.kind) { syncFocus() }
        if [.frontApp, .windowReorder].contains(event.kind) {
            // The front window settles a few ms after the event, as the border manager also knows: Cmd-` or a click
            // between one app's windows can report the previous window still in front.
            // One read at a time, which the borders take too, rather than one each and one per event.
            if focusReadPending { focusReadAgain = true } else { readFocusSoon() }
        }
        if [.frontApp, .windowReorder, .windowCreate].contains(event.kind) {
            // Cmd-Tab, a click in the Dock or a new window can bring a band window up over a pin: once it settles, the
            // pin goes back on top. One pass at a time: the raises post the same events.
            if !pinRaisePending {
                pinRaisePending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                    self?.pinRaisePending = false
                    self?.raiseCoveredPins()
                }
            }
        }
        flush()
    }

    /// Picking a window in Mission Control puts the windows macOS still has tiled back where its tiling has them as it
    /// closes, over the frames dinky wrote, and holds them there until its animation is over (see `systemTiled`). Once
    /// it is, every tree on screen is laid out again, and a window found out of place is taken to be tiled.
    private func missionControlClosed() {
        for delay in [0.4, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, enabled, !MissionControl.shared.active else { return }
                var moved: [WindowID] = []
                for (key, workspace) in workspaces where isVisible(key) {
                    let layout = workspace.layout()
                    // Not one whose app is not answering, which is out of place for that.
                    for id in workspace.windows where !isAnimating(id) && id != dragging {
                        guard let want = layout.frames[id], let pid = model.windows[id]?.pid, !applier.isBusy(pid) else { continue }
                        let live = dinky_window_info(id)
                        if live.exists, !live.frame.isClose(to: want, within: 4) { moved.append(id) }
                    }
                    dirty.insert(key)
                }
                if !moved.isEmpty {
                    systemTiled.formUnion(moved)
                    print("\(stamp()) mission control: closed, put back \(moved.map(String.init).joined(separator: " "))")
                }
                flush()
            }
        }
    }

    /// Re-reads every window and display, moves windows to the trees of the Spaces they are on now
    /// (so a window dragged to another Space stays there), and re-applies every tree on screen. The model
    /// publishes every window it re-reads, so `handle` tracks and forgets them. Empty trees of Spaces that
    /// no longer exist are dropped.
    /// `placingAtOnce`, as strips a display change put back, are placed without glides.
    func reconcile(placingAtOnce: Set<UInt64> = []) {
        configureWorkspaces()
        model.reconcile()
        fitToDisplays()
        workspaces = workspaces.filter { displays.display(containingSpace: $0.key) != nil || !$0.value.windows.isEmpty }
        syncFocus()
        snap.formUnion(placingAtOnce.filter { workspaces[$0] != nil })
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
            let (bounds, gaps) = (workspaces[key]!.bounds, workspaces[key]!.gaps)
            workspaces[key]!.bounds = display.visibleArea
            workspaces[key]!.gaps = self.gaps(on: display)
            workspaces[key]!.walls = walls(of: display)
            // Only as the display or the gaps change: pins dropped at any other pass would never come back.
            // The band's own room first, as a pass would, so the pins are fitted to a band at the size it lays out at.
            if workspaces[key]!.bounds != bounds || workspaces[key]!.gaps != gaps {
                workspaces[key]!.fitBand()
                workspaces[key]!.fitPins()
            }
        }
    }

    /// Where each display is, by UUID: what changes when one comes, goes, moves or changes size.
    private static func arrangement(of model: DisplayModel) -> [String: CGRect] {
        Dictionary(model.displays.map { ($0.uuid, $0.frame) }) { first, _ in first }
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
        // Its pins are fitted to the display it lands on only where that is another size or has other gaps, once the
        // move holds (`fitMovedTree`): a reorder of one display's Spaces leaves them as they are.
        let resized = tree.bounds != display.visibleArea || tree.gaps != gaps(on: display)
        pendingPinFit.remove(from)
        if resized { pendingPinFit.insert(to) } else { pendingPinFit.remove(to) }
        tree.bounds = display.visibleArea
        tree.gaps = gaps(on: display)
        tree.walls = walls(of: display)
        workspaces[to] = tree
        for (id, placement) in placements where placement.space == from { placements[id]!.space = to }
    }

    /// Fits the tree `moveTree` took to `key` to the display it is on now, as for a display that changed, the band's own
    /// room first and then, where the display is another size, the pins: once its windows are there, so a move rolled
    /// back brings the tree back as it was.
    func fitMovedTree(_ key: UInt64) {
        guard workspaces[key] != nil else { return }
        let resized = pendingPinFit.remove(key) != nil
        edit(key) { workspace in
            workspace.fitBand()
            if resized { workspace.fitPins() }
        }
        flush()
    }

    /// Resolve layout settings by a Space's current numbered position, which can change when Spaces are reordered.
    private func configureWorkspaces() {
        for key in workspaces.keys {
            workspaces[key]!.accordionPadding = CGFloat(config.accordion.padding)
            workspaces[key]!.autoOrientAccordions = config.accordion.orientation == .auto
            workspaces[key]!.columnWidth = config.scrolling.columnWidth
            workspaces[key]!.columnCentring = columnCentring
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
        // A free workspace tiles nothing; a tree kept from before it was free lays out as tiles if it ever must.
        case .tiles, .dwindle, .free: .dwindle(.tiles)
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
        // A dragged window keeps its tree till the drop, which decides where it goes (Drag.swift): macOS moves one
        // dragged over another display to its Space on the way, which can be a free workspace's. One the drop took to
        // another Space's tree keeps that tree till it is on its Space.
        guard window.id != dragging, arriving[window.id] == nil else { return }
        // Off a user Space (an inactive tab, a hidden app's window, a native full-screen Space) a window keeps what it
        // has: that is no workspace whose layout it could take.
        let shown = !window.isMinimized && window.isOrderedIn
            && displays.display(containingSpace: window.spaceID)?.userSpaces.contains(window.spaceID) == true
        let free = settings(for: window.spaceID).isFree
        if shown, !placements[window.id]!.floating, free {
            // Poured onto a free workspace, it leaves its tree as one moved to another Space does.
            if let old = placements[window.id]!.space { onWindowLeft?(window.id, old) }
            float(window.id)
        } else if shown, placements[window.id]!.freed, !free {
            filledFrom[window.id] = nil
            griddedFrom[window.id] = nil
            placements[window.id] = Placement(floating: false, space: nil)
        }
        guard !adopting.contains(window.id), !placements[window.id]!.floating else { return }
        let old = placements[window.id]!.space
        if let old, window.isMinimized || !window.isOrderedIn, takeOverTile(of: window.id, in: old) {
            telemetry.member(old, workspaces[old], window.id, joined: false, "an inactive tab, its tab took its place")
            placements[window.id]!.space = nil
            return
        }
        let new = window.isMinimized ? nil : key(of: window)
        guard old != new, heldTabs[window.id] == nil else { return }
        // Taken to a tiled Space on another display with the mouse button down, as macOS takes a window dragged over
        // one: a drag, from the tree it is in, which the drop takes it out of, if no frame change started it yet. Taken
        // to another Space on the same display, as switching Spaces holding it does, it goes along.
        if let old, let new, displays.display(containingSpace: old)?.id != displays.display(containingSpace: new)?.id {
            noteDisplayChange(of: window.id, to: new)
            if window.id == dragging { return }
        }
        if let old {
            let why = window.isMinimized ? "minimized, or its app hidden" : !window.isOrderedIn ? "ordered out"
                : new.map { "moved to Space \($0)" } ?? "on Space \(window.spaceID), which dinky does not tile"
            telemetry.member(old, workspaces[old], window.id, joined: false, why)
            // Minimized or hidden, a pin is pinned again as it comes back; moved to another Space, it is unpinned.
            if new == nil, window.isMinimized || !window.isOrderedIn {
                edit(old) { $0.depart(window.id) }
            } else {
                edit(old) { $0.remove(window.id) }
                onWindowLeft?(window.id, old)
            }
        }
        // A window coming from another Space's tree is moving, not switching tabs: tabs share a Space.
        if let new, old == nil, holdAsTab(window, in: new) { return }
        if let new {
            // Back in another tree, it is no pin away from the one it left.
            for key in workspaces.keys where key != new && workspaces[key]!.departedPins.values.contains(window.id) {
                edit(key) { $0.forgetPinned(window.id) }
            }
            // Pinned again only with room for it, judged with the minimums the next pass lays out with, its own too.
            let own = applier.minimumSize(of: window.id, app: window.bundleID)
            edit(new) { workspace in
                workspace.minimumSizes = minimumSizes(in: workspace)
                workspace.minimumSizes[window.id] = own
                workspace.arrive(window.id)
            }
            telemetry.member(new, workspaces[new], window.id, joined: true, old.map { "from Space \($0)" } ?? "shown")
        }
        placements[window.id]!.space = new
    }

    /// Floats tiled windows that two passes in a row found gone from Accessibility, so they would hold a tile they
    /// never move into. They are looked at again when they take focus. A window whose app is only slow to answer is
    /// busy, not gone: it keeps its tile, and the count it has so far stands until the app answers. Nor does one
    /// count while the displays settle (see `displaysChangedAt`): floated then and tiled again later, a strip's
    /// windows would come back in a new order.
    private func noteUnread(_ results: [FrameResult]) {
        for result in results {
            let id = result.job.id
            if result.busy { continue }
            guard result.gone, placements[id]?.floating == false, model.windows[id] != nil else { unread[id] = nil; continue }
            // While the displays settle, a window that cannot be read is most likely only being moved: it keeps its tile,
            // and what was counted before starts over.
            if CACurrentMediaTime() - displaysChangedAt < Self.displaySettle { unread[id] = nil; continue }
            unread[id, default: 0] += 1
            guard unread[id]! >= 2 else { continue }
            unread[id] = nil
            NSLog("dinky: window %u cannot be read through Accessibility; floating it until it can", id)
            float(id, freed: false)
            unreachable[id] = CACurrentMediaTime()
        }
    }

    /// Looks again at a window floated because its AX element could not be reached, at most every few seconds, and
    /// classifies it afresh once it can be, so it tiles as any window would.
    func retryUnreachable(_ window: Window) {
        guard let since = unreachable[window.id], CACurrentMediaTime() - since > 3, !applier.isBusy(window.pid) else { return }
        unreachable[window.id] = CACurrentMediaTime()
        guard axWindow(pid: window.pid, wid: window.id, timeout: 0.25) != nil else { return }
        unreachable[window.id] = nil
        attempts[window.id] = nil
        placements[window.id] = nil
        track(window)
        flush()
    }

    /// Floats a window out of the tree it was tiled in: by default one that reached a `free` workspace, which tiles
    /// again once it is on a workspace with another layout (see `track(_:)`).
    private func float(_ id: WindowID, freed: Bool = true) {
        if let space = placements[id]?.space {
            telemetry.member(space, workspaces[space], id, joined: false,
                             freed ? "floated, on a free workspace" : "floated, Accessibility cannot read it")
            // Only a window floated while it cannot be read is pinned again as it tiles back: on a free workspace it was
            // taken there.
            edit(space) { freed ? $0.remove(id) : $0.depart(id) }
        }
        heldTabs[id] = nil
        placements[id] = Placement(floating: true, space: nil, freed: freed)
    }

    private func forget(_ id: WindowID) {
        if frontRead.map({ $0.read == id || $0.focused == id }) == true || confirmedPin == id { forgetFrontRead() }
        unpinnedByHand.remove(id)
        raisedInBackground.remove(id)
        lastUsed = lastUsed.filter { $0.value != id }
        // A pin away when it closed: no tree remembers it, its id free for another window.
        for key in workspaces.keys where workspaces[key]!.departedPins.values.contains(id) {
            edit(key) { $0.forgetPinned(id) }
        }
        stagingWindows[id] = nil
        systemTiling[id] = nil
        systemFilled[id] = nil
        systemTiled.remove(id)
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
        guard let placement = placements.removeValue(forKey: id), let space = placement.space else { return }
        telemetry.member(space, workspaces[space], id, joined: false, "closed")
        guard !takeOverTile(of: id, in: space) else { return }
        edit(space) { $0.remove(id) }
    }

    /// The front app's frontmost document window on a current Space, as the window server stacks them; but where that
    /// is a pin Dock ordered in front of a window of its own app the user was on, which it does without changing focus,
    /// the window that app has focused, as Accessibility says. Asked of the app only then, not for dinky's settled focus,
    /// nor of an app that is busy or did not answer lately (then the window dinky last had of it), and kept for a moment
    /// unless the button went down since; `fresh` asks again all the same.
    func frontWindow(fresh: Bool = false, whileMoving: Bool = false) -> WindowID {
        lastReadDeferred = false
        let id = dinky_border_focused_window()
        guard ScriptingAddition.orders, let window = model.windows[id], let key = placements[id]?.space,
              workspaces[key]?.pinSide(of: id) != nil, !(id == confirmedPin && id == lastFocused && focusing == nil)
        else {
            // No pin to read through: the window server's answer, what a command read while a strip moved past.
            readWhileMoving = nil
            return id
        }
        let pid = window.pid
        // Another window of its app it may be in front of: tiled or floating, shown on a Space that shows.
        let shown = { [self] (other: WindowID) -> Bool in
            guard let w = model.windows[other] else { return false }
            return w.pid == pid && w.isVisible && !w.isMinimized && isVisible(w.spaceID)
        }
        guard model.windows.keys.contains(where: { $0 != id && shown($0) }) else { return id }
        let now = CACurrentMediaTime()
        let sinceDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        if !fresh, let cached = frontRead, cached.read == id, now - cached.at < min(0.2, sinceDown),
           model.windows[cached.focused] != nil { return cached.focused }
        // Not asked, or no use: the window of its app dinky is focusing, or the one it had last, if one shows and is
        // no pin; the pin read only failing those. Never taken for confirmed.
        let fallback = { [self] () -> WindowID in
            confirmedPin = nil
            // The pin itself where dinky is focusing it, as picked in a switcher.
            if focusing?.id == id { return id }
            let pinned = { (other: WindowID) in
                self.placements[other]?.space.flatMap { self.workspaces[$0]?.pinSide(of: other) } != nil
            }
            // What a command read of this app while a strip moved, a pin or not.
            if let read = readWhileMoving, shown(read) { return read }
            // A window dinky is focusing only once activated: before, its app has another focused, which keys go to.
            // Then the window last focused, floating ones too, then the one its app had tiled last.
            let activated = focusing.flatMap { $0.activated ? $0.id : nil }
            return [activated, lastFocused, lastUsed[pid]].compactMap { $0 }.first { shown($0) && !pinned($0) } ?? id
        }
        // While a drag or a glide moves the windows of its strip, asking the app, up to a tenth of a second on the main
        // thread, would hold their frames up: the window dinky has, and the app asked once the strip rests.
        // A command asks all the same (`whileMoving`): it acts on what it reads.
        let moving = !whileMoving && stripMoves(key)
        // A click on the pin itself, which shows in front: the pin, as the user chose. The window the press went down on,
        // not the one under the pointer now, which a window dragged over the pin or a menu over it hides. Asks no app.
        if moving, drag == nil, stripScroll == nil, let press = lastPress, CACurrentMediaTime() - press.at < 0.3,
           press.window == id {
            readFocusOnceStill(key)
            return id
        }
        guard !applier.isBusy(pid), (frontBackoff[pid] ?? 0) <= now else { return fallback() }
        if moving {
            readFocusOnceStill(key)
            lastReadDeferred = true
            return fallback()
        }
        let real = focusedWindowID(of: pid, timeout: 0.1)
        let after = CACurrentMediaTime()
        let focused: WindowID
        if real == 0 || after - now > 0.1 {
            frontBackoff[pid] = after + 2
            focused = fallback()
        } else if real == id {
            // The pin is what its app has focused: it may be read straight from now on, till focus moves.
            confirmedPin = id
            focused = id
            // The app answered: its answer is the newest, kept till focus follows it if it is not the window dinky had.
            readWhileMoving = focused == lastFocused ? nil : focused
        } else if let answer = model.windows[real], isVisible(answer.spaceID) {
            confirmedPin = nil
            focused = real
            readWhileMoving = focused == lastFocused ? nil : focused
        } else {
            focused = fallback()
        }
        frontRead = (id, focused, after)
        return focused
    }

    /// After a click at `point`: where a pin dinky does not have focused reads in front and the click was on it, its
    /// app may have made it key with no event to say so, so focus is read again. A click in the window behind it, as
    /// usual, asks no app.
    private func recheckClickedPin(at point: CGPoint) {
        guard enabled else { return }
        let shown = dinky_border_focused_window()
        guard shown != lastFocused, let key = placements[shown]?.space, workspaces[key]?.pinSide(of: shown) != nil else {
            return
        }
        let frame = onScreenStack().first { $0.id == shown }?.frame ?? model.windows[shown]?.frame
        guard frame?.contains(point) == true else { return }
        syncFocus(fresh: true)
        borders?.refocus()
        flush()
    }

    /// Reads focus afresh 20 ms on, as the front window settles after an event, the borders taking that read; once
    /// more after it where another event came meanwhile, so a burst costs two reads at most.
    /// A read of focus waits for a strip to stop moving (`readFocusOnceStill`).
    private var focusReadDeferred = false
    /// Whether `frontWindow` last answered with the window dinky had rather than asking the app, a strip moving: not news
    /// of focus moving, which `syncFocus` leaves to the read once the strip rests.
    private(set) var lastReadDeferred = false
    /// When the button last went down, and the window it went down on (`frontmostWindow`), while a strip that shows has
    /// pins.
    private var lastPress: (at: CFTimeInterval, window: WindowID?)?
    /// The newest window an app named focused, other than the one dinky had, as a command's read or any read the app
    /// answered: answered first by `frontWindow` till `syncFocus` takes it.
    private var readWhileMoving: WindowID?

    /// `whileMoving` asks the app even while the strip still moves (`frontWindow`), as the wait for it to rest gave up.
    private func readFocusSoon(whileMoving: Bool = false) {
        focusReadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
            guard let self else { return }
            focusReadPending = false
            syncFocus(fresh: true, whileMoving: whileMoving)
            borders?.refocus()
            flush()
            if focusReadAgain {
                focusReadAgain = false
                readFocusSoon()
            }
        }
    }

    /// Whether window `id` at `frame` is where its app last put it when asked for `tile`, or on it (`Animator.rests`).
    func rests(_ id: WindowID, at frame: CGRect, askedFor tile: CGRect) -> Bool {
        animator.rests(id, at: frame, askedFor: tile)
    }

    /// Whether a drag or a glide is moving windows of the strip on `key`, as `frontWindow` should not hold up.
    private func stripMoves(_ key: UInt64) -> Bool {
        drag != nil || dragging != nil || saGlides[key] != nil || pushes[key] != nil
            || workspaces[key]?.windows.contains(where: animator.isAnimating) == true
    }

    /// Reads focus afresh, asking the app, once the strip on `key` stops moving, or after three seconds whatever it does.
    private func readFocusOnceStill(_ key: UInt64) {
        guard !focusReadDeferred else { return }
        focusReadDeferred = true
        let began = CACurrentMediaTime()
        func check() {
            guard enabled else { return focusReadDeferred = false }
            let moves = stripMoves(key)
            guard !moves || CACurrentMediaTime() - began > 3 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { check() }
                return
            }
            focusReadDeferred = false
            frontRead = nil
            // Still moving after three seconds: the app is asked all the same, else the read would wait on it again.
            readFocusSoon(whileMoving: moves)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { check() }
    }

    /// Forgets what `frontWindow` last read: the window behind a pin, and a pin it was told is focused.
    private func forgetFrontRead() {
        frontRead = nil
        confirmedPin = nil
    }

    /// The front app's frontmost window as `frontWindow` has it, asking no app: a pin read in front of the window dinky
    /// last had of its app is that window. For what only needs the display focus is on.
    func trackedFront() -> WindowID {
        let id = dinky_border_focused_window()
        guard let pid = model.windows[id]?.pid, let key = placements[id]?.space, workspaces[key]?.pinSide(of: id) != nil,
              lastFocused != id, model.windows[lastFocused]?.pid == pid else { return id }
        return lastFocused
    }

    /// The front app's frontmost document window on a current Space; or, while a window dinky focused has yet to
    /// come to the front, that window: its app is activated once the Accessibility calls into it are done, off the
    /// main thread, and a command run right after the focus acts on the window it chose. While a strip moves, the
    /// window dinky had of a pin's app, asking it nothing (`frontWindow`).
    var focusedWindow: WindowID {
        if let focusing, Date() < focusing.until { return focusing.id }
        let id = frontWindow()
        // One only in front while it is raised into order behind another is not focused, as `syncFocus` has it.
        return applier.echoesRaise(id) ? lastFocused : id
    }

    /// `focusedWindow` for what acts on the window it reads: asked of its app even while a strip moves. An answer
    /// other than the window dinky had is kept (`readWhileMoving`), so the reads of events meanwhile, which answer
    /// with what dinky had, do not take it back, and the next of them takes it as focus moving.
    var commandFocusedWindow: WindowID {
        if let focusing, Date() < focusing.until { return focusing.id }
        let id = frontWindow(whileMoving: true)
        let focused = applier.echoesRaise(id) ? lastFocused : id
        if focused == lastFocused {
            readWhileMoving = nil
        } else if model.windows[focused] != nil {
            readWhileMoving = focused
        }
        return focused
    }

    /// Focuses a window, raising it and activating its app. For a moment after, focus events that still
    /// report the previous window are ignored, so they do not pull the trees back to it.
    func focus(_ id: WindowID) {
        guard let window = model.windows[id] else { return }
        if let space = placements[id]?.space { telemetry.command(space, "dinky focused \(id) \(window.appName ?? "?")") }
        // A pin focused on purpose is the user's choice, not one raised in the background.
        raisedInBackground.remove(id)
        forgetFrontRead()
        readWhileMoving = nil
        // A band window whose glide in crosses a pin is activated once it rests in the band, as a clicked peek is:
        // activated now, its app would bring it up over the pin as it slides across. Not one already where it goes,
        // which has no glide, though it meets a pin there, as a window fullscreen over the strip does.
        if let key = placements[id]?.space, let workspace = workspaces[key], workspace.pinSide(of: id) == nil,
           !workspace.pinnedWindows.isEmpty {
            var focused = workspace
            focused.focus(id)
            if let target = focused.layout().frames[id], !window.frame.isClose(to: target, within: 1),
               PinSide.allCases.contains(where: { workspace.pinFrame($0)?.intersects(window.frame.union(target)) == true }) {
                focusing = (id, Date() + 3, false)
                edit(key) { $0.focus(id) }
                flush()
                return focusOnceStill(id, in: key)
            }
        }
        activate(id)
    }

    /// Activates `id`'s app on it, now: `focus` without waiting for a glide.
    private func activate(_ id: WindowID) {
        guard let window = model.windows[id] else { return }
        forgetFrontRead()
        readWhileMoving = nil
        // Until the app is activated, which waits on Accessibility calls into it off the main thread (at most about
        // two seconds), and for half a second after.
        focusing = (id, Date() + 3, false)
        focusWindow(pid: window.pid, id: id) { [weak self] activated in
            guard let self, focusing?.id == id else { return }
            forgetFrontRead()
            if activated {
                focusing = (id, Date() + 0.5, true)
                // Activated, its app brought it to the front: over a pin, as one wider than the band hangs, the pin goes
                // back over it now, not only once the window events come.
                if let key = placements[id]?.space, workspaces[key]?.pinnedWindows.isEmpty == false { raiseCoveredPins(in: key) }
            } else {
                // Something else came to the front first: it has focus, and the trees follow it.
                focusing = nil
                syncFocus()
                flush()
            }
        }
    }

    /// Follows focus into the trees, so new windows land beside the focused one and accordions show it.
    private func syncFocus(fresh: Bool = false, whileMoving: Bool = false) {
        let id = frontWindow(fresh: fresh, whileMoving: whileMoving)
        // Only what dinky had, answered while a strip moves: focus moves once the read after it says so, or as a
        // command read it meanwhile. Not even back to the window dinky had, which would undo a command's focus.
        if lastReadDeferred, id != readWhileMoving { return }
        // A window being raised into its place in the stacking comes in front of its app's other windows on the way,
        // which reads as focus moving to it. That is dinky's doing, not the user's, so nothing follows it: not the tree,
        // whose strip would scroll to it and call for more raises, nor the switchers' recency, the hooks or the click
        // hold. Focus is read again once the raise has settled (`FrameApplier.onRaised`).
        if applier.echoesRaise(id) {
            if let key = placements[id]?.space, let workspace = workspaces[key] { telemetry.passedOver(key, workspace, id) }
            return
        }
        if id != lastFocused, let pid = model.windows[id]?.pid {
            // Its app came to the front on a pin dinky raised meanwhile, not one the user chose: back to the window they
            // had. A click on the pin is theirs.
            if raisedInBackground.contains(id), focusing?.id != id, !clickUnderWay(within: 0.3), let used = lastUsed[pid],
               used != id, model.windows[used] != nil, let usedKey = placements[used]?.space, isVisible(usedKey),
               workspaces[usedKey].map({ $0.isInView(used) || $0.hangsUnderPin(used) }) ?? false {
                raisedInBackground = raisedInBackground.filter { model.windows[$0]?.pid != pid }
                return focus(used)
            }
            raisedInBackground = raisedInBackground.filter { model.windows[$0]?.pid != pid }
            if placements[id]?.space != nil { lastUsed[pid] = id }
        }
        if id != lastFocused {
            // Before the override goes: a new window can take focus before it shows. See Adoption.swift.
            displayBeforeFocus = displays.focusedDisplay(window: lastFocused)?.uuid
            WindowSwitcher.shared.focusLeft(lastFocused)
            WorkspaceSwitcher.shared.focusLeft(lastFocused)
            lastFocused = id
            readWhileMoving = nil
            if let window = model.windows[id] { retryUnreachable(window) }
            // Only a window takes focus from a display focused without one, not an app with no window here.
            if id != 0 { displays.focusOverride = nil }
            displays.noteFocus(window: id)
            onFocusChange?()
            if clickUnderWay(within: 0.3) { holdForClick() }
        }
        if let focusing, focusing.id != id, Date() < focusing.until { return }
        // The window dinky is about to activate, read as focused before it is: only its activation, or giving up on
        // it, ends that.
        if let focusing, focusing.id == id, !focusing.activated, Date() < focusing.until {} else { focusing = nil }
        guard let key = placements[id]?.space, let workspace = workspaces[key], workspace.focused != id else { return }
        telemetry.focus(key, workspace, to: id, from: workspace.focused, click: clickUnderWay(within: 0.3))
        // While a click holds the pass, a strip stays where it shows, however focusing would scroll it, till
        // the hold lets go (`revealClickedFocus`), so a drag the press starts is measured against the windows where
        // they are.
        edit(key) { $0.focus(id, holdingScroll: clickHold) }
    }

    /// The tree of a user Space, numbered workspace or not, created on first use. Nil for full-screen Spaces.
    private func key(of window: Window) -> UInt64? {
        guard let display = displays.display(containingSpace: window.spaceID),
              display.userSpaces.contains(window.spaceID) else { return nil }
        let settings = settings(for: window.spaceID)
        guard settings.tiling, !settings.isFree else { return nil }
        let key = window.spaceID
        makeWorkspace(key, on: display)
        return key
    }

    /// Has the next pass on the Space place its windows without gliding.
    func placeAtOnce(_ key: UInt64) {
        snap.insert(key)
    }

    /// Window `id` was moved by a command to `space` on another display, its tree set to be placed at once: once it is
    /// in that tree, watched as it arrives; one that did not join it, as floating or held as a tab, leaves the tree
    /// unsnapped, which would keep fingers and the mouse from taking hold of the strip.
    func joined(_ id: WindowID, _ space: UInt64) {
        if placements[id]?.space == space {
            watchArrival([id: space])
        } else {
            snap.remove(space)
        }
    }

    /// Makes the empty tree of a Space of `display` if it has none yet, as on first use.
    func makeWorkspace(_ space: UInt64, on display: Display) {
        if workspaces[space] == nil { workspaces[space] = newWorkspace(on: display, settings(for: space)) }
    }

    /// An empty tree for a Space of `display` with `settings`, as one is made on first use.
    func newWorkspace(on display: Display, _ settings: WorkspaceSettings) -> Workspace {
        var workspace = Workspace(bounds: display.visibleArea, gaps: gaps(on: display),
                                  accordionPadding: CGFloat(config.accordion.padding),
                                  autoOrientAccordions: config.accordion.orientation == .auto,
                                  algorithm: algorithm(settings))
        workspace.columnWidth = config.scrolling.columnWidth
        workspace.columnCentring = columnCentring
        workspace.fullscreenFocus = fullscreenFocus
        workspace.fullscreenFollowsLater = config.fullscreen.followDelayMs > 0
        workspace.fullscreenPushesStrip = config.fullscreen.scrolling == .push
        workspace.walls = walls(of: display)
        return workspace
    }

    /// Where focusing a scrolling column scrolls it, from `[scrolling] center-focused-column`.
    private var columnCentring: ColumnCentring {
        ColumnCentring(rawValue: config.scrolling.centerFocusedColumn.rawValue) ?? .never
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

    /// A click that moves focus is left to land where it was pressed: after a focus change a click made, the trees
    /// follow focus at once, but nothing is laid out while the button is down and for `clickQuiet` after it comes up;
    /// then the held pass runs. A strip, however focusing would scroll it, to the middle or only into view, holds its
    /// scroll till then as well, unless a window is fullscreen (`Workspace.holdsScroll`): a drag the press starts is
    /// measured against the tree, and one scrolled ahead of the screen would have the window far off its tile and the
    /// pointer over the next column, and drop it there. A strip scrolled under the pressed button would turn the click
    /// into a drag in the app, and dinky's writes, raises and captures would reach the app while it is still taking the
    /// click. A drag, which drops on its own when the button comes up, lets the pass run as soon as it has ended, or
    /// once it shows a drop: a pass while it is still open would leave out the window it has, the focused one, and
    /// raise others of its app over it. A button held past ten seconds stops holding.
    private func holdForClick() {
        guard !clickHold else { return }
        clickHold = true
        let began = CACurrentMediaTime()
        var up: CFTimeInterval?
        var dragged = false
        func check() {
            let now = CACurrentMediaTime()
            dragged = dragged || dragging != nil
            if CGEventSource.buttonState(.combinedSessionState, button: .left) {
                up = nil
            } else if up == nil {
                up = now
            }
            // A drop shown lets the pass run at once, the button still down: the windows make room for it (Drag.swift).
            // A drag that shows nothing holds it till it has ended, as it does within 50 ms of the button coming up: a
            // pass meanwhile could neither write nor raise the window it has (`dragFrozen`), the one the click focused.
            let quiet = drag?.shown != nil
                || (dragging == nil && (up.map { now - $0 >= (dragged ? 0 : Self.clickQuiet) } ?? false))
            guard quiet || now - began > 10 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { check() }
                return
            }
            clickHold = false
            // A drag still under way, as one showing a drop with the button down, keeps the strip still till it ends
            // (Drag.swift): it is measured against the windows where they are.
            if dragging == nil { revealClickedFocus() }
            flush()
            // A raise the click held off, as of a pin on another display a Dock click covered, now that it has let go.
            raiseCoveredPins()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { check() }
    }

    /// Scrolls each strip a click held still to the window the click focused, now that nothing is under the button.
    /// Nothing while a click still holds the passes: its release does it then. See `holdForClick()` and
    /// `Workspace.holdsScroll`.
    func revealClickedFocus() {
        guard !clickHold else { return }
        for (key, tree) in workspaces where tree.holdsScroll { edit(key) { $0.revealFocus() } }
    }

    // MARK: Strip scroll

    /// `[gestures.scroll]`'s fingers on the trackpad, as TrackpadGestures hears them: they take hold of the strip under
    /// the pointer, scroll it, and let go. See `beginStripScroll()`.
    func fingersScrolled(_ scroll: FingerScroll) {
        switch scroll {
        case .began(let dx):
            // Fingers landing again before the last of them were heard to lift: no glance, the stroke goes on.
            if stripScroll != nil { endStripScroll(velocity: 0, glance: false) }
            if beginStripScroll() { scrollStrip(by: dx) }
        case .moved(let dx):
            scrollStrip(by: dx)
        case .ended(let velocity):
            endStripScroll(velocity: velocity)
        }
    }

    /// Fingers take hold of the strip on the display under the pointer, as SlideScroll's do, where it can scroll freely
    /// and nothing else has it: no click, drag or switcher under way, no Space changing or Mission Control, nothing
    /// staged, filling through the system, pushing or glided through Dock transforms. Its windows follow them from
    /// where they are, a glide under way carrying on into it at its speed: through Dock's connection, as a scroll
    /// glides, where Dock moves them all as they are, else through Accessibility. Nothing is laid out on its Space till
    /// they let go. False, and nothing changed, when they take nothing: the rest of their stroke does nothing.
    private func beginStripScroll() -> Bool {
        guard enabled, !clickHold, drag == nil, windowPress == nil,
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !MissionControl.shared.active, !SpaceSwitcher.shared.switching,
              !WindowSwitcher.shared.isShowing, !WorkspaceSwitcher.shared.isShowing,
              let pointer = CGEvent(source: nil)?.location,
              let display = displays.displays.first(where: { $0.frame.contains(pointer) }),
              !dinky_display_is_animating(display.uuid as CFString),
              dinky_current_space_id(display.uuid as CFString) == display.currentSpaceID else { return false }
        let key = display.currentSpaceID
        guard var workspace = workspaces[key], !snap.contains(key), pushes[key] == nil,
              !workspace.windows.contains(where: { stagingWindows[$0] != nil || systemTiling[$0] != nil }),
              workspace.beginFreeScroll() else { return false }
        let strip = workspace.stripFrames, windows = model.windows
        let pids = Dictionary(uniqueKeysWithValues: strip.keys.compactMap { id in windows[id].map { (id, $0.pid) } })
        let sizes = Dictionary(uniqueKeysWithValues: strip.keys.compactMap { id -> (WindowID, CGSize)? in
            serverFrame(id).map { (id, $0.size) }
        })
        // Dock moves windows without resizing them: only a strip whose windows all have the sizes it gives them, with
        // no wall, behind which a window hides at another, can follow the fingers through it.
        let dock = ScriptingAddition.available && ScriptingAddition.moves && workspace.walls.isEmpty
            && strip.allSatisfy { id, frame in
                sizes[id].map { abs($0.width - frame.width) <= 1 && abs($0.height - frame.height) <= 1 } ?? false
            }
        // A scripting-addition glide under way carries on into the follow through Dock, as a newer pass would take it
        // over: not one through Dock transforms, which would stay over the windows, nor one whose windows would have to
        // change size on the way. A glide of the windows themselves carries on through Accessibility.
        if saGlides[key] != nil, !dock { return false }
        let throughDock = dock && (saGlides[key] != nil || !strip.keys.contains(where: animator.isAnimating))
        if throughDock { saGlides[key] = nil }
        workspaces[key] = workspace
        stripScroll = StripScroll(key: key, display: display.uuid, heard: CACurrentMediaTime(), throughDock: throughDock)
        // The column it would settle on as they take hold is not one they moved to: no tick for it.
        stripHolds += 1
        stripScroll?.hold = stripHolds
        if let workspace = workspaces[key] {
            stripScroll?.ticker = StripTicker(target: workspace.heldTarget, offset: workspace.shownOffset,
                                              atEnd: workspace.heldAtEnd)
        }
        // The glance the last let-go left up is of where the strip was.
        WindowSwitcher.shared.endGlance()
        // Peeks move with the strip, so a click on one would miss; the pass after the fingers lift notes them again.
        PeekClicks.shared.update([], space: key)
        applier.assume(sizes, pids: pids)
        // Dock's moves leave the stacking as it is, so the pins go on top now, before anything slides under them.
        raiseCoveredPins(in: key, takingHold: true)
        if throughDock { ScriptingAddition.forget(Array(strip.keys)) }
        telemetry.fingers(key, "took hold" + (throughDock ? ", through Dock" : ""))
        stripScrollWatch?.invalidate()
        stripScrollWatch = Timer.scheduledTimer(withTimeInterval: Self.stripScrollCheck, repeats: true) { [weak self] _ in
            self?.watchStripScroll()
        }
        return true
    }

    /// Scrolls the strip the fingers hold by `dx` trackpad widths, `[gestures.scroll] speed` screens a width, its
    /// content going with them, and has its windows follow it there.
    private func scrollStrip(by dx: Double) {
        guard let scroll = stripScroll else { return }
        stripScroll?.heard = CACurrentMediaTime()
        // A drag, which is the user's to move, ends the scroll where it is.
        guard drag == nil, windowPress == nil else { return endStripScroll(velocity: 0, glance: false) }
        guard var workspace = workspaces[scroll.key], workspace.isScrollingFreely else {
            takeOver(scroll.key)
            return flush()
        }
        let delta = -CGFloat(dx * config.gestures.scroll.speed) * workspace.bounds.width
        let moved = workspace.scrollFreely(by: delta)
        // Pushed on past an end, some or all of the way.
        if abs(delta - moved) >= 0.5 { flashStripEnd(on: scroll.display, last: delta > 0) }
        guard moved != 0 else { return }
        workspaces[scroll.key] = workspace
        followStrip(scroll, in: workspace)
        tickForColumn()
    }

    /// With `[gestures.scroll] haptic`, the trackpad ticks as the column a let-go would settle on changes under the
    /// fingers, as the switchers' picks do: felt only while they touch it, so as the strip moves, not once it rests. Not
    /// for a target flickering at a boundary or an end as resting fingers move a fraction, and not more often than the
    /// ticker's gap: a change inside it is checked again as it ends (`StripTicker`).
    private func tickForColumn() {
        guard config.gestures.scroll.haptic, let scroll = stripScroll, let workspace = workspaces[scroll.key],
              workspace.isScrollingFreely else { return }
        let now = CACurrentMediaTime()
        switch stripScroll!.ticker.moved(to: workspace.heldTarget, offset: workspace.shownOffset, at: now,
                                         atEnd: workspace.heldAtEnd) {
        case .none:
            break
        case .tick(let target):
            tapTrackpad("strip column \(target)", actuation: config.gestures.scroll.hapticStrength.actuation)
        case .later(let at):
            guard !scroll.tickPending else { return }
            stripScroll?.tickPending = true
            let hold = scroll.hold
            DispatchQueue.main.asyncAfter(deadline: .now() + max(at - now, 0)) { [weak self] in
                guard let self, stripScroll?.hold == hold else { return }
                stripScroll?.tickPending = false
                tickForColumn()
            }
        }
    }

    /// The fingers push the strip on display `uuid` on past an end, its `last` or its first: the display's side there
    /// glows, its right or its left, as a binding that does nothing makes a window glow, held while they push. Unless
    /// `[gestures.scroll] edge-flash` is off, whatever `[borders] noop-flash` says.
    private func flashStripEnd(on uuid: String, last: Bool) {
        guard config.gestures.scroll.edgeFlash, let display = displays.displays.first(where: { $0.uuid == uuid }),
              let screen = screen(of: display.id) else { return }
        edgeGlow.flash(on: screen, right: last, config: config.borders)
    }

    /// Has the strip's windows follow it to where the fingers have it now: a window already moving bends towards its
    /// new place at its speed, one at rest sets out from where the last pass left it.
    private func followStrip(_ scroll: StripScroll, in workspace: Workspace) {
        let strip = workspace.stripFrames, previous = lastStrips[scroll.key]?.strip ?? [:], windows = model.windows
        let pids = Dictionary(uniqueKeysWithValues: strip.keys.compactMap { id in windows[id].map { (id, $0.pid) } })
        let targets = strip.filter { pids[$0.key] != nil }
        let starts = Dictionary(uniqueKeysWithValues: targets.map { id, target in (id, previous[id] ?? target) })
        let place = { (frames: [WindowID: CGRect]) in workspace.placeStrip(strip.merging(frames) { $1 }) }
        if scroll.throughDock {
            animator.follow(scroll.key, from: starts, to: targets, pids: pids, sink: { ScriptingAddition.move(place($0)) })
        } else {
            animator.follow(scroll.key, from: starts, to: targets, pids: pids, place: place)
        }
    }

    /// The fingers let go, moving across at `velocity` trackpad widths a second: the strip coasts on as far as that
    /// takes it, then settles with the column showing nearest the middle in view, which takes focus once it rests, and
    /// its pass glides the windows there from where they are, at their speed; once they rest, with `[gestures.scroll]
    /// show-switcher` and `glance`, the window switcher shows the strip for `switcher-ms`, that column's window picked.
    /// A Space gone from under the fingers puts the strip back instead.
    private func endStripScroll(velocity: Double, glance: Bool = true) {
        guard let scroll = stripScroll else { return }
        guard stripScrollShows(scroll) else { return abortStripScroll() }
        let key = scroll.key
        guard let workspace = workspaces[key], workspace.isScrollingFreely else {
            takeOver(key)
            return flush()
        }
        let before = workspace.focused
        let momentum = -CGFloat(velocity * config.gestures.scroll.speed * Self.stripScrollFling) * workspace.bounds.width
        let target = edit(key) { $0.endFreeScroll(momentum: momentum) } ?? nil
        telemetry.fingers(key, "let go" + (target.map { ", \(telemetry.name($0)) takes focus" } ?? ""))
        handBack(key)
        dirty.insert(key)
        guard let target else { return flush() }
        // A flick the fingers' frames never carried past a column, or one that settles back, lands on another column
        // than the trackpad last ticked for: it ticks now, as the first finger lifts, the others still on it, so a
        // column taking focus is always felt.
        if config.gestures.scroll.haptic, target != scroll.ticker.felt {
            tapTrackpad("strip let-go, settles on \(target)", actuation: config.gestures.scroll.hapticStrength.actuation)
        }
        if glance { glanceOnceStill(target, in: key, display: scroll.display) }
        // As SlideScroll does, the window is focused when it is another than before, or focus was on another Space.
        guard target != before || placements[lastFocused]?.space != key else { return flush() }
        focusing = (target, Date() + 3, false)
        flush()
        focusOnceStill(target, in: key)
    }

    /// The strip's Space went from under the fingers, or Mission Control opened: it goes back to where it showed as
    /// they took hold, placed at once, as SlideScroll's does, since what shows now is something else; the rest of their
    /// stroke does nothing.
    private func abortStripScroll() {
        guard let key = stripScroll?.key else { return }
        telemetry.fingers(key, "lost it, the strip no longer showing")
        edit(key) { $0.cancelFreeScroll() }
        handBack(key)
        animator.stop(key)
        flung[key] = nil
        placeAtOnce(key)
        dirty.insert(key)
        flush()
    }

    /// Something ended the fingers' free scroll, as a command, or a window focused or opening, or left the strip
    /// nothing to scroll, as fullscreen: it takes the strip over, laid out as ever from where the windows are, and the
    /// rest of the fingers' stroke does nothing.
    private func takeOver(_ key: UInt64) {
        telemetry.fingers(key, "let go, the strip taken over")
        // A strip still scrolled freely, as one gone fullscreen, is back where it showed as they took hold.
        workspaces[key]?.cancelFreeScroll()
        handBack(key)
        dirty.insert(key)
    }

    /// Ends the fingers' hold on the strip on `key`: its windows may arrive again, and its next pass glides them on
    /// from where they are at the speed they have, the way they moved (`flung`), or places them at once without glides.
    private func handBack(_ key: UInt64) {
        guard let scroll = stripScroll, scroll.key == key else { return }
        stripScroll = nil
        if scroll.throughDock { ScriptingAddition.forget(workspaces[key]?.windows) }
        stripScrollWatch?.invalidate()
        stripScrollWatch = nil
        if animates, !snap.contains(key) {
            flung[key] = scroll.throughDock
            animator.endFollow(key)
        } else {
            animator.stop(key)
        }
    }

    /// Every `stripScrollCheck` while fingers hold a strip: its Space gone from under them puts it back, fingers not
    /// heard from for `stripScrollQuiet` let go, and a band window in front of a pin has the pin raised again.
    private func watchStripScroll() {
        guard let scroll = stripScroll else {
            stripScrollWatch?.invalidate()
            stripScrollWatch = nil
            return
        }
        if !stripScrollShows(scroll) {
            abortStripScroll()
        } else if CACurrentMediaTime() - scroll.heard > Self.stripScrollQuiet {
            endStripScroll(velocity: 0)
        } else {
            // A window its app brought up meanwhile, as one activated just as the fingers came down, goes back under
            // the pins it slides under.
            raiseCoveredPins(in: scroll.key)
        }
    }

    /// Whether the strip the fingers hold still shows: dinky on, Mission Control shut, and its Space its display's
    /// current one and not sliding away, as the window server has it now rather than the display model, which hears
    /// late.
    private func stripScrollShows(_ scroll: StripScroll) -> Bool {
        enabled && !MissionControl.shared.active && !dinky_display_is_animating(scroll.display as CFString)
            && dinky_current_space_id(scroll.display as CFString) == scroll.key
    }

    /// dinky turned off: the fingers hold nothing, and the strip they held forgets it was scrolled freely.
    private func dropStripScroll() {
        if let key = stripScroll?.key { workspaces[key]?.cancelFreeScroll() }
        stripScroll = nil
        stripScrollWatch?.invalidate()
        stripScrollWatch = nil
        flung = [:]
    }

    // MARK: Applying

    func flush() {
        // A click holds the passes, but not the first making room for a drop its press began to show.
        guard !clickHold || drag?.shown != nil else { return }
        // Something ended the fingers' free scroll, as a command or a window focused, or left the strip nothing to
        // scroll, as fullscreen: it takes the strip over.
        if let key = stripScroll?.key, workspaces[key].map({ !$0.isScrollingFreely || !$0.canScrollFreely }) ?? true {
            takeOver(key)
        }
        var keys = dirty
        dirty = []
        // A strip the fingers hold is laid out once they let go: till then it stays dirty.
        if let key = stripScroll?.key, keys.remove(key) != nil { dirty.insert(key) }
        guard enabled else {
            borders?.setPinned([])
            return
        }
        for key in keys where isVisible(key) { apply(key) }
        // The pins shown now get their rings; those gone, hidden or on a Space not shown lose them.
        if let borders {
            borders.setPinned(Set(workspaces.filter { isVisible($0.key) }.flatMap { $0.value.ringedPins }))
        }
    }

    /// Tells `PeekClicks` which of the strip's windows only peek in at a screen edge as this pass lays them out, and
    /// where. None on a workspace without a strip.
    private func notePeeks(_ key: UInt64, frames: [WindowID: CGRect], strip: [WindowID: CGRect],
                           fullscreen: Set<WindowID> = []) {
        guard !strip.isEmpty, let screen = displays.display(containingSpace: key)?.frame else {
            return PeekClicks.shared.update([], space: key)
        }
        // A band window partly under a pin counts as peeking with the part beside it in the band: clicked there, macOS
        // would bring it up over the pin before dinky heard, so it glides into the band first, as a peek does. Not one
        // shown fullscreen, the focused one, nor one whose part beside the pin spans the whole band: it is in view.
        let workspace = workspaces[key]
        let band = workspace?.bandRect
        let pins = PinSide.allCases.compactMap { side in workspace?.pinFrame(side).map { (side, $0) } }
        let peeks = strip.keys.compactMap { id -> PeekClicks.Peek? in
            guard let frame = frames[id] else { return nil }
            let shown = frame.intersection(screen)
            guard !shown.isNull, shown.width > 0 else { return nil }
            if let workspace, let band, workspace.pinSide(of: id) == nil,
               let (side, pin) = pins.first(where: { $0.1.intersects(shown) }) {
                guard !fullscreen.contains(id), workspace.focused != id else { return nil }
                // From the pin's edge, so the gap beside it counts too, to the band's far edge.
                let minX = side == .left ? pin.maxX : max(shown.minX, band.minX)
                let maxX = side == .left ? min(shown.maxX, band.maxX) : pin.minX
                let inBand = min(maxX, band.maxX) - max(minX, band.minX)
                guard maxX - minX > 0, inBand < band.width - 1 else { return nil }
                return PeekClicks.Peek(id: id, rect: CGRect(x: minX, y: shown.minY, width: maxX - minX, height: shown.height))
            }
            guard shown.width <= PeekClicks.widest, shown.width < frame.width else { return nil }
            return PeekClicks.Peek(id: id, rect: shown)
        }
        PeekClicks.shared.update(peeks, space: key)
    }

    /// Brings a strip window whose peek was clicked into view, then focuses it once it rests there: its app is not
    /// activated while its window moves. Until then the tree keeps it focused against the window macOS still has in
    /// front. See PeekClicks.swift.
    func reveal(_ id: WindowID) {
        guard enabled, let key = placements[id]?.space, model.windows[id] != nil else { return }
        focusing = (id, Date() + 3, false)
        telemetry.command(key, "peek of \(id) \(model.windows[id]?.appName ?? "?") clicked")
        edit(key) { $0.focus(id) }
        flush()
        focusOnceStill(id, in: key)
    }

    /// Focuses a window of the tree on `key` once it rests where its tree has it, or after a second and a half all the
    /// same: its app is not activated while its window moves. Nothing once `focusing` is another's, or once the user has
    /// focused another meanwhile.
    private func focusOnceStill(_ id: WindowID, in key: UInt64) {
        let began = CACurrentMediaTime(), from = frontWindow()
        func check() {
            guard focusing?.id == id else { return }
            // Focus taken elsewhere meanwhile, by a click or Cmd-Tab, not a raise of dinky's: that wins, and the tree
            // follows it, as `syncFocus` held it off for this window.
            let now = frontWindow()
            if now != from, now != id, now != 0, !applier.echoesRaise(now) {
                focusing = nil
                syncFocus()
                return flush()
            }
            let moving = animator.isAnimating(id) || pushes[key] != nil
            guard !moving || CACurrentMediaTime() - began > 1.5 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { check() }
                return
            }
            activate(id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { check() }
    }

    /// With `[gestures.scroll] show-switcher`, once the strip on `key` the fingers let go of rests, its glide over, the
    /// window switcher shows it for `switcher-ms`, `id` picked: its glass over the glide would cost the glide frames.
    /// Nothing if, before then, fingers let go again or take hold, a click, a drag or anything that would close a
    /// glance shown comes, focus goes to another window, or the Space no longer shows.
    private func glanceOnceStill(_ id: WindowID, in key: UInt64, display: String) {
        stripGlance += 1
        guard config.gestures.scroll.showSwitcher else { return }
        let began = CACurrentMediaTime(), glance = stripGlance, calledOff = WindowSwitcher.shared.calledOff
        // Longer than the release glide can last, the animator's own limit for it, and Dock's frames landing after.
        let longest = max(1.5, 4 * Double(config.animations.durationMs) / 1000 + 0.5)
        func check() {
            guard glance == stripGlance, calledOff == WindowSwitcher.shared.calledOff, stripScroll == nil, enabled,
                  isVisible(key), drag == nil, windowPress == nil, !clickHold,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  workspaces[key]?.focused == id else { return }
            // Focus compared once the strip rests: while it moves, the read answers what dinky had.
            let moving = saGlides[key] != nil || pushes[key] != nil
                || workspaces[key]?.windows.contains(where: isAnimating) == true
            guard !moving || CACurrentMediaTime() - began > longest else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { check() }
                return
            }
            guard focusedWindow == id else { return }
            WindowSwitcher.shared.glance(space: key, display: display, pick: id,
                                         for: Double(config.gestures.scroll.switcherMs) / 1000)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { check() }
    }

    /// Once the strip on `key` is still, logs any of its windows not where it has them, and any window on its Space
    /// that no tree holds sitting off the screen. See StripTelemetry.
    private func checkStrip(_ key: UInt64) {
        telemetry.schedule(key, moving: { [weak self] in
            guard let self else { return false }
            return saGlides[key] != nil || pushes[key] != nil || dragging != nil || clickHold || stripScroll?.key == key
                || workspaces[key]?.windows.contains(where: isAnimating) == true
        }) { [weak self] in
            guard let self, enabled, isVisible(key), let workspace = workspaces[key] else { return }
            let loose = model.windows.values.filter { w in
                w.spaceID == key && w.isNormal && !w.isMinimized && !workspace.contains(w.id) && !self.isBorderWindow(w.id)
                    && NSRunningApplication(processIdentifier: w.pid)?.isHidden != true
            }.map { w in
                (id: w.id, placement: self.placements[w.id].map { $0.floating ? "floating" : "tiled on Space \($0.space ?? 0)" }
                    ?? "not classified")
            }
            telemetry.check(key, workspace, loose: loose) { id in self.model.windows[id].map { self.applier.isBusy($0.pid) } ?? false }
        }
    }

    /// Whether the Space is a display's current one.
    func isVisible(_ space: UInt64) -> Bool {
        displays.displays.contains { $0.currentSpaceID == space }
    }

    /// Writes the tree's frames around the minimum sizes windows have shown, then lets the applier raise
    /// overlapping windows (accordion, fullscreen) into the tree's stacking, with its focused window on top.
    /// Nothing is activated: the tree follows macOS's focus (`syncFocus`) and commands that choose a window
    /// focus it themselves, so a pass, which may have started before the latest focus change, must not.
    /// Minimum sizes found in a pass are laid out around all at once, when that moves anything. While a drag makes
    /// room on the Space, its tree is laid out as the drop shown leaves it, and the windows the drag has are not
    /// written, but for one it takes from here to another display, which waits in its tile here (Drag.swift).
    private func apply(_ key: UInt64) {
        // Fingers just let go of the strip, its windows moving at their speed: through Dock (true) or their own
        // (false).
        let fling = flung.removeValue(forKey: key)
        let shownByDrag = dragShows(key), frozen = dragFrozen
        let waiting = shownByDrag == nil ? [:] : dragWaiting(on: key)
        guard var workspace = shownByDrag ?? workspaces[key] else { return }
        workspace.minimumSizes = minimumSizes(in: workspace)
        workspace.observedWidths = observedWidths(in: workspace)
        // A band left under a quarter of the screen, as by a pinned window's minimum learned since, takes the room from
        // the pins; a wide band window narrows none: it hangs under them.
        workspace.fitBand()
        // Pushing, a fullscreen window fills where macOS's own Fill puts it, over its neighbours' peeks, when that is
        // the area inside the outer gaps: the system can then animate it there itself (see SystemTiling).
        // Not with a column pinned: Fill would cover it.
        if let display = displays.display(containingSpace: key) {
            workspace.pushedFullscreenFills = animates && workspace.pinnedWindows.isEmpty
                && SystemTiling.fillFrame(on: display).isClose(to: workspace.gaps.inset(workspace.bounds), within: 1)
        }
        if shownByDrag == nil { workspaces[key] = workspace }
        // A window the system is still filling or putting back shows as where it is going, whatever the tree says by
        // now: the others are laid out around that, so none runs off the other way, and the pass after it lands takes
        // it on to what the tree says (see SystemTiling).
        for (id, tiling) in systemTiling where workspace.contains(id) {
            workspace = workspace.showing(id, fullscreen: tiling.filling)
        }
        var layout = workspace.layout()
        for (id, frame) in waiting {
            layout.frames[id] = frame
            layout.order.append(id)
        }
        if workspace.isScrolling, shownByDrag == nil {
            telemetry.pass(key, workspace, layout)
            checkStrip(key)
        }
        // A scripting-addition glide heading for this layout carries on. One heading elsewhere is taken over, from where
        // its windows show now, by this pass's own scripting-addition glide, so a scroll taken further or turned back
        // part way goes on from there rather than jumping; before anything else, `settleGlide` clears its transforms, so
        // the windows show at the real frames this pass is about to write.
        // Only one that wrote the same windows: a window a drag held out of it, released now, is written by this pass, and
        // from where it really is, not where that glide had it.
        var supersededGlide: [WindowID]?
        if let sa = saGlides[key] {
            if sa.carry.carriesOn(into: layout, frozen: frozen) { return }
            saGlides[key] = nil
            supersededGlide = sa.ids.filter { !sa.carry.frozen.contains($0) || frozen.contains($0) }
        }
        func settleGlide() {
            guard let ids = supersededGlide else { return }
            supersededGlide = nil
            ScriptingAddition.reset(ids)
            animator.stop(key)
        }
        // Windows taking their whole fullscreen frames before the strip glides to this layout carry on; for another
        // layout, this pass takes them from wherever they have got to.
        if let push = pushes[key] {
            if push.carry.carriesOn(into: layout, frozen: frozen) { return settleGlide() }
            pushes[key] = nil
        }
        // Not the windows a drag has: written, they would be taken from the user, or from the display they wait on.
        let pids = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in
            frozen.contains(id) && waiting[id] == nil ? nil : model.windows[id].map { (id, $0.pid) }
        })
        // Windows shown fullscreen over the strip. A strip that pushes has only its pinned ones: its others are part of
        // it, and a pinned column has no place in the band to widen.
        let overPins = Set(workspace.fullscreenWindows.filter { workspace.pinSide(of: $0) != nil })
        let fullscreen = workspace.pushesFullscreen ? overPins : Set(workspace.fullscreenWindows)
        // Windows filling their widened columns, pushing their neighbours off.
        let pushed: Set<WindowID> = workspace.pushesFullscreen ? Set(workspace.fullscreenWindows).subtracting(overPins) : []
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
        // - Any other keeps to resizing as it glides, as does one whose app is not answering, which would hold it up.
        // Read where the window server has them: just after a glide the window model can be a move or two behind. A
        // window counts as coming back until it has its size.
        let frameOf = { [self] (id: WindowID) -> CGRect? in serverFrame(id) ?? model.windows[id]?.frame }
        let edge = display.map { $0.visibleArea.maxX < $0.frame.maxX - 0.5 ? $0.visibleArea.maxX : $0.frame.maxX } ?? 0
        let dock = display.map { $0.visibleArea.maxX < $0.frame.maxX - 0.5 } ?? false
        // A right pin is a wall to the band's windows: one growing to the left must not reach past the screen edge under
        // it, nor be staged over it. Not to one shown fullscreen over the strip, the pins too, nor coming back from it.
        let fullscreenNow = Set(workspace.fullscreenWindows), wasFullscreen = lastFullscreen[key] ?? []
        let shownOver = workspace.pushesFullscreen ? [] : fullscreenNow.union(wasFullscreen)
        let rightPin = workspace.pinFrame(.right)
        let besidePin = { (id: WindowID) in rightPin != nil && workspace.pinSide(of: id) == nil && !shownOver.contains(id) }
        // The focused window going fullscreen where macOS's own Fill puts it, or coming back to where Fill took it from,
        // is left to the system's tiling, whose app animates its whole frame on every step (see SystemTiling); this pass,
        // and those until it lands, leave it alone. Columns it pushes follow it as the window server shows it.
        var systemTiles: [WindowID: String] = [:]
        let focusedNow = dinky_border_focused_window()
        // Only once the tree has caught up with macOS's focus, as after a focus command it has not yet: the menu item
        // acts on the app's key window. Not for an app that is not answering.
        if animates, let display, systemTiling[focusedNow] == nil, workspace.focused == focusedNow,
           let target = layout.frames[focusedNow], let pid = pids[focusedNow], !applier.isBusy(pid),
           let current = frameOf(focusedNow) {
            let fill = SystemTiling.fillFrame(on: display)
            // Not Fill with a column pinned, which it would cover; putting a window back from it goes on all the same.
            if workspace.pinnedWindows.isEmpty, fullscreenNow.contains(focusedNow), !wasFullscreen.contains(focusedNow),
               target.isClose(to: fill, within: 1),
               !current.isClose(to: fill, within: 1) {
                systemTiles[focusedNow] = SystemTiling.fill
            } else if !fullscreenNow.contains(focusedNow), systemTiled.contains(focusedNow) {
                // Even where the tree has it somewhere else than Fill took it from, or long after it lost fullscreen to
                // another window being focused: left tiled, Mission Control would take it back over the strip.
                systemTiles[focusedNow] = SystemTiling.untile
            }
        }
        let leftAlone = Set(systemTiling.keys).intersection(layout.order).union(systemTiles.keys)
        enum Change { case once, whole, none }
        let change = { [self] (id: WindowID, pushing: Bool) -> Change in
            guard !frozen.contains(id), !leftAlone.contains(id), display != nil, let target = layout.frames[id],
                  let window = model.windows[id],
                  let frame = frameOf(id), !applier.isBusy(window.pid), !animator.rests(id, at: frame, askedFor: target),
                  ResizeOnce.resizes(frame, target) else { return .none }
            let fits = (strip[id] == nil || workspace.isInView(id) && workspace.columns(around: id).own.count == 1)
                && ResizeOnce.applies(from: frame, to: target,
                                      edge: besidePin(id) ? rightPin!.minX - workspace.gaps.horizontal : edge,
                                      wall: workspace.walls.contains(.right) || besidePin(id), dock: dock)
            if fits, pushing || ResizeOnce.movesAndResizes(frame, target) { return .once }
            return pushing ? .whole : .none
        }
        let grows = { (id: WindowID) -> Bool in
            guard let frame = frameOf(id), let target = layout.frames[id] else { return false }
            return ResizeOnce.grows(frame, target)
        }
        let growsLeft = { (id: WindowID) -> Bool in
            guard let frame = frameOf(id), let target = layout.frames[id] else { return false }
            return ResizeOnce.growsLeft(frame, target) && !workspace.walls.contains(.right) && !dock && !besidePin(id)
        }
        let changing = Dictionary(uniqueKeysWithValues: fullscreenNow.map { ($0, change($0, pushed.contains($0))) })
        let leavingChange = Dictionary(uniqueKeysWithValues: wasFullscreen.subtracting(fullscreenNow).map {
            ($0, change($0, workspace.pushesFullscreen && strip[$0] != nil && workspace.pinSide(of: $0) == nil))
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
        // Windows left to the system are stacked with the rest but not written.
        let writable = pids.filter { !leftAlone.contains($0.key) }
        let writeThen = { [weak self] (landed: @escaping () -> Void) in
            guard let self else { return }
            applier.apply(layout, pids: writable, front: workspace.focused) { [weak self] results in
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
                    if let workspace = self.workspaces[key] { self.telemetry.landed(key, workspace, results) }
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
        // One the system is tiling counts as where the system is taking it, so the pass after it lands puts it back, or
        // fills it again, through the system too, when the tree has changed its mind meanwhile.
        lastFullscreen[key] = fullscreenNow.union(leavingAll)
        for id in leftAlone {
            let filling = systemTiles[id].map { $0 == SystemTiling.fill } ?? systemTiling[id]?.filling ?? false
            if filling { lastFullscreen[key]?.insert(id) } else { lastFullscreen[key]?.remove(id) }
        }
        notePeeks(key, frames: layout.frames, strip: strip, fullscreen: fullscreen)
        if !systemTiles.isEmpty { settleGlide() }
        for id in wasFullscreen.subtracting(fullscreenNow) where !leftAlone.contains(id) { systemFilled[id] = nil }
        for (id, identifier) in systemTiles {
            guard let pid = pids[id], let start = frameOf(id) else { continue }
            tileBySystem(id, identifier, pid: pid, from: start) { [weak self] tiled in
                guard let self else { return }
                // Not put back after all: still fullscreen as it was, to come back as dinky does it, and not offered
                // to the system again.
                if !tiled, identifier == SystemTiling.untile {
                    lastFullscreen[key]?.insert(id)
                    systemFilled[id] = nil
                }
                dirty.insert(key)
                if let space = placements[id]?.space { dirty.insert(space) }
                flush()
            }
        }
        // Placed at once, a strip is snapped to once: animations off, it is placed at once anyway, and must not stay held
        // to snap, which stops the fingers taking hold of it.
        let snapped = snap.remove(key) != nil
        guard animates, !snapped else {
            settleGlide()
            return write()
        }
        // Stacking first, so the window coming to the front of an accordion slides in on top. A band window whose glide
        // sweeps under a pin, from where it is now to where it goes, has the pin raised over it before it slides beneath,
        // not once it ends there.
        // Those this raises go in front of the pins too, so they count as in front of them already.
        let pinFrames = workspace.pinnedWindows.compactMap { id in layout.frames[id].map { (id, $0) } }
        // The window list read once, for what this pass raises and for the pins it sweeps under.
        let shownStack = pinFrames.isEmpty ? nil : onScreenStack()
        let raising = shownStack.map { Set(layout.raises(current: $0.map(\.id))) } ?? []
        applier.raiseIntoOrder(layout, pids: pids, front: workspace.focused)
        var sweeping: [WindowID: Set<WindowID>] = [:]
        for (id, target) in layout.frames where workspace.pinSide(of: id) == nil {
            guard let now = model.windows[id]?.frame else { continue }
            for (pin, frame) in pinFrames where frame.intersects(now.union(target)) { sweeping[pin, default: []].insert(id) }
        }
        if !sweeping.isEmpty { raiseCoveredPins(in: key, sweeping: sweeping, raising: raising, stack: shownStack) }
        let sized = staged.union(shrinkOnce), special = sized.union(held).union(growLeft)
        // Where the window server has those changing size, or that just went fullscreen or came back, which the system's
        // own tiling can have moved without the window model hearing of it yet.
        let frameNow = { [self] (id: WindowID) -> CGRect? in
            special.contains(id) || fullscreenNow.contains(id) || wasFullscreen.contains(id) ? frameOf(id) : model.windows[id]?.frame
        }
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
            settleGlide()
            // Windows the fingers moved through Dock ride the follow's entries in unparked strip coordinates, which have
            // no place in a tree: those are dropped, and the windows set out from where the window server shows them.
            if fling == true { animator.stop(key) }
            let startOf = fling == true ? frameOf : frameNow
            let starts = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in
                frozen.contains(id) || leftAlone.contains(id) ? nil : startOf(id).map { (id, $0) }
            })
            var targets = layout.frames.filter { !leftAlone.contains($0.key) }
            hold(&targets, from: starts)
            applier.assume(starts.filter { special.contains($0.key) }.mapValues(\.size), pids: pids)
            animator.animate(key, from: starts, to: targets, pids: pids, slower: drawn, anchors: anchors(to: targets),
                             then: write)
        }

        /// Glides the strip to `layout`.
        func glideStrip() {
            var starts = Dictionary(uniqueKeysWithValues: layout.order.compactMap { id in
                frozen.contains(id) || leftAlone.contains(id) ? nil : frameNow(id).map { (id, $0) }
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
                // One still gliding, through its Dock transform or its real frame, starts where its steps have it now,
                // and one resting in a scripting-addition glide this pass takes over where its transform shows it.
                if let start = starts[id], let was = previous?.strip[id], let placed = previous?.placed[id],
                   !(previous?.fullscreen.contains(id) ?? false),
                   animator.isAnimating(id) || supersededGlide?.contains(id) == true
                    || animator.rests(id, at: start, askedFor: placed) {
                    starts[id] = special.contains(id) ? CGRect(origin: was.origin, size: start.size)
                        : animator.frame(of: id) ?? was
                }
            }
            for id in leftAlone { targets[id] = nil }
            hold(&targets, from: starts)
            var restart: Set<WindowID> = []
            // A long scroll glides about a screen's width, past none of the columns between (see ScrollShortcut.swift);
            // not with a window changing size, dragged, shown over the strip or left to the system, nor one the fingers
            // let go of, whose windows carry on from where they are at the speed they had.
            if fling == nil, special.isEmpty, fullscreen.isEmpty, frozen.allSatisfy({ strip[$0] == nil }),
               !leftAlone.contains(where: { strip[$0] != nil }),
               let shortcut = workspace.scrollShortcut(from: starts, to: targets) {
                restart = Set(shortcut.starts.filter { starts[$0.key] != $0.value }.keys)
                starts = shortcut.starts
                targets = shortcut.targets
            }
            // Nothing of the strip to glide, as on arriving at a Space: written at once. Not while a glide is under way,
            // which this pass takes over and finishes before its write.
            let anyMoves = targets.contains { id, target in
                guard let start = starts[id] else { return false }
                return !start.isClose(to: target, within: 1) && !animator.rests(id, at: start, askedFor: target)
            }
            guard anyMoves || strip.keys.contains(where: animator.isAnimating) else {
                settleGlide()
                // A glide of the tree still under way here steps only windows that have left it, as one moved to
                // another display: it would go on moving them on the old one and, at its end, write the old layout
                // over this one. Stopped first, as a glide this pass takes over is.
                if animator.isGliding(key) { animator.stop(key) }
                return write()
            }
            // A long scroll takes longer, a little more for each column it passes, so a window an app is slow to move
            // falls less far behind the others in a frame. Only how far those in view at either end go counts. Not one
            // the fingers let go of: its windows carry on on the configured spring, whatever the curve, at their speed.
            let screen = workspace.bounds
            let shows = { (r: CGRect) in r.maxX > screen.minX && r.minX < screen.maxX }
            let moved = strip.keys.compactMap { id -> CGFloat? in
                guard let start = starts[id], let target = targets[id], shows(start) || shows(target) else { return nil }
                return abs(target.minX - start.minX)
            }.max() ?? 0
            let column = max(workspace.bounds.width * CGFloat(workspace.columnWidth), 1)
            let base = Double(config.animations.durationMs) / 1000
            let stretch = fling != nil ? 1 : AnimationCurve.stripStretch(base: base, columns: Double(moved / column))
            let curve = fling.map { _ in animator.releaseCurve }
            applier.assume(Dictionary(uniqueKeysWithValues: strip.keys.compactMap { id in
                frozen.contains(id) ? nil : frameNow(id).map { (id, $0.size) }
            }), pids: pids)
            // Where the strip's windows that are not gliding are now: where the last pass put them. Parking follows the
            // columns in front, so one of them can still have to move while the others glide.
            let resting = (previous?.placed ?? [:]).filter { id, _ in
                strip[id] != nil && !frozen.contains(id) && !fullscreen.contains(id) && !leftAlone.contains(id)
            }
            // A window not resizing as it glides and the columns beside it move together, and each move of theirs is a
            // move only, which apps keep up with; but one can take a frame or two longer over a move now and then, just
            // after a resize most of all, so on every frame the one moving away from the other is held at the other's edge
            // as the window server shows it. A gap of the inner gap, the nudge and a point is let be. Only a window in
            // view with its column to itself, where strip and screen agree.
            let leads = special.filter { id in
                strip[id] != nil && !fullscreen.contains(id) && workspace.pinSide(of: id) == nil && workspace.isInView(id)
                    && workspace.columns(around: id).own.count == 1
            }.map { ($0, workspace.columns(around: $0)) }
            let guardGap = workspace.gaps.horizontal + ResizeOnce.nudge + 1
            // A window the system is tiling, pushing the columns beside it: they are held at its edges as the window
            // server shows it, the same way, though nothing of dinky's moves it.
            let systemLeads = leftAlone.filter { id in
                strip[id] != nil && !fullscreen.contains(id) && workspace.pinSide(of: id) == nil && workspace.isInView(id)
                    && workspace.columns(around: id).own.count == 1
            }.map { ($0, workspace.columns(around: $0)) }
            let shown = { (id: WindowID) -> CGRect? in serverFrame(id) }
            let place = { (frames: [WindowID: CGRect]) -> [WindowID: CGRect] in
                var input = strip
                for (id, frame) in frames where !fullscreen.contains(id) { input[id] = frame }
                for (lead, beside) in leads {
                    input = ResizeOnce.guarded(input, lead: lead, left: beside.left, right: beside.right, gap: guardGap,
                                               anchored: growLeft.contains(lead), shown: shown)
                }
                for (lead, beside) in systemLeads {
                    guard let frame = shown(lead) else { continue }
                    input[lead] = frame
                    input = ResizeOnce.guarded(input, lead: lead, left: beside.left, right: beside.right, gap: guardGap,
                                               shown: { $0 == lead ? frame : shown($0) })
                }
                var placed = workspace.placeStrip(input)
                // Placed as the guard has it: hanging past the screen edge at its size, such a window is no window
                // scrolled out to be parked. Not past a wall, though: one coming back into view from behind the column
                // at a wall starts where the strip had it, off the screen, which there is on the other display, and
                // macOS would take it to that display's Space.
                for (lead, _) in leads where input[lead] != nil { placed[lead] = workspace.keptOffWalls(input[lead]!) }
                for id in fullscreen where frames[id] != nil { placed[id] = frames[id] }
                return placed
            }
            // With the scripting addition, the strip glides by moving the real windows through Dock's connection each
            // frame: no snapshots, no Screen Recording, no app falling behind the others, and windows slide past the
            // screen edges that Accessibility clamps. Their apps are not told, so the frames go through Accessibility
            // once the glide ends, and find the windows where they put them. Every strip window is placed every frame,
            // the moving ones over the resting ones. With a payload from before Dock could move them, they are shown
            // through Dock transforms instead, the real frames going to their places underneath at once and the
            // transforms clearing once the glide ends and those frames have landed.
            // Dock only moves windows, and its transforms only translate, so a window whose size also changes this pass
            // (restoring from a filled or enlarged state, a column width change) must resize through Accessibility,
            // where its app re-renders, rather than be stretched by a transform; such a pass is left to the window
            // glide below. So is one with a window staged at its size just now, or held. Its size here is the one the
            // pass gives it, not the strip's: a window hiding behind a column at a wall is smaller than its tile, and
            // stays so while it hides.
            // Not a window a drag has, which is not written: its size, as one dragged in from another display at its own,
            // does not keep the others from gliding through Dock.
            let saResizing = !special.isEmpty || leftAlone.contains(where: { strip[$0] != nil }) || strip.contains { id, frame in
                guard !frozen.contains(id), let size = frameNow(id)?.size else { return false }
                let target = layout.frames[id] ?? frame
                return abs(size.width - target.width) > 1 || abs(size.height - target.height) > 1
            }
            // Fingers that moved the windows through Accessibility hand them on to the window glide below, at their
            // speed.
            if fullscreen.isEmpty, !saResizing, fling != false, ScriptingAddition.available {
                let stripIDs = Array(strip.keys)
                // The glide this pass takes over carries on into it: its windows keep their steps, and their transforms if
                // they have them, and head for the new targets from there. One it moved that is no longer in the strip
                // goes back to its real frame.
                if let ids = supersededGlide {
                    supersededGlide = nil
                    ScriptingAddition.reset(ids.filter { strip[$0] == nil })
                }
                saGlideTokens += 1
                let token = saGlideTokens
                saGlides[key] = (token, stripIDs, GlideCarry(layout: layout, frozen: frozen))
                let saGlide = SAGlide { [weak self] in self?.endSAGlide(key, token) }
                // Parked on every frame, as the window glide below is: a column scrolled out stays at the edge with its
                // sliver showing rather than leaving the screen, and one coming in slides out from there, in view all the
                // way. The last frame is where the real frames are written, so writing them, or clearing the transforms,
                // moves nothing.
                var initial: [WindowID: CGRect] = [:]
                for id in stripIDs { initial[id] = starts[id] ?? strip[id] }
                // Not the windows a drag has, which are the user's to move, or wait on another display.
                let unfrozen = { (frames: [WindowID: CGRect]) in frames.filter { !frozen.contains($0.key) } }
                guard ScriptingAddition.moves else {
                    ScriptingAddition.transform(unfrozen(place(initial)))
                    writeThen { saGlide.framesLanded() }
                    return animator.animate(key, from: starts, to: targets, pids: pids, stretch: stretch, restart: restart,
                                            curve: curve, sink: { ScriptingAddition.transform(unfrozen(place($0))) }) {
                        saGlide.glideEnded()
                    }
                }
                let slide = { (frames: [WindowID: CGRect]) in ScriptingAddition.move(unfrozen(place(frames))) }
                ScriptingAddition.forget(stripIDs)
                slide(initial)
                return animator.animate(key, from: starts, to: targets, pids: pids, stretch: stretch, restart: restart,
                                        curve: curve, sink: slide) { [weak self] in
                    // Taken over by a newer pass, which writes its own frames.
                    guard self?.saGlides[key]?.token == token else { return }
                    writeThen { saGlide.framesLanded() }
                    saGlide.glideEnded()
                }
            }
            settleGlide()
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
            // A right pin growing to the left is drawn out as slowly, and so are the band's columns it pushes.
            for pin in growLeft where workspace.pinSide(of: pin) == .right {
                for id in workspace.columns(around: pin).left.joined() { slower[id] = ResizeOnce.drawn }
            }
            // The columns a window going fullscreen through the system pushes off take longer than its animation, so
            // they never get ahead of it and finish where it shows: they follow it, under it.
            let followers = max(SystemTiling.followTime * 1000 / Double(max(config.animations.durationMs, 1)), 1)
            for (lead, beside) in systemLeads where fullscreenNow.contains(lead) {
                for id in (beside.left + beside.right).joined() { slower[id] = followers }
            }
            return animator.animate(key, from: starts, to: targets, pids: pids, place: place, resting: resting,
                                    stretch: stretch, slower: slower, anchors: anchors(to: targets), restart: restart,
                                    curve: curve, then: write)
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
        settleGlide()
        animator.stop(key)
        pushTokens += 1
        let token = pushTokens
        pushes[key] = (token, GlideCarry(layout: layout, frozen: dragFrozen))
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
                guard let got = settled[id], let shown = serverFrame(id) else { return true }
                return ResizeOnce.shows(shown, staging: frame) || shown.isClose(to: got, within: 2)
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
    func observedWidths(in workspace: Workspace) -> [WindowID: CGFloat] {
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
    /// ResizeOnce): growing, it takes its whole size first; shrinking, it takes its new size once there; and one filling
    /// the display where macOS's Fill does, or coming back to where Fill took it from, is left to the system's tiling,
    /// unless `bySystem` is false (see SystemTiling).
    func placeFloating(_ id: WindowID, at frame: CGRect, resizingOnce: Bool = false, bySystem: Bool = true) {
        guard let window = model.windows[id] else { return }
        floatingTargets[id] = frame
        // The system is moving it: placed once it has landed (see `tileBySystem`).
        if systemTiling[id] != nil { return }
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
        let start = serverFrame(id) ?? window.frame
        let display = displays.display(ofWindow: id)
        let dock = display.map { $0.visibleArea.maxX < $0.frame.maxX - 0.5 } ?? false
        let edge = display.map { dock ? $0.visibleArea.maxX : $0.frame.maxX } ?? 0
        if resizingOnce, bySystem, let display, dinky_border_focused_window() == id, !applier.isBusy(window.pid),
           !animator.isAnimating(id) {
            let fill = SystemTiling.fillFrame(on: display)
            let identifier = frame.isClose(to: fill, within: 1) && !start.isClose(to: fill, within: 1) ? SystemTiling.fill
                : systemFilled[id].map { frame.isClose(to: $0, within: 2) } == true ? SystemTiling.untile : nil
            if let identifier {
                animator.stop(key)
                return tileBySystem(id, identifier, pid: window.pid, from: start) { [weak self] tiled in
                    guard let self, placements[id]?.floating == true, let latest = floatingTargets[id] else { return }
                    if !tiled, identifier == SystemTiling.untile { systemFilled[id] = nil }
                    // Placed meanwhile somewhere else: there now, through the system again where it can.
                    if latest != frame { return placeFloating(id, at: latest, resizingOnce: true) }
                    tiled ? write() : placeFloating(id, at: frame, resizingOnce: true, bySystem: false)
                }
            }
        }
        if resizingOnce { systemFilled[id] = nil }
        guard resizingOnce, ResizeOnce.movesAndResizes(start, frame), !applier.isBusy(window.pid), let display,
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
        pushes[key] = (token, GlideCarry(layout: layout, frozen: dragFrozen))
        let staging = ResizeOnce.staging(from: start, to: frame, edge: edge)
        stage([id: staging], token: token, order: [id], front: id, pids: pids,
              live: { [weak self] in self?.pushes[key]?.token == token }) { [weak self] in
            guard let self else { return }
            pushes[key] = nil
            guard placements[id]?.floating == true, model.windows[id] != nil else { return }
            let staged = serverFrame(id) ?? staging
            applier.assume([id: staged.size], pids: pids)
            animator.animate(key, from: [id: staged], to: [id: ResizeOnce.glideTarget(frame, size: staged.size)],
                             pids: pids, then: write)
        }
    }

    /// Leaves a window to macOS's own tiling (see SystemTiling): presses `identifier` for it, then watches the window
    /// server until it has moved and stopped, and runs `landed` with true, to lay it out as usual and put right the point
    /// or so the system's frame can be off. Meanwhile it counts as gliding and passes leave it alone. An app that does not
    /// take the press, or a window that does not set off, runs `landed` with false, to glide it as dinky does.
    private func tileBySystem(_ id: WindowID, _ identifier: String, pid: pid_t, from start: CGRect,
                              landed: @escaping (Bool) -> Void) {
        systemTilingTokens += 1
        let token = systemTilingTokens
        systemTiling[id] = (token, identifier == SystemTiling.fill, false)
        // Tried once: a window whose app does not take it is most likely not tiled at all.
        if identifier == SystemTiling.untile { systemTiled.remove(id) }
        let live = { [weak self] in self?.systemTiling[id]?.token == token && self?.enabled == true }
        // An app too slow to take the press in time is left to dinky; should it act on it late, its own animation still
        // ends where dinky puts the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, systemTiling[id]?.token == token, systemTiling[id]?.pressed == false else { return }
            systemTiling[id] = nil
            landed(false)
        }
        tiler.press(identifier, pid: pid, window: id) { [weak self] pressed in
            guard let self, live() else { return }
            guard pressed else {
                systemTiling[id] = nil
                return landed(false)
            }
            systemTiling[id]?.pressed = true
            systemFilled[id] = identifier == SystemTiling.fill ? start : nil
            if identifier == SystemTiling.fill { systemTiled.insert(id) }
            // From where it is now: a step of a glide it was in can have landed since.
            let began = CACurrentMediaTime()
            let from = serverFrame(id) ?? start
            var last = from, since = began
            func check() {
                guard live() else { return }
                let seen = serverFrame(id), now = CACurrentMediaTime()
                if let seen, seen != last { last = seen; since = now }
                let moved = !last.isClose(to: from, within: 1), still = now - since
                // Still for a while once it has moved for about as long as the system's animation takes: it can pause
                // near the end before its last frame, which would land over a frame written sooner, and an app busy
                // with a step can pause in the middle. Or never set off; or gone, or so long that something else has it.
                let done = moved && still > 0.15 && now - began > 0.35 || !moved && now - began > 1
                    || seen == nil || now - began > 2.5
                guard done else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120) { check() }
                    return
                }
                systemTiling[id] = nil
                if !moved, identifier == SystemTiling.fill {
                    systemFilled[id] = nil
                    systemTiled.remove(id)
                }
                landed(moved)
            }
            check()
        }
    }

    /// Stops a floating window's staging for a glide, as when it stops floating: the glide is no longer its to take.
    func endFloatingStage(_ id: WindowID) {
        pushes[Self.floatingKey(id)] = nil
    }

    /// Where a floating window is, or where it is gliding to.
    func floatingFrame(of id: WindowID) -> CGRect? {
        if isAnimating(id), let target = floatingTargets[id] { return target }
        return serverFrame(id) ?? model.windows[id]?.frame
    }

    /// The animator's key for one floating window's glide, apart from every Space ID, which keys a tree's.
    private static func floatingKey(_ id: WindowID) -> UInt64 { 1 << 63 | UInt64(id) }

    /// Whether passes glide windows to their tiles.
    var animates: Bool {
        config.animations.enabled && config.animations.durationMs > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Whether dinky is gliding the window to its tile right now.
    func isAnimating(_ id: WindowID) -> Bool {
        animator.isAnimating(id) || stagingWindows[id] != nil || systemTiling[id] != nil
    }

    /// The windows dinky is gliding to their tiles right now.
    var animatingWindows: [WindowID] { animator.animating }

    func minimumSizes(in workspace: Workspace) -> [WindowID: CGSize] {
        var sizes: [WindowID: CGSize] = [:]
        for id in workspace.windows { sizes[id] = applier.minimumSize(of: id, app: model.windows[id]?.bundleID) }
        return sizes
    }

    /// A tiled window seen smaller than the minimum it is laid out around, wholly on one display, shows that minimum
    /// was wrong: it is lowered to what the window went to. Laid out around it, the window is never asked for less, so
    /// only a size it went to some other way, as making room for a drag, shows it.
    private func noteSize(of id: WindowID) {
        guard placements[id]?.floating == false, let window = model.windows[id], !window.isMinimized,
              let minimum = applier.minimumSize(of: id, app: window.bundleID),
              window.frame.width < minimum.width - 2 || window.frame.height < minimum.height - 2,
              FrameApplier.isOnScreen(window.frame),
              applier.saw(window.frame.size, of: id, app: window.bundleID) else { return }
        print("\(stamp()) \(id) \(window.appName ?? "?") at \(window.frame.size), under the minimum \(minimum) it was laid out around: lowered")
        dirty.formUnion(placements[id]?.space.map { [$0] } ?? [])
    }
}
