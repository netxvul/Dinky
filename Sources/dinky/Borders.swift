import AppKit
import DinkyConfig
import DinkyPrivate

// din-nt98: focus borders. One BorderWindow per document window on a visible Space; the
// focused window's border gets the active colour, the rest the inactive one (JankyBorders'
// behaviour).
//
// The owner feeds it the WindowModel's events through handle(_:). Events only record what needs doing;
// one flush per run-loop turn does it, in a fixed order: the focus check first, so every border is drawn
// with the current focus, then the borders of the windows that changed (or all of them).
final class BorderManager {
    private var config: Borders
    private let model: WindowModel
    private var borders: [UInt32: BorderWindow] = [:]
    private var focusedID: UInt32 = 0
    private var visibleSpaces: Set<UInt64> = []
    /// What the next flush does: check focus, place every border, or place the borders of these windows.
    private var pending = (refocus: false, all: false, ids: Set<UInt32>())
    private var flushScheduled = false
    /// The window whose border is flashing, and whether the flash is lit now.
    private var flashed: (id: UInt32, lit: Bool)?
    private let flasher = BorderFlash()
    /// Whether dinky is animating the window, when its border only follows moves: redrawing it at every
    /// size of a resize costs more than a frame.
    private let isAnimating: (UInt32) -> Bool

    init(config: Borders, model: WindowModel, isAnimating: @escaping (UInt32) -> Bool) {
        self.config = config
        self.model = model
        self.isAnimating = isAnimating
        refreshSpaces()
        focusedID = dinky_border_focused_window()
        syncAll()
        // An active colour of 'accent' follows the accent colour as it changes in System Settings.
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.config.activeColor == .accent { self?.syncAll() }
        }
    }

    func update(config: Borders) {
        guard config != self.config else { return }
        self.config = config
        syncAll()
    }

    /// Whether a window id is one of the border windows dinky draws.
    func isBorder(_ id: UInt32) -> Bool { borders.values.contains { $0.id == id } }

    func handle(_ event: WindowEvent) {
        switch event.kind {
        case .spaceChange, .spaceCreated, .spaceDestroyed:
            refreshSpaces()
            pending.refocus = true
            pending.all = true
        case .frontApp:
            pending.refocus = true
            // The new app's front window can settle a few ms after the app (JankyBorders waits 20 ms).
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in self?.refocus() }
        case .windowReorder:
            pending.refocus = true
            // A click between one app's windows can report the previous one in front for a few ms.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in self?.refocus() }
        case .windowUpdate, .windowCreate, .windowDestroy, .windowTitle:
            pending.refocus = true
        default:
            break
        }

        if let window = event.window {
            if event.change == .removed {
                // Released now, not at the flush: WindowServer can reuse the id before then.
                borders[window.id] = nil
            } else if event.kind == .windowReorder {
                // A border is ordered next to its target once, so a window raised later lands on top of every
                // border below it: an app's activation, or the accordion raising its other windows, buries the
                // focused border under the windows raised after it. So any reorder places every border again.
                pending.all = true
            } else {
                // A window being animated or dragged sends a move and a resize every frame, and placing its
                // border is a WindowServer round trip, so the events of one turn share one placement.
                pending.ids.insert(window.id)
            }
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    /// Does what the events since the last flush asked for: focus first, then the borders.
    private func flush() {
        let work = pending
        pending = (refocus: false, all: false, ids: [])
        flushScheduled = false
        if work.refocus { refocus() }
        if work.all { syncAll() } else { sync(work.ids) }
    }

    /// Windows that finished animating: their borders catch up with any size they skipped.
    func arrived(_ ids: [UInt32]) { sync(ids) }

    private func sync<S: Sequence<UInt32>>(_ ids: S) {
        for id in ids { if let window = model.windows[id] { sync(window) } }
    }

    /// Flashes a window's border in `noop-flash-color`, for a binding that did nothing. Again while it flashes
    /// starts it over.
    func flash(_ id: UInt32) {
        if let old = flashed?.id, old != id {
            flashed = nil
            sync([old])
        }
        flasher.start(count: config.noopFlashCount, onMs: config.noopFlashMs) { [weak self] lit, last in
            guard let self else { return }
            self.flashed = last ? nil : (id, lit)
            self.sync([id])
        }
    }

    /// Mission Control came or went: every border hides or returns.
    func missionControlChanged() { syncAll() }

    private func syncAll() {
        for id in borders.keys where model.windows[id] == nil { borders[id] = nil }
        for window in model.windows.values { sync(window) }
    }

    private func sync(_ window: Window) {
        guard config.enabled, window.isDocument, config.decorates(bundleID: window.bundleID) else {
            borders[window.id] = nil
            return
        }
        // Minimized windows land here too (they are still documents, just not visible), so the border hides.
        guard window.isOrderedIn, window.isVisible, !window.isMinimized, visibleSpaces.contains(window.spaceID), !MissionControl.shared.active else {
            borders[window.id]?.hide()
            return
        }
        let focused = window.id == focusedID
        let lit = flashed.map { $0.id == window.id && $0.lit } ?? false
        let color = lit ? config.noopFlashColor.resolved : focused ? config.activeColor.resolved : config.inactiveColor
        let border = borders[window.id] ?? BorderWindow(target: window.id)
        borders[window.id] = border
        // Lit, it is redrawn at every size of a glide too, or a flash asked for mid-glide would not show.
        border.update(window, color: color, config: config, moveOnly: isAnimating(window.id) && !lit)
    }

    private func refocus() {
        let id = dinky_border_focused_window()
        guard id != focusedID else { return }
        let old = focusedID
        focusedID = id
        for id in [old, id] {
            if let window = model.windows[id] { sync(window) }
        }
    }

    // The current Space of every display, full-screen Spaces left out.
    private func refreshSpaces() {
        visibleSpaces = Set(dinky_displays().compactMap { display in
            let current = display.spaces.first { $0.spaceID == display.currentSpaceID }
            return current?.isFullscreen == true ? nil : display.currentSpaceID
        })
    }
}

/// The steps of a border flash: lit for `onMs`, then dark for 80 ms, `count` times. Starting again drops the steps
/// still to come, so pressing a binding again restarts the flash instead of stacking another.
final class BorderFlash {
    private static let offMs = 80
    private var generation = 0

    /// Calls `step` lit at once and at each flash after, dark at the end of each, `last` on the final one.
    func start(count: Int, onMs: Int, _ step: @escaping (_ lit: Bool, _ last: Bool) -> Void) {
        generation += 1
        let shown = generation
        func at(_ ms: Int, _ lit: Bool, _ last: Bool) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                guard self?.generation == shown else { return }
                step(lit, last)
            }
        }
        step(true, false)
        for i in 0..<count {
            let start = i * (onMs + Self.offMs)
            if i > 0 { at(start, true, false) }
            at(start + onMs, false, i == count - 1)
        }
    }
}

/// The flash for a window the border manager leaves bare: every window with `[borders] enabled = false`, and
/// `exclude-apps`' windows. A border of its own around the window for as long as it flashes, kept on the window as
/// it moves and hidden where a border would be.
final class LoneBorderFlash {
    private var border: BorderWindow?
    private var target: UInt32 = 0
    private var lit = false
    private var config = Borders()
    private let flasher = BorderFlash()

    /// Whether a window id is the flash's border.
    func isBorder(_ id: UInt32) -> Bool { id != 0 && border?.id == id }

    func flash(_ id: UInt32, config: Borders, model: WindowModel) {
        if target != id { border = nil }
        target = id
        self.config = config
        flasher.start(count: config.noopFlashCount, onMs: config.noopFlashMs) { [weak self] lit, last in
            guard let self, self.target == id else { return }
            guard !last, let window = model.windows[id] else { return self.end() }
            self.lit = lit
            self.draw(window)
        }
    }

    /// The flashed window's events: the ring follows its moves and goes with it.
    func handle(_ event: WindowEvent) {
        guard border != nil, let window = event.window, window.id == target else { return }
        if event.change == .removed { return end() }
        if [.windowMove, .windowResize].contains(event.kind) { draw(window) }
    }

    /// Mission Control came or went.
    func missionControlChanged() {
        if MissionControl.shared.active { border?.hide() }
    }

    private func draw(_ window: Window) {
        guard lit, window.isOrderedIn, window.isVisible, !window.isMinimized, !MissionControl.shared.active else {
            border?.hide()
            return
        }
        let border = self.border ?? BorderWindow(target: window.id)
        self.border = border
        border.update(window, color: config.noopFlashColor.resolved, config: config)
    }

    private func end() {
        border = nil
        target = 0
        lit = false
    }
}
