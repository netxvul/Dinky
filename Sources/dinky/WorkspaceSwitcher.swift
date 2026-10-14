import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// `[workspace-switcher]`: hold the modifier on its own and, after `delay-ms`, a glass capsule of the workspaces shows
// over the pointer on its display, the display's current workspace under it. A card per workspace, its display
// drawn small with the windows where its layout puts them; with `displays = 'all'`, every display's, a group per
// display left to right as the displays are arranged, named when there is more than one. Moving across picks a
// card; releasing the modifier switches to it as `workspace` does, giving its display focus. A display with no
// numbered workspace shows its Space unnumbered, and picking it focuses that display. Esc, or any other key, closes
// the capsule without switching. Thumbnails are the window switcher's, captured as windows lose focus, as a dinky
// switch leaves a workspace, and for the workspaces on screen as the capsule shows; macOS draws no other Space's
// windows. The holding is `ModifierHold`'s. Main thread only.
final class WorkspaceSwitcher {
    static let shared = WorkspaceSwitcher()

    /// Points the pointer moves before it picks, so the current workspace stays picked through a tremor.
    private static let deadZone: CGFloat = 4
    private static let rise: CGFloat = 6
    private static let fadeIn: TimeInterval = 0.14
    private static let fadeOut: TimeInterval = 0.12

    private var config = DinkyConfig.WorkspaceSwitcher()
    private var cornerRadius: CGFloat = 18
    private let hold = ModifierHold(name: "workspace-switcher")
    private var cards: [WorkspaceCard] = []
    private var layout = WorkspaceSwitcherLayout(groups: [], cardHeight: 0, maxWidth: 0)
    /// The capsule's top-left corner, in global coordinates with a top-left origin.
    private var origin = CGPoint.zero
    private var startPointer = CGPoint.zero
    private var pointerMoved = false
    /// Bumped on every showing, so a fade-out that finishes after a newer showing leaves the panel up.
    private var generation = 0

    private lazy var view = WorkspaceSwitcherView(frame: .zero)
    private lazy var glass = GlassPanel(content: view, cornerRadius: cornerRadius)

    init() {
        hold.show = { [unowned self] in show() }
        hold.moved = { [unowned self] in pointerMoved(to: $0) }
        hold.commit = { [unowned self] in commit() }
        hold.hide = { [unowned self] in hide() }
        hold.navigate = { [unowned self] in navigate($0) }
        hold.hasNumber = { [unowned self] n in cards.contains { $0.number == n } }
        hold.pickNumber = { [unowned self] n in
            guard let index = cards.firstIndex(where: { $0.number == n }) else { return false }
            view.pick(index)
            return true
        }
        hold.within = { [unowned self] in CGRect(origin: origin, size: layout.size).contains($0) }
        hold.cycle = { [unowned self] in navigate($0 ? .right : .left) }
    }

    var isShowing: Bool { hold.isShowing }
    /// Whether the capsule, shown from the keyboard, takes this key.
    func takes(_ event: CGEvent) -> Bool { hold.takes(event) }
    /// Whether a modifier or a key binding can show the capsule, so thumbnails are worth keeping.
    private var enabled = false

    /// The `workspace-switcher` command: the capsule in the middle of the display under the pointer, picked with the
    /// keys. False if there is nothing to pick from.
    func showFromKeyboard() -> Bool {
        hold.showFromKeyboard()
    }

    func update(config: Config) {
        self.config = config.workspaceSwitcher
        enabled = self.config.modifier != .none || config.binds("workspace-switcher")
        cornerRadius = CGFloat(self.config.cornerRadius ?? config.windowSwitcher.cornerRadius)
        hold.update(modifier: self.config.modifier, sides: config.modifiers, delayMs: self.config.delayMs)
    }

    /// Closes the capsule without switching, as a binding that runs while it is up does.
    func dismiss() {
        hold.dismiss()
    }

    private var capturing: Bool {
        enabled && config.thumbnails == .windows && Thumbnails.shared.permitted
    }

    /// Captures a window that just lost focus, so its workspace's card is recent.
    func focusLeft(_ id: WindowID) {
        guard capturing, id != 0, AppState.shared.coordinator?.model.windows[id] != nil else { return }
        Thumbnails.shared.refresh(id, scale: NSScreen.main?.backingScaleFactor ?? 2)
    }

    /// Captures the windows of a Space a display is about to leave, while macOS still draws them.
    func leaving(space: UInt64) {
        guard capturing, space != 0 else { return }
        Thumbnails.shared.refresh(windows(on: space), scale: NSScreen.main?.backingScaleFactor ?? 2) { _, _ in }
    }

    // MARK: The capsule

    /// The windows dinky knows on a Space, front to back.
    private func windows(on space: UInt64) -> [WindowID] {
        guard let model = AppState.shared.coordinator?.model else { return [] }
        return dinky_space_window_ids(space, false).map(\.uint32Value).filter { model.windows[$0] != nil }
    }

    /// The Spaces to show for a display: its numbered workspaces in order, less `exclude` and, without `show-empty`,
    /// the empty ones other than the one it shows; a display with no numbered workspace, the Space it shows.
    private func spaces(on display: Display) -> [(space: UInt64, number: Int?)] {
        let numbers = AppState.shared.numbers
        let numbered = numbers.workspaces(on: display)
        guard !numbered.isEmpty else {
            return display.userSpaces.contains(display.currentSpaceID) ? [(display.currentSpaceID, nil)] : []
        }
        return numbered.filter { !config.exclude.contains($0) }.compactMap { n in
            guard let space = numbers.space(of: n) else { return nil }
            if !config.showEmpty, space != display.currentSpaceID, windows(on: space).isEmpty { return nil }
            return (space, n)
        }
    }

    /// Shows the capsule on the display under the pointer, if there are two workspaces or more to pick from.
    private func show() -> Bool {
        let app = AppState.shared
        guard app.enabled, !MissionControl.shared.active, !SpaceSwitcher.shared.switching,
              let coordinator = app.coordinator, let pointer = CGEvent(source: nil)?.location,
              let here = app.displays.displays.first(where: { $0.frame.contains(pointer) }),
              let screen = screen(of: here.id) else { return false }
        let shown = config.displays == .all ? app.displays.displays.sorted { $0.frame.minX < $1.frame.minX } : [here]
        let groups = shown.map { display in (display, spaces(on: display)) }.filter { !$0.1.isEmpty }
        guard groups.reduce(0, { $0 + $1.1.count }) >= 2 else { return false }

        let visible = here.visibleArea
        layout = WorkspaceSwitcherLayout(
            groups: groups.map { display, spaces in
                spaces.map { _ in display.frame.height > 0 ? display.frame.width / display.frame.height : 16.0 / 10 }
            },
            cardHeight: CGFloat(config.cardHeight), cornerRadius: cornerRadius, maxWidth: (visible.width * 0.9).rounded())
        let model = coordinator.model
        cards = groups.flatMap { display, spaces in
            spaces.map { space, number in
                let workspace = coordinator.workspaces[space]
                let miniature: Miniature
                var icons: [WindowID: NSImage] = [:]
                if config.thumbnails == .schematic {
                    miniature = Miniature(schematic: schematic(of: space, coordinator), screen: display.frame, height: layout.cardHeight)
                } else {
                    let tiled = Set(workspace?.windows ?? [])
                    let floating = windows(on: space).reversed().filter { !tiled.contains($0) && model.windows[$0]?.isMinimized == false }
                    miniature = Miniature(screen: display.frame, height: layout.cardHeight, workspace: workspace,
                                          known: { model.windows[$0] != nil },
                                          floating: floating.map { (id: $0, frame: model.windows[$0]!.frame) })
                    for tile in miniature.tiles {
                        guard let pid = model.windows[tile.id]?.pid else { continue }
                        icons[tile.id] = NSRunningApplication(processIdentifier: pid)?.icon
                    }
                }
                let name = coordinator.layoutName(ofSpace: space)
                return WorkspaceCard(space: space, number: number, display: display,
                                     label: number.map { "\($0) · \(name)" } ?? name,
                                     current: display.currentSpaceID == space, miniature: miniature, icons: icons,
                                     schematic: config.thumbnails == .schematic)
            }
        }
        let picked = cards.firstIndex { $0.display.uuid == here.uuid && $0.current }
            ?? cards.firstIndex { $0.display.uuid == here.uuid } ?? 0
        origin = hold.centred ? SwitcherLayout.centred(layout.size, in: visible)
                                 : layout.origin(anchor: picked, pointer: pointer, visible: visible)
        startPointer = pointer
        pointerMoved = false

        let scale = screen.backingScaleFactor
        let headers = groups.map { display, _ in display.name.isEmpty ? "Display \(display.id)" : display.name }
        view.animates = animates
        view.frame = CGRect(origin: .zero, size: layout.size)
        view.show(cards, layout: layout, headers: layout.headers.isEmpty ? [] : headers, picked: picked, scale: scale)
        present()

        if config.thumbnails == .windows {
            Thumbnails.shared.askOnce()
            // Only the workspaces on screen: macOS draws no other Space's windows.
            let onScreen = cards.filter(\.current).flatMap { $0.miniature.tiles.map(\.id) }
            Thumbnails.shared.refresh(onScreen, scale: scale) { [weak self] id, image in
                guard let self, self.isShowing else { return }
                self.view.update(id, image: image)
            }
        }
        return true
    }

    /// The picture a schematic card draws for a Space: floating where dinky does not tile it, else its layout as
    /// the HUD names it, a fixed workspace as its template, and a workspace not laid out yet as its config says.
    private func schematic(of space: UInt64, _ coordinator: Coordinator) -> Schematic {
        let settings = coordinator.settings(for: space)
        guard settings.tiling, !settings.float else { return .floating }
        if settings.layout == .fixed, coordinator.workspaces[space]?.isScrolling != true {
            return .fixed(rows: settings.rows, columns: settings.columns)
        }
        switch coordinator.layoutName(ofSpace: space) {
        case "scrolling": return .scrolling
        case "fullscreen": return .fullscreen
        case "floating": return .floating
        case "v_tiles": return .tiles(.vertical)
        case "h_accordion", "accordion": return .accordion(.horizontal)
        case "v_accordion": return .accordion(.vertical)
        default: return .tiles(.horizontal)
        }
    }

    /// A key's step along the row, round from end to end.
    private func navigate(_ direction: Direction) {
        let index = SwitcherLayout.step(view.picked, count: cards.count, toward: direction)
        guard index != view.picked else { return }
        view.pick(index)
        // Felt, as a pointer's pick is, when the swiping fingers move it.
        if hold.byFingers { tapTrackpad() }
    }

    private func pointerMoved(to point: CGPoint) {
        if !pointerMoved {
            guard hypot(point.x - startPointer.x, point.y - startPointer.y) >= Self.deadZone else { return }
            pointerMoved = true
        }
        guard let index = layout.index(atX: point.x - origin.x), index != view.picked else { return }
        view.pick(index)
        tapTrackpad()
    }

    /// Switches to the picked workspace, or focuses the picked display's Space, and closes the capsule.
    private func commit() {
        hide()
        guard cards.indices.contains(view.picked) else { return }
        let card = cards[view.picked]
        if let number = card.number {
            let reply = Dispatcher.run("workspace \(number)")
            if !reply.ok { fputs("workspace-switcher: \(reply.text)\n", stderr) }
        } else if let display = AppState.shared.displays.displays.first(where: { $0.uuid == card.display.uuid }) {
            _ = Dispatcher.focus(display, window: AppState.shared.coordinator?.workspace(on: display)?.focused)
        }
    }

    /// Fades the capsule in, rising a few points, where `origin` says.
    private func present() {
        let panel = glass.panel
        generation += 1
        let primary = NSScreen.screens.first?.frame.maxY ?? 0
        let size = layout.size
        let frame = CGRect(x: origin.x, y: primary - origin.y - size.height, width: size.width, height: size.height)
        if animates {
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
        glass.dress(cornerRadius: min(cornerRadius, size.height / 2))
        // The glass builds its layers on its first display; catch them then too.
        DispatchQueue.main.async { [weak self] in self?.glass.removeShadow() }
    }

    private func hide() {
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
