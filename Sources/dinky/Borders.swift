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

    /// The border shown directly above a window, with `order = 'above'`: what is drawn over the window goes above it.
    func border(above id: UInt32) -> UInt32? {
        guard config.order == .above, let border = borders[id], border.isShown, border.id != 0 else { return nil }
        return border.id
    }

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

/// The noop flash: the window's edge breathes in `noop-flash-color`, the way the screen's edges breathe while Claude uses
/// the computer. A `noop-flash-width` ring around the window and six bands inside it, reaching `noop-flash-spread` points
/// in, brighten and dim at an uneven pace (Breathing), `noop-flash-count` times for a press and on for as long as a held
/// key repeats. Every window gets it, borders on or off, its app excluded or not. It is drawn over the window and its
/// border and follows it, and goes as soon as the window closes, hides or minimizes, the Space changes or Mission Control
/// opens.
final class NoopGlow: NSObject {
    /// The window's border drawn directly above it, if any, which the glow goes above.
    private let borderAbove: (UInt32) -> UInt32?
    private var glow: BorderWindow?
    /// The glowing window as last seen.
    private var window: Window?
    private var config = Borders()
    private var breathing: Breathing?
    private var state = Breathing.State(level: 1, presence: 0)
    /// The glow needs placing again: its window moved or changed, or another was raised over it.
    private var needsPlace = false
    private var link: CADisplayLink?
    private var lastTick = 0.0
    /// Counts glows, so the watch of one that has gone stops.
    private var generation = 0

    init(borderAbove: @escaping (UInt32) -> UInt32?) {
        self.borderAbove = borderAbove
    }

    /// Whether a window id is the glow's.
    func isBorder(_ id: UInt32) -> Bool { id != 0 && glow?.id == id }

    /// Breathes on the window's edge. Again on the same window while it shows keeps it breathing.
    func flash(_ id: UInt32, config: Borders, model: WindowModel) {
        guard let window = model.windows[id], Self.shows(window) else { return }
        let now = CACurrentMediaTime()
        if window.id != self.window?.id { end() }
        let changed = config != self.config
        self.config = config
        self.window = window
        if breathing?.press(at: now) != true {
            breathing = Breathing(count: config.noopFlashCount, at: now)
        }
        state = breathing?.state(at: now) ?? state
        // A glow already showing takes the press at its next frame, unless it is to look different.
        if glow == nil || changed { place() }
        guard link == nil else { return }
        link = screen(containing: window.frame)?.displayLink(target: self, selector: #selector(tick))
        // A breath takes seconds: 60 frames a second are smooth, and each is a redraw.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link?.add(to: .main, forMode: .common)
        lastTick = now
        watch(generation)
    }

    /// The window events while it shows: it follows its window, stays above it and goes with it.
    func handle(_ event: WindowEvent) {
        guard glow != nil else { return }
        if event.kind == .spaceChange { return end() }
        guard let changed = event.window else { return }
        if changed.id == window?.id {
            if event.change == .removed || !Self.shows(changed) { return end() }
            window = changed
            needsPlace = true
        } else if event.kind == .windowReorder {
            // A window raised later lands above the glow and may cover it.
            needsPlace = true
        }
    }

    /// Mission Control came or went.
    func missionControlChanged() {
        if MissionControl.shared.active { end() }
    }

    /// One frame: the breath moves on, and the glow is placed again if it needs to be, or else just drawn again. Moves
    /// and resizes wait for the frame, so a glide's events cost one placement a frame, not one each.
    @objc private func tick(_ link: CADisplayLink) {
        lastTick = CACurrentMediaTime()
        guard let state = breathing?.state(at: link.targetTimestamp) else { return end() }
        self.state = state
        if needsPlace { place() } else { glow?.redraw(bands) }
    }

    /// The look now. The bands reach a quarter of the window's shorter side at most, so they never meet.
    private var bands: GlowBands {
        let size = window?.frame.size ?? .zero
        return GlowBands(spread: min(config.noopFlashSpread, Double(min(size.width, size.height)) / 4), state: state)
    }

    private func place() {
        needsPlace = false
        guard let window else { return }
        let glow = self.glow ?? BorderWindow(target: window.id)
        self.glow = glow
        glow.glow(window, color: config.noopFlashColor.resolved, width: config.noopFlashWidth, bands: bands,
                  above: borderAbove(window.id) ?? window.id)
    }

    /// A display link whose screen goes away stops firing: the glow goes all the same.
    private func watch(_ generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generation == generation else { return }
            if CACurrentMediaTime() - self.lastTick > 0.5 { self.end() } else { self.watch(generation) }
        }
    }

    private static func shows(_ window: Window) -> Bool {
        window.isOrderedIn && window.isVisible && !window.isMinimized && !MissionControl.shared.active
    }

    private func end() {
        link?.invalidate()
        link = nil
        glow = nil
        window = nil
        breathing = nil
        state = Breathing.State(level: 1, presence: 0)
        needsPlace = false
        generation += 1
    }
}
