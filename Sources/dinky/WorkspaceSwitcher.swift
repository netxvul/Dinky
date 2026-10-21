import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// `[workspace-switcher]`: hold the modifier on its own and, after `delay-ms`, a glass capsule of the workspaces shows
// over the pointer on its display, the display's current workspace under it. A card per workspace, its display
// drawn small with the windows where its layout puts them; with `displays = 'all'`, every display's, a group per
// display left to right as the displays are arranged, named when there is more than one. Moving across picks a
// card; releasing the modifier switches to it as `workspace` does, giving its display focus. A display with no
// numbered workspace shows its Space unnumbered, and picking it focuses that display. With `letter-keys`, the windows
// in the cards carry the letters of `letters`, card by card as each reads, drawn as keys; a letter's key switches to
// its window's workspace at once and focuses the window there. Esc, or any other key, closes the capsule without
// switching. Thumbnails are the window switcher's, captured as windows lose focus, as a dinky
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
    private var position = SwitcherPosition.auto
    private var startPointer = CGPoint.zero
    private var pointerMoved = false
    /// Bumped on every showing, so a fade-out that finishes after a newer showing leaves the panel up.
    private var generation = 0
    /// The window a letter's key picked, focused on its workspace as the pick is taken.
    private var jumpTo: WindowID?

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
        hold.hasLetter = { [unowned self] letter in view.letterTargets[letter] != nil }
        hold.pickLetter = { [unowned self] letter in
            guard let target = view.letterTargets[letter] else { return false }
            view.pick(target.card)
            jumpTo = target.id
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
        config.enabled && hold.showFromKeyboard()
    }

    func update(config: Config) {
        self.config = config.workspaceSwitcher
        let modifier = self.config.enabled ? self.config.modifier : .none
        enabled = self.config.enabled && (modifier != .none || config.binds("workspace-switcher"))
        cornerRadius = CGFloat(self.config.cornerRadius)
        position = self.config.position
        hold.update(modifier: modifier, sides: config.modifiers, delayMs: self.config.delayMs,
                    trigger: self.config.trigger, doubleTapMs: self.config.doubleTapMs)
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
        Thumbnails.shared.refreshSoon(id, scale: NSScreen.main?.backingScaleFactor ?? 2)
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
    /// the empty ones other than the one it shows; a display with no numbered workspace, the Space it shows if that
    /// is a user Space. With `show-fullscreen`, then its native full-screen Spaces with a window dinky knows, in
    /// Mission Control order.
    private func spaces(on display: Display) -> [(space: UInt64, number: Int?)] {
        let numbers = AppState.shared.numbers
        let numbered = numbers.workspaces(on: display)
        let workspaces: [(space: UInt64, number: Int?)]
        if numbered.isEmpty {
            workspaces = display.userSpaces.contains(display.currentSpaceID) ? [(display.currentSpaceID, nil)] : []
        } else {
            workspaces = numbered.filter { !config.exclude.contains($0) }.compactMap { n in
                guard let space = numbers.space(of: n) else { return nil }
                if !config.showEmpty, space != display.currentSpaceID, windows(on: space).isEmpty { return nil }
                return (space, n)
            }
        }
        guard config.showFullscreen else { return workspaces }
        return workspaces + fullscreenSpaces(on: display).map { (space: $0, number: nil) }
    }

    /// A display's native full-screen Spaces that hold a window dinky knows, in Mission Control order.
    private func fullscreenSpaces(on display: Display) -> [UInt64] {
        display.spaces.filter { !display.userSpaces.contains($0) && !fullscreenWindows(on: $0).isEmpty }
    }

    /// The windows a native full-screen Space shows, front to back: one, or two side by side in Split View. Empty for
    /// a user Space.
    private func fullscreenWindows(on space: UInt64) -> [WindowID] {
        guard let display = AppState.shared.displays.display(containingSpace: space),
              !display.userSpaces.contains(space), let model = AppState.shared.coordinator?.model else { return [] }
        return windows(on: space).filter { model.windows[$0]?.isMinimized == false }
    }

    /// Where a native full-screen Space's windows are, back to front: a lone window fills the display; Split View's
    /// windows where the window server has them, or halves of the display left to right when a frame is off it.
    private func fullscreenFrames(_ ids: [WindowID], on display: CGRect, _ model: WindowModel) -> [(id: WindowID, frame: CGRect)] {
        guard ids.count > 1 else { return ids.map { (id: $0, frame: display) } }
        let frames = ids.reversed().map { (id: $0, frame: model.windows[$0]?.frame ?? .zero) }
        if frames.allSatisfy({ !$0.frame.isEmpty && display.insetBy(dx: -1, dy: -1).contains($0.frame) }) { return frames }
        let width = display.width / CGFloat(ids.count)
        return frames.sorted { $0.frame.minX < $1.frame.minX }.enumerated().map { i, entry in
            (id: entry.id, frame: CGRect(x: display.minX + width * CGFloat(i), y: display.minY, width: width, height: display.height))
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
        // Windows in native full screen keep their place in their workspace's tree; they show on their own Space's
        // card only, so a letter or a pick of their workspace does not take macOS back to them.
        let away = Set(app.displays.displays.flatMap { display in
            display.spaces.filter { !display.userSpaces.contains($0) }.flatMap { fullscreenWindows(on: $0) }
        })
        let titled = config.showTitles && config.thumbnails != .schematic
        var titles: [WindowID: String] = [:]
        cards = groups.flatMap { display, spaces in
            spaces.map { space, number in
                let workspace = coordinator.workspaces[space]
                let fullscreen = fullscreenWindows(on: space)
                let miniature: Miniature
                var icons: [WindowID: NSImage] = [:]
                if config.thumbnails == .schematic, !fullscreen.isEmpty {
                    miniature = Miniature(schematic: .fullscreen, screen: display.frame, height: layout.cardHeight)
                } else if config.thumbnails == .schematic {
                    miniature = Miniature(schematic: schematic(of: space, coordinator), screen: display.frame, height: layout.cardHeight)
                } else {
                    if !fullscreen.isEmpty {
                        miniature = Miniature(screen: display.frame, height: layout.cardHeight, workspace: nil,
                                              floating: fullscreenFrames(fullscreen, on: display.frame, model))
                    } else {
                        let tiled = Set(workspace?.windows ?? [])
                        let floating = windows(on: space).reversed().filter { !tiled.contains($0) && model.windows[$0]?.isMinimized == false }
                        miniature = Miniature(screen: display.frame, height: layout.cardHeight, workspace: workspace,
                                              known: { model.windows[$0] != nil && !away.contains($0) },
                                              floating: floating.map { (id: $0, frame: model.windows[$0]!.frame) })
                    }
                    for tile in miniature.tiles {
                        guard let pid = model.windows[tile.id]?.pid else { continue }
                        icons[tile.id] = NSRunningApplication(processIdentifier: pid)?.icon
                    }
                    if titled { titles.merge(WindowTitles.known(miniature.tiles.map(\.id))) { $1 } }
                }
                // A full-screen Space is named for its apps, left to right in Split View.
                let apps = fullscreenFrames(fullscreen, on: display.frame, model).sorted { $0.frame.minX < $1.frame.minX }
                    .compactMap { entry in
                        model.windows[entry.id].flatMap { $0.appName ?? NSRunningApplication(processIdentifier: $0.pid)?.localizedName }
                    }
                let name = apps.isEmpty ? coordinator.layoutName(ofSpace: space) : apps.joined(separator: " | ")
                return WorkspaceCard(space: space, number: number, display: display,
                                     label: number.map { "\($0) · \(name)" } ?? name,
                                     current: display.currentSpaceID == space, miniature: miniature, icons: icons,
                                     schematic: config.thumbnails == .schematic, titles: titled ? titles : nil,
                                     letters: config.letterKeys && config.thumbnails != .schematic)
            }
        }
        let picked = cards.firstIndex { $0.display.uuid == here.uuid && $0.current }
            ?? cards.firstIndex { $0.display.uuid == here.uuid } ?? 0
        let atPointer = layout.origin(anchor: picked, pointer: pointer, visible: visible)
        origin = position.origin(size: layout.size, visible: visible, fromKeyboard: hold.centred, atPointer: atPointer)
        startPointer = pointer
        pointerMoved = false

        let scale = screen.backingScaleFactor
        let headers = groups.map { display, _ in display.name.isEmpty ? "Display \(display.id)" : display.name }
        view.animates = animates
        view.highlight = config.highlightColor
        view.frame = CGRect(origin: .zero, size: layout.size)
        jumpTo = nil
        view.show(cards, layout: layout, headers: layout.headers.isEmpty ? [] : headers, picked: picked, scale: scale,
                  letters: config.letterKeys ? config.letters : [])
        present()
        if titled {
            // The windows the window server gave no title, asked of their apps.
            let asks = cards.flatMap { $0.miniature.tiles.map(\.id) }.filter { titles[$0] == nil }.compactMap { id in
                model.windows[id].map { window in
                    (id: id, pid: window.pid, app: window.appName ?? NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "")
                }
            }
            let shown = generation
            WindowTitles.ask(asks) { [weak self] id, title in
                guard let self, self.generation == shown, self.isShowing else { return }
                self.view.update(id, title: title)
            }
        }

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
        guard !coordinator.isFree(space) else { return .floating }
        let settings = coordinator.settings(for: space)
        if settings.layout == .fixed, coordinator.workspaces[space]?.isScrolling != true {
            return .fixed(rows: settings.rows, columns: settings.columns)
        }
        switch coordinator.layoutName(ofSpace: space) {
        case "scrolling": return .scrolling
        case "fullscreen": return .fullscreen
        case "free": return .floating
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
        let jump = jumpTo
        jumpTo = nil
        guard cards.indices.contains(view.picked) else { return }
        let card = cards[view.picked]
        if let jump, AppState.shared.coordinator?.model.windows[jump] != nil {
            if let number = card.number {
                let reply = Dispatcher.showWorkspace(number, focusing: jump)
                if !reply.ok { fputs("workspace-switcher: \(reply.text)\n", stderr) }
            } else if let display = AppState.shared.displays.displays.first(where: { $0.uuid == card.display.uuid }) {
                _ = Dispatcher.focus(display, window: jump)
            }
        } else if let number = card.number {
            let reply = Dispatcher.run("workspace \(number)")
            if !reply.ok { fputs("workspace-switcher: \(reply.text)\n", stderr) }
        } else if let window = fullscreenWindows(on: card.space).first,
                  let display = AppState.shared.displays.displays.first(where: { $0.uuid == card.display.uuid }) {
            // Focusing the window takes macOS to its full-screen Space.
            _ = Dispatcher.focus(display, window: window)
        } else if let display = AppState.shared.displays.displays.first(where: { $0.uuid == card.display.uuid }) {
            _ = Dispatcher.focus(display, window: Dispatcher.windowToFocus(on: display))
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
