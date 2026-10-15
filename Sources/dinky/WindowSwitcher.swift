import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// `[window-switcher]`: hold the modifier on its own over a workspace laid out by one of `layouts` and, after `delay-ms`, a
// glass capsule of the workspace's windows shows over the pointer, with the focused one under it. A row for a
// scrolling or accordion workspace, in strip or tree order, the windows of a column or a part of the root together,
// picked by moving across; for a tiles or fixed workspace, with `tiles-style = 'map'`, a map of its tiles, picked by
// moving onto one. Releasing the modifier focuses the window picked, which scrolls a strip to it. Esc closes the
// capsule without focusing anything, and so does any other key, which goes on to whatever it was for, so bindings
// that use the modifier work as before: a key or click while the modifier is held before the capsule shows calls it
// off until the modifier is released. One capsule for every workspace, filled afresh each time from the workspace
// under the pointer. The holding is `ModifierHold`'s. Main thread only.
final class WindowSwitcher {
    static let shared = WindowSwitcher()
    /// Points the pointer moves before it picks, so the focused window stays picked through a tremor.
    private static let deadZone: CGFloat = 4
    private static let rise: CGFloat = 6
    private static let fadeIn: TimeInterval = 0.14
    private static let fadeOut: TimeInterval = 0.12

    private var config = Switcher()
    private let hold = ModifierHold(name: "window-switcher")
    /// The Space whose windows the capsule shows.
    private var shownSpace: UInt64 = 0
    /// The display the capsule shows a workspace of.
    private var shownDisplay = ""
    private var observingSpaces = false
    /// Set while `show` runs, whose own reading of the displays must not start another showing.
    private var showing = false
    /// The display whose Space was still moving when the capsule was asked for, and since when: it shows once the
    /// move ends.
    private var waiting: (display: String, since: UInt64)?
    /// Watches the Spaces closely while the capsule is up or waiting, faster than the display model learns of them.
    private var watch: Timer?
    private static let watchInterval: TimeInterval = 1.0 / 60
    /// Nanoseconds a wait for a Space to land lasts before the capsule shows anyway.
    private static let longestWait: UInt64 = 1_500_000_000

    private var items: [SwitcherItem] = []
    /// How the capsule shows the windows: a row, picked across, or a map, picked in two dimensions.
    private enum Arrangement {
        case row(SwitcherLayout)
        case map(SwitcherMap)

        var size: CGSize {
            switch self {
            case .row(let row): row.size
            case .map(let map): map.size
            }
        }

        var frames: [CGRect] {
            switch self {
            case .row(let row): row.frames
            case .map(let map): map.frames
            }
        }

        /// The window at `point` in the capsule's coordinates.
        func index(at point: CGPoint) -> Int? {
            switch self {
            case .row(let row): row.index(atX: point.x)
            case .map(let map): map.index(at: point)
            }
        }
    }

    private var arrangement = Arrangement.row(SwitcherLayout(columns: [], maxWidth: 0))
    /// The capsule's top-left corner, in global coordinates with a top-left origin.
    private var origin = CGPoint.zero
    /// Where pointer moves pick from: the capsule over the pointer, though `position` shows it elsewhere.
    private var pickOrigin = CGPoint.zero
    private var startPointer = CGPoint.zero
    private var pointerMoved = false
    /// Bumped on every showing, so a fade-out that finishes after a newer showing leaves the panel up.
    private var generation = 0

    private lazy var view = SwitcherView(frame: .zero)
    private lazy var glass = GlassPanel(content: view, cornerRadius: SwitcherLayout.thumbHeight)

    init() {
        hold.show = { [unowned self] in show() }
        hold.moved = { [unowned self] in pointerMoved(to: $0) }
        hold.commit = { [unowned self] in commit() }
        hold.hide = { [unowned self] in hide() }
        hold.navigate = { [unowned self] in navigate($0) }
        hold.within = { [unowned self] in CGRect(origin: origin, size: arrangement.size).contains($0) }
        hold.vertical = { [unowned self] in
            if case .map = arrangement { return true }
            return false
        }
        hold.cycle = { [unowned self] forward in
            view.pick(SwitcherLayout.step(view.picked, count: items.count, toward: forward ? .right : .left))
        }
    }

    var isShowing: Bool { hold.isShowing }
    /// Whether the capsule, shown from the keyboard, takes this key.
    func takes(_ event: CGEvent) -> Bool { hold.takes(event) }
    /// Whether a modifier or a key binding can show the capsule, so thumbnails are worth keeping.
    private var enabled = false

    /// The `window-switcher` command: the capsule in the middle of the display under the pointer, picked with the
    /// keys. False if the workspace there has nothing to pick from.
    func showFromKeyboard() -> Bool {
        hold.showFromKeyboard()
    }

    func update(config: Config) {
        if !observingSpaces {
            observingSpaces = true
            AppState.shared.displays.observe { [weak self] _ in self?.spacesChanged() }
        }
        self.config = config.windowSwitcher
        enabled = self.config.modifier != .none || config.binds("window-switcher")
        hold.update(modifier: self.config.modifier, sides: config.modifiers, delayMs: self.config.delayMs)
    }

    /// Closes the capsule without focusing anything, as a binding that runs while it is up does.
    func dismiss() {
        hold.dismiss()
    }

    /// Captures a window that just lost focus on a workspace the switcher shows for, so its thumbnail is recent the next
    /// time the capsule shows its workspace.
    func focusLeft(_ id: WindowID) {
        guard enabled, id != 0, Thumbnails.shared.permitted,
              let coordinator = AppState.shared.coordinator,
              let workspace = coordinator.placements[id]?.space.flatMap({ coordinator.workspaces[$0] }),
              shows(for: workspace) else { return }
        Thumbnails.shared.refresh(id, scale: NSScreen.main?.backingScaleFactor ?? 2)
    }

    // MARK: The capsule

    /// Whether the workspace is laid out by one of `layouts`.
    private func shows(for workspace: Workspace) -> Bool {
        config.layouts.contains(kind(of: workspace))
    }

    private func kind(of workspace: Workspace) -> SwitcherLayoutKind {
        switch workspace.algorithm {
        case .scrolling: .scrolling
        case .dwindle(.tiles): .tiles
        case .dwindle(.accordion): .accordion
        case .fixed: .fixed
        }
    }

    /// A trackpad swipe lands its Space a moment after it looks done, so the capsule can show for the workspace being
    /// left; and the display can move to another workspace while it is up. Either way it shows the workspace the
    /// display is on now, in place, or closes when that one has nothing to pick.
    private func spacesChanged() {
        guard isShowing, !showing,
              let display = AppState.shared.displays.displays.first(where: { $0.uuid == shownDisplay }),
              display.currentSpaceID != shownSpace else { return }
        if !show() { hold.dismiss() }
    }

    /// Watches every frame while the capsule is up or waiting: shows a waiting capsule as soon as its display's Space
    /// lands, and moves a shown one to the workspace its display has landed on, without waiting for the notifications.
    private func startWatching() {
        guard watch == nil else { return }
        watch = Timer.scheduledTimer(withTimeInterval: Self.watchInterval, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if let waiting {
            guard !dinky_display_is_animating(waiting.display as CFString)
                    || uptime() - waiting.since > Self.longestWait else { return }
            self.waiting = nil
            if !show() { hold.dismiss() }
            return
        }
        guard isShowing, !shownDisplay.isEmpty else {
            watch?.invalidate()
            watch = nil
            return
        }
        let uuid = shownDisplay as CFString
        guard !dinky_display_is_animating(uuid), dinky_current_space_id(uuid) != shownSpace else { return }
        AppState.shared.displays.reconcile()
        spacesChanged()
    }

    /// Shows the capsule for the workspace under the pointer, if `layouts` has its layout and it has a tiled window, or
    /// two with `show-single` off. While the display under the pointer is still moving between Spaces, as in a trackpad swipe, it waits and
    /// shows the workspace it lands on.
    private func show() -> Bool {
        if let pointer = CGEvent(source: nil)?.location,
           let display = AppState.shared.displays.displays.first(where: { $0.frame.contains(pointer) }),
           dinky_display_is_animating(display.uuid as CFString) {
            if waiting == nil { waiting = (display.uuid, uptime()) }
            startWatching()
            return true
        }
        showing = true
        defer { showing = false }
        let app = AppState.shared
        // The display model learns of a Space change from notifications and a half-second poll, so right after a
        // switch it can still name the workspace left behind; read the displays afresh.
        app.displays.reconcile()
        guard app.enabled, !MissionControl.shared.active, !SpaceSwitcher.shared.switching,
              let coordinator = app.coordinator, let pointer = CGEvent(source: nil)?.location,
              let display = app.displays.displays.first(where: { $0.frame.contains(pointer) }),
              let workspace = coordinator.workspace(on: display), shows(for: workspace),
              let screen = screen(of: display.id) else { return false }
        let tiles = workspace.tileFrames
        let columns = workspace.root.children.map { $0.windows.filter { coordinator.model.windows[$0] != nil && tiles[$0] != nil } }
            .filter { !$0.isEmpty }
        let ids = columns.flatMap { $0 }
        guard ids.count >= (config.showSingle ? 1 : 2) else { return false }
        items = ids.map { id in
            let window = coordinator.model.windows[id]!
            let running = NSRunningApplication(processIdentifier: window.pid)
            return SwitcherItem(id: id, app: window.appName ?? running?.localizedName ?? "", icon: running?.icon)
        }
        let visible = display.visibleArea, maxWidth = (visible.width * 0.8).rounded()
        let picked = workspace.focused.flatMap { ids.firstIndex(of: $0) } ?? 0
        let mapped = config.tilesStyle == .map && [.tiles, .fixed].contains(kind(of: workspace))
        if mapped {
            let map = SwitcherMap(tiles: ids.map { tiles[$0]! }, bounds: workspace.bounds,
                                  cornerRadius: CGFloat(config.cornerRadius), maxWidth: maxWidth)
            arrangement = .map(map)
            place(map.size, visible: visible, atPointer: map.origin(anchor: picked, pointer: pointer, visible: visible))
        } else {
            let aspects = columns.map { $0.map { id -> CGFloat in
                let size = coordinator.model.windows[id]!.frame.size
                return size.height > 0 ? size.width / size.height : 1
            } }
            let row = SwitcherLayout(columns: aspects, cornerRadius: CGFloat(config.cornerRadius), maxWidth: maxWidth)
            arrangement = .row(row)
            place(row.size, visible: visible, atPointer: row.origin(anchor: picked, pointer: pointer, visible: visible))
        }
        startPointer = pointer
        pointerMoved = false

        let scale = screen.backingScaleFactor
        view.animates = animates
        view.frame = CGRect(origin: .zero, size: arrangement.size)
        view.show(items, frames: arrangement.frames, style: mapped ? .map : .row, picked: picked, scale: scale)
        present()

        Thumbnails.shared.askOnce()
        // Tall enough for the biggest cell, grown.
        let height = (arrangement.frames.map(\.height).max() ?? SwitcherLayout.thumbHeight) * 1.1
        Thumbnails.shared.refresh(ids, height: height, scale: scale) { [weak self] id, image in
            guard let self, self.isShowing else { return }
            self.view.update(id, image: image)
        }
        shownSpace = display.currentSpaceID
        shownDisplay = display.uuid
        startWatching()
        return true
    }

    /// Sets `origin` where `position` puts a capsule of `size`, `atPointer` being where it goes over the pointer.
    private func place(_ size: CGSize, visible: CGRect, atPointer: CGPoint) {
        origin = config.position.origin(size: size, visible: visible, fromKeyboard: hold.centred, atPointer: atPointer)
        // Shown by the keyboard, the pointer picks over the capsule; held, it moves the pick as if the capsule were under it.
        pickOrigin = hold.centred ? origin : atPointer
    }

    /// A key's step: across a row, round from end to end, or onto the nearest tile that way on a map.
    private func navigate(_ direction: Direction) {
        let index: Int?
        switch arrangement {
        case .row: index = SwitcherLayout.step(view.picked, count: items.count, toward: direction)
        case .map(let map): index = map.neighbor(of: view.picked, toward: direction)
        }
        guard let index, index != view.picked else { return }
        view.pick(index)
        // Felt, as a pointer's pick is, when the swiping fingers move it.
        if hold.byFingers { tapTrackpad() }
    }

    private func pointerMoved(to point: CGPoint) {
        if !pointerMoved {
            guard hypot(point.x - startPointer.x, point.y - startPointer.y) >= Self.deadZone else { return }
            pointerMoved = true
        }
        let local = CGPoint(x: point.x - pickOrigin.x, y: point.y - pickOrigin.y)
        guard let index = arrangement.index(at: local), index != view.picked else { return }
        view.pick(index)
        tapTrackpad()
    }

    /// Focuses the picked window, if it is not the focused one already, and closes the capsule.
    private func commit() {
        // Let go before the Space landed: nothing was shown to pick from.
        if waiting != nil { return hide() }
        let space = shownSpace
        hide()
        guard items.indices.contains(view.picked), let coordinator = AppState.shared.coordinator else { return }
        let id = items[view.picked].id
        guard coordinator.workspaces[space]?.contains(id) == true, coordinator.workspaces[space]?.focused != id else { return }
        coordinator.focus(id)
    }

    /// Fades the capsule in, rising a few points, where `origin` says.
    private func present() {
        let panel = glass.panel
        generation += 1
        let primary = NSScreen.screens.first?.frame.maxY ?? 0
        let size = arrangement.size
        let frame = CGRect(x: origin.x, y: primary - origin.y - size.height, width: size.width, height: size.height)
        if panel.isVisible, panel.alphaValue > 0 {
            // Up already, perhaps still fading in, for the workspace the display left: to the new one's frame in
            // place. Through the animator, so the new frame replaces a fade-in's still on its way, which would
            // otherwise land on the old size.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animates ? Self.fadeIn : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } else if animates {
            panel.setFrame(frame.offsetBy(dx: 0, dy: -Self.rise), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeIn
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        glass.dress(cornerRadius: min(CGFloat(config.cornerRadius), size.height / 2))
        // The glass builds its layers on its first display; catch them then too.
        DispatchQueue.main.async { [weak self] in self?.glass.removeShadow() }
    }

    private func hide() {
        waiting = nil
        let panel = glass.panel, shown = generation
        guard animates else { return panel.orderOut(nil) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }
            panel.orderOut(nil)
        })
    }

    private var animates: Bool {
        AppState.shared.config.animations.enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

extension SwitcherPosition {
    /// Where a switcher's capsule of `size` goes in `visible`, shown by a key binding or not; `atPointer` is where it
    /// goes over the pointer.
    func origin(size: CGSize, visible: CGRect, fromKeyboard: Bool, atPointer: CGPoint) -> CGPoint {
        switch self {
        case .auto: fromKeyboard ? SwitcherLayout.centred(size, in: visible) : atPointer
        case .center: SwitcherLayout.centred(size, in: visible)
        case .top: SwitcherLayout.edge(size, in: visible, top: true)
        case .bottom: SwitcherLayout.edge(size, in: visible, top: false)
        case .mouse: atPointer
        }
    }
}
