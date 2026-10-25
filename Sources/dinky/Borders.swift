import AppKit
import DinkyConfig
import DinkyLayout
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
        let color = focused ? config.activeColor.resolved : config.inactiveColor
        let border = borders[window.id] ?? BorderWindow(target: window.id)
        borders[window.id] = border
        border.update(window, color: color, config: config, moveOnly: isAnimating(window.id))
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

/// The noop flash: a glow around the window, the way the screen's edges glow while Claude uses the computer.
/// `noop-flash-color` at the window's edge, fading out over `noop-flash-spread` points outside it and half that inside,
/// drawn over the window and any border it has, breathing in and out `noop-flash-count` times. Every window gets it,
/// borders on or off, its app excluded or not; it stays on the window as it moves and hides where a border would.
/// The glow is drawn once and breathes by its window's opacity alone, so a frame of it costs one WindowServer call.
final class NoopGlow: NSObject {
    private var glow: BorderWindow?
    private var target: UInt32 = 0
    private var config = Borders()
    private var pulse = Pulse(count: 1, hold: 0)
    private var started = 0.0
    private var strength = 0.0
    private var link: CADisplayLink?

    /// Whether a window id is the glow's.
    func isBorder(_ id: UInt32) -> Bool { id != 0 && glow?.id == id }

    /// Glows around the window. Again while it glows starts it over, rising on from where it is, so a held key that
    /// repeats keeps it lit.
    func flash(_ id: UInt32, config: Borders, model: WindowModel) {
        if target != id {
            glow = nil
            setStrength(0)
        }
        target = id
        self.config = config
        pulse = Pulse(count: config.noopFlashCount, hold: Double(config.noopFlashMs) / 1000)
        let started = CACurrentMediaTime() - Pulse.rising(to: strength)
        self.started = started
        guard let window = model.windows[id] else { return end() }
        draw(window)

        link?.invalidate()
        link = (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        // A link whose screen goes away stops firing: the glow ends on time all the same.
        DispatchQueue.main.asyncAfter(deadline: .now() + pulse.duration + 0.25) { [weak self] in
            if self?.started == started { self?.end() }
        }
    }

    /// The glowing window's events: the glow follows its moves and goes with it.
    func handle(_ event: WindowEvent) {
        guard glow != nil, let window = event.window, window.id == target else { return }
        if event.change == .removed { return end() }
        if [.windowMove, .windowResize].contains(event.kind) { draw(window) }
    }

    /// Mission Control came or went.
    func missionControlChanged() {
        if MissionControl.shared.active { glow?.hide() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let strength = pulse.strength(at: link.targetTimestamp - started) else { return end() }
        setStrength(strength)
    }

    private func setStrength(_ strength: Double) {
        self.strength = strength
        glow?.setAlpha(strength)
    }

    private func draw(_ window: Window) {
        guard window.isOrderedIn, window.isVisible, !window.isMinimized, !MissionControl.shared.active else {
            glow?.hide()
            return
        }
        let glow = self.glow ?? BorderWindow(target: window.id)
        self.glow = glow
        // A new glow window starts out opaque: it takes the breath where it is before it shows.
        glow.setAlpha(strength)
        glow.glow(window, color: config.noopFlashColor.resolved, spread: config.noopFlashSpread)
    }

    private func end() {
        link?.invalidate()
        link = nil
        glow = nil
        target = 0
        started = 0
        strength = 0
    }
}
