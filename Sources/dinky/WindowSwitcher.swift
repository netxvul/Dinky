import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// `[window-switcher]`: hold the modifier on its own over a workspace laid out by one of `layouts` and, after `delay-ms`, a
// glass capsule of the workspace's windows shows over the pointer, with the focused one under it. A row for a
// scrolling or accordion workspace, in strip or tree order, the windows of a column or a part of the root together,
// picked by moving across; for a tiles or fixed workspace, with `tiles-style = 'map'`, a map of its tiles, picked by
// moving onto one; for a free workspace, a row of the windows on it, left to right as they stand. Releasing the modifier focuses the window picked, which scrolls a strip to it. While it is up,
// h, j, k, l and the arrows move the pick (`navigate`) and Return or Space focuses it at once, swallowed. Esc closes the
// capsule without focusing anything. With `letter-keys`, each window carries a letter of `letters`, handed out as the
// cards read left to right, drawn as a key beside its title, and its key focuses that window at once, swallowed, held
// or from a binding, whatever modifiers are down. Any other key closes the capsule and goes on to whatever it was
// for, so bindings that use the modifier work as before: a key or click while the modifier is held before the capsule shows calls it
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
    /// Whether that Space is free, its windows untiled, and the window picked as it showed: letting go on it changes
    /// nothing, as on a tree's focused tile.
    private var shownFree = false
    private var shownPick: WindowID = 0
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
            case .row(let row): row.index(at: point)
            case .map(let map): map.index(at: point)
            }
        }
    }

    private var arrangement = Arrangement.row(SwitcherLayout(columns: [], maxWidth: 0))
    /// The capsule's top-left corner, in global coordinates with a top-left origin.
    private var origin = CGPoint.zero
    private var startPointer = CGPoint.zero
    private var pointerMoved = false
    /// Bumped on every showing, so a fade-out that finishes after a newer showing leaves the panel up.
    private var generation = 0
    /// Closes a glance, the capsule shown by itself as fingers let go of a strip, set while one is up. See `glance`.
    private var glanceEnd: Timer?
    /// Bumped by whatever closes a glance, so one still waiting for its strip to rest does not show after it.
    private(set) var calledOff = 0
    /// From a showing for the hold until its hide: the hold lets go before the commit that hides it, as a click's
    /// release or Return's next turn of the run loop, and a glance meanwhile would put its pick in its place.
    private var heldUp = false

    /// Each app's name and icon by its process, as the capsule last showed them: looking them up afresh for every
    /// window took several milliseconds a showing, frames a glance stole from the glide under it.
    private var apps: [pid_t: (running: NSRunningApplication?, name: String, icon: NSImage?)] = [:]

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
        hold.hasLetter = { [unowned self] letter in items.contains { $0.letter == letter } }
        hold.pickLetter = { [unowned self] letter in
            guard let index = items.firstIndex(where: { $0.letter == letter }) else { return false }
            view.pick(index)
            return true
        }
        hold.cycle = { [unowned self] forward in
            view.pick(SwitcherLayout.step(view.picked, count: items.count, toward: forward ? .right : .left))
        }
    }

    var isShowing: Bool { hold.isShowing }
    /// Shown, held, from a binding or as a glance: thumbnails and titles landing late still go in.
    private var isUp: Bool { isShowing || glanceEnd != nil }
    /// Whether the capsule, shown from the keyboard, takes this key.
    func takes(_ event: CGEvent) -> Bool { hold.takes(event) }
    /// Whether a modifier, a key binding or a strip let go of (a glance) can show the capsule, so thumbnails are worth
    /// keeping.
    private var enabled = false
    /// Whether only a glance can, which shows nothing but a scrolling strip: thumbnails for no other workspace.
    private var glancesOnly = false

    /// The `window-switcher` command: the capsule in the middle of the display under the pointer, picked with the
    /// keys. False if the workspace there has nothing to pick from.
    func showFromKeyboard() -> Bool {
        config.enabled && hold.showFromKeyboard()
    }

    func update(config: Config) {
        if !observingSpaces {
            observingSpaces = true
            AppState.shared.displays.observe { [weak self] _ in self?.spacesChanged() }
        }
        self.config = config.windowSwitcher
        let modifier = self.config.enabled ? self.config.modifier : .none
        let byHand = modifier != .none || config.binds("window-switcher")
        let glances = config.gestures.scroll.enabled && config.gestures.scroll.showSwitcher
            && self.config.layouts.contains(.scrolling)
        enabled = self.config.enabled && (byHand || glances)
        glancesOnly = !byHand
        hold.update(modifier: modifier, sides: config.modifiers, delayMs: self.config.delayMs,
                    trigger: self.config.trigger, doubleTapMs: self.config.doubleTapMs)
    }

    /// Closes the capsule without focusing anything, as a binding that runs while it is up does, a glance too.
    func dismiss() {
        hold.dismiss()
        endGlance()
    }

    /// `[gestures.scroll] show-switcher`: the fingers let go of the strip of Space `space` on display `uuid`, settling
    /// with `pick` in view, and the capsule shows that workspace for `duration` seconds with `pick` picked, then closes
    /// by itself: a glance at where the strip went, with nothing to hold, pick or let go of. It goes where it would
    /// held, and for what it would held: not with the switcher off or `layouts` without the workspace's. Not over a
    /// capsule shown or waiting to; one shown meanwhile takes the glance over.
    func glance(space: UInt64, display uuid: String, pick: WindowID, for duration: TimeInterval) {
        let glanced = glanceEnd != nil
        glanceEnd?.invalidate()
        glanceEnd = nil
        let app = AppState.shared
        guard config.enabled, duration > 0, !isShowing, !(heldUp && glass.panel.isVisible), waiting == nil, !showing,
              app.enabled, !MissionControl.shared.active, !SpaceSwitcher.shared.switching,
              !WorkspaceSwitcher.shared.isShowing, let coordinator = app.coordinator,
              let display = app.displays.displays.first(where: { $0.uuid == uuid }),
              display.currentSpaceID == space,
              // Read afresh: the display model learns of a Space swipe only once it lands.
              !dinky_display_is_animating(uuid as CFString), dinky_current_space_id(uuid as CFString) == space else {
            if glanced { hide() }
            return
        }
        // Over the pointer as held, where the fingers left it; in the middle should it have gone to another display.
        let visible = display.visibleArea
        let pointer = (CGEvent(source: nil)?.location).flatMap { display.frame.contains($0) ? $0 : nil }
            ?? CGPoint(x: visible.midX, y: visible.midY)
        showing = true
        defer { showing = false }
        // The pictures kept as each window last lost focus: capturing them all now would load the window server just
        // as the strip glides and its window takes focus.
        guard fill(display, pointer: pointer, pick: pick, fresh: false, coordinator) else {
            if glanced { hide() }
            return
        }
        glanceEnd = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.hide() }
        startWatching()
    }

    /// The name and icon of the app of process `pid`, kept while it runs.
    private func app(_ pid: pid_t) -> (name: String, icon: NSImage?) {
        if let known = apps[pid], known.running?.isTerminated == false { return (known.name, known.icon) }
        let running = NSRunningApplication(processIdentifier: pid)
        apps[pid] = (running, running?.localizedName ?? "", running?.icon)
        return (apps[pid]!.name, apps[pid]!.icon)
    }

    /// Closes a glance up, sooner than it would by itself, or keeps one waiting from showing; nothing else.
    func endGlance() {
        calledOff += 1
        guard glanceEnd != nil else { return }
        hide()
    }

    /// Captures a window that just lost focus on a workspace the switcher shows for, so its thumbnail is recent the next
    /// time the capsule shows its workspace.
    func focusLeft(_ id: WindowID) {
        guard enabled, id != 0, Thumbnails.shared.permitted,
              let coordinator = AppState.shared.coordinator, let placement = coordinator.placements[id] else { return }
        if let workspace = placement.space.flatMap({ coordinator.workspaces[$0] }) {
            guard shows(for: workspace), !glancesOnly || kind(of: workspace) == .scrolling else { return }
        } else {
            guard !glancesOnly, config.layouts.contains(.free), let window = coordinator.model.windows[id],
                  isFreeUserSpace(window.spaceID, coordinator) else { return }
        }
        Thumbnails.shared.refreshSoon(id, scale: NSScreen.main?.backingScaleFactor ?? 2)
    }

    // MARK: The capsule

    /// Whether the workspace is laid out by one of `layouts`.
    private func shows(for workspace: Workspace) -> Bool {
        config.layouts.contains(kind(of: workspace))
    }

    /// Whether the Space is a free workspace: a display's user Space, a native full-screen one being no workspace.
    private func isFreeUserSpace(_ space: UInt64, _ coordinator: Coordinator) -> Bool {
        coordinator.displays.display(containingSpace: space)?.userSpaces.contains(space) == true && coordinator.isFree(space)
    }

    /// The windows a free Space shows, left to right by their middles, then top to bottom.
    private func freeWindows(on space: UInt64, _ coordinator: Coordinator) -> [WindowID] {
        coordinator.model.windows.values
            .filter { $0.spaceID == space && $0.isNormal && !$0.isMinimized && coordinator.placements[$0.id] != nil }
            .sorted { ($0.frame.midX, $0.frame.minY, $0.id) < ($1.frame.midX, $1.frame.minY, $1.id) }
            .map(\.id)
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
        guard isUp, !showing,
              let display = AppState.shared.displays.displays.first(where: { $0.uuid == shownDisplay }),
              display.currentSpaceID != shownSpace else { return }
        // A glance is of the strip let go of, gone from the display now.
        if glanceEnd != nil { return hide() }
        if !show() { hold.dismiss() }
    }

    /// Watches every frame while the capsule is up or waiting: shows a waiting capsule as soon as its display's Space
    /// lands, and moves a shown one to the workspace its display has landed on, without waiting for the notifications.
    /// A glance closes as its display sets off for another Space or Mission Control opens.
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
        guard isUp, !shownDisplay.isEmpty else {
            watch?.invalidate()
            watch = nil
            return
        }
        let uuid = shownDisplay as CFString
        if glanceEnd != nil, MissionControl.shared.active || dinky_display_is_animating(uuid) { return hide() }
        guard !dinky_display_is_animating(uuid), dinky_current_space_id(uuid) != shownSpace else { return }
        AppState.shared.displays.reconcile()
        spacesChanged()
    }

    /// Shows the capsule for the workspace under the pointer, if `layouts` has its layout and it has a tiled window (on
    /// a free workspace, any window), or two with `show-single` off. While the display under the pointer is still moving between Spaces, as in a trackpad swipe, it waits and
    /// shows the workspace it lands on.
    private func show() -> Bool {
        // A glance up is this showing's now: it stays up for it, filled afresh, or goes; one waiting stays away.
        calledOff += 1
        let glanced = glanceEnd != nil
        glanceEnd?.invalidate()
        glanceEnd = nil
        if let pointer = CGEvent(source: nil)?.location,
           let display = AppState.shared.displays.displays.first(where: { $0.frame.contains(pointer) }),
           dinky_display_is_animating(display.uuid as CFString) {
            if glanced { hide() }
            if waiting == nil { waiting = (display.uuid, uptime()) }
            heldUp = true
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
              fill(display, pointer: pointer, pick: nil, fresh: true, coordinator) else {
            if glanced { hide() }
            return false
        }
        heldUp = true
        Thumbnails.shared.askOnce()
        startWatching()
        return true
    }

    /// Fills the capsule with the windows of the workspace `display` is on and shows it placed for `pointer`, `pick`
    /// picked when it is one of them, else the focused window, each window's thumbnail captured afresh when `fresh`,
    /// else only one without a picture yet. False, and nothing shown, when the workspace's layout is not in `layouts`
    /// or it has too few windows. See `show()`.
    private func fill(_ display: Display, pointer: CGPoint, pick: WindowID?, fresh: Bool,
                      _ coordinator: Coordinator) -> Bool {
        guard let screen = screen(of: display.id) else { return false }
        // A free workspace has no tree, or one kept from before it was free.
        let free = isFreeUserSpace(display.currentSpaceID, coordinator)
        let workspace = free ? nil : coordinator.workspace(on: display)
        let tiles = workspace?.tileFrames ?? [:]
        let columns: [[WindowID]]
        if let workspace {
            guard shows(for: workspace) else { return false }
            columns = workspace.root.children.map { $0.windows.filter { coordinator.model.windows[$0] != nil && tiles[$0] != nil } }
                .filter { !$0.isEmpty }
        } else {
            guard free, config.layouts.contains(.free) else { return false }
            columns = freeWindows(on: display.currentSpaceID, coordinator).map { [$0] }
        }
        let ids = columns.flatMap { $0 }
        guard ids.count >= (config.showSingle ? 1 : 2) else { return false }
        let titles = config.showTitles ? WindowTitles.known(ids) : [:]
        items = ids.map { id in
            let window = coordinator.model.windows[id]!
            let running = app(window.pid)
            return SwitcherItem(id: id, app: window.appName ?? running.name, icon: running.icon, title: titles[id] ?? "")
        }
        let visible = display.visibleArea, maxWidth = (visible.width * 0.8).rounded()
        // On a free workspace, the focused window, else the frontmost one there.
        let focused = workspace.map(\.focused) ?? (ids.contains(coordinator.focusedWindow) ? coordinator.focusedWindow
            : dinky_space_window_ids(display.currentSpaceID, false).lazy.map(\.uint32Value).first(where: ids.contains))
        let picked = pick.flatMap { ids.firstIndex(of: $0) } ?? focused.flatMap { ids.firstIndex(of: $0) } ?? 0
        let mapped = config.tilesStyle == .map && workspace.map { [.tiles, .fixed].contains(kind(of: $0)) } == true
        if mapped, let workspace {
            let map = SwitcherMap(tiles: ids.map { tiles[$0]! }, bounds: workspace.bounds,
                                  cornerRadius: CGFloat(config.cornerRadius), maxWidth: maxWidth)
            arrangement = .map(map)
            place(map.size, visible: visible, atPointer: map.origin(anchor: picked, pointer: pointer, visible: visible))
        } else {
            // A column's stacked windows one over the other, as their tiles sit.
            let groups = columns.map { ids in
                SwitcherLayout.Group(aspects: ids.map { id -> CGFloat in
                    let size = coordinator.model.windows[id]!.frame.size
                    return size.height > 0 ? size.width / size.height : 1
                }, tiles: ids.compactMap { tiles[$0] })
            }
            let row = SwitcherLayout(groups: groups, cornerRadius: CGFloat(config.cornerRadius), maxWidth: maxWidth,
                                     titles: config.showTitles || config.letterKeys)
            arrangement = .row(row)
            place(row.size, visible: visible, atPointer: row.origin(anchor: picked, pointer: pointer, visible: visible))
        }
        startPointer = pointer
        pointerMoved = false

        if config.letterKeys {
            // As the cards read, left to right.
            for (index, letter) in zip(SwitcherLayout.readingOrder(arrangement.frames), config.letters) {
                items[index].letter = letter
            }
        }
        let scale = screen.backingScaleFactor
        view.animates = animates
        view.highlight = config.highlightColor
        view.frame = CGRect(origin: .zero, size: arrangement.size)
        view.show(items, frames: arrangement.frames, style: mapped ? .map : .row, picked: picked, scale: scale,
                  titles: config.showTitles, roomUnder: !mapped)
        present()
        if config.showTitles { askTitles() }

        // Tall enough for the biggest cell, grown.
        let height = (arrangement.frames.map(\.height).max() ?? SwitcherLayout.thumbHeight) * 1.1
        let shown = generation
        let capture = fresh ? ids : ids.filter { Thumbnails.shared.image(of: $0) == nil }
        Thumbnails.shared.refresh(capture, height: height, scale: scale) { [weak self] id, image in
            guard let self, self.generation == shown, self.isUp else { return }
            self.view.update(id, image: image)
        }
        shownSpace = display.currentSpaceID
        shownFree = free
        shownPick = ids[picked]
        shownDisplay = display.uuid
        return true
    }

    /// Fills in the titles the window server did not give, as the apps answer.
    private func askTitles() {
        let asks = items.filter { $0.title.isEmpty }.compactMap { item in
            AppState.shared.coordinator?.model.windows[item.id].map { (id: item.id, pid: $0.pid, app: item.app) }
        }
        let shown = generation
        WindowTitles.ask(asks) { [weak self] id, title in
            guard let self, self.generation == shown, self.isUp else { return }
            self.view.update(id, title: title)
        }
    }

    /// Sets `origin` where `position` puts a capsule of `size`, `atPointer` being where it goes over the pointer.
    private func place(_ size: CGSize, visible: CGRect, atPointer: CGPoint) {
        origin = config.position.origin(size: size, visible: visible, fromKeyboard: hold.centred, atPointer: atPointer)
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
        if hold.byFingers, config.haptic {
            tapTrackpad("window switcher pick moved by the fingers", actuation: config.hapticStrength.actuation)
        }
    }

    private func pointerMoved(to point: CGPoint) {
        if !pointerMoved {
            guard hypot(point.x - startPointer.x, point.y - startPointer.y) >= Self.deadZone else { return }
            pointerMoved = true
        }
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let index = arrangement.index(at: local), index != view.picked else { return }
        view.pick(index)
        if config.haptic { tapTrackpad("window switcher pick moved by the pointer", actuation: config.hapticStrength.actuation) }
    }

    /// Focuses the picked window, if it is not the focused one already, and closes the capsule.
    private func commit() {
        // Let go before the Space landed: nothing was shown to pick from.
        if waiting != nil { return hide() }
        let space = shownSpace
        hide()
        guard items.indices.contains(view.picked), let coordinator = AppState.shared.coordinator else { return }
        let id = items[view.picked].id
        if shownFree {
            guard id != shownPick, coordinator.model.windows[id]?.spaceID == space, coordinator.commandFocusedWindow != id else { return }
        } else {
            guard coordinator.workspaces[space]?.contains(id) == true, coordinator.workspaces[space]?.focused != id else { return }
        }
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
        heldUp = false
        glanceEnd?.invalidate()
        glanceEnd = nil
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
