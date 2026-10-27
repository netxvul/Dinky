import AppKit
import DinkyConfig
import DinkyLayout

// Dragging a window from anywhere in it with `[drag] mouse-modifier` held, not only by its title bar. A press with
// exactly those modifiers over a window dinky places, tiled or floating, grabs it: the press, the drag and the
// release are swallowed, so the app never sees them, and each move of the pointer sends the window to where the
// pointer takes it on its app's frame queue, the newest winning, so a slow app only falls behind itself. The window
// is focused, as a press on its title bar would. A tiled window is dragged as one dragged by its title bar is
// (Drag.swift): placeholders while it moves, and on release it drops by the tile under the pointer. A floating window
// just moves. A press over anything else, or with other modifiers, goes on to the app.
//
// A plain click never passes through a tap that could hold it up on dinky's main thread: a tap that only listens
// follows the modifiers and turns the one for presses on only while exactly those are held, and the one for the drag,
// the moves and the release is on only while a window is held. Main thread only.
final class ModifierDrag {
    private struct Grab {
        let id: WindowID
        let pid: pid_t
        /// From the window's top-left corner to the pointer as it was pressed.
        let offset: CGSize
        /// Where the window was last sent.
        var frame: CGRect
        /// The pointer events that moved it, drags and plain moves, and where the last left the pointer, for the log.
        var drags = 0, moves = 0
        var pointer: CGPoint
        /// The press that took it, by its timestamp.
        let press: CGEventTimestamp
    }

    private unowned let coordinator: Coordinator
    private var modifiers: KeyCombo.Modifiers = []
    private var sides = ModifierSides()
    private var grab: Grab?
    /// Listens to the modifiers, to turn `pressTap` on only while exactly `modifiers` are held.
    private var modifierTap: MainEventTap?
    /// Takes presses; on only while `armed`.
    private var pressTap: MainEventTap?
    /// Takes the drag, the moves and the release; on only while a window is held.
    private var grabTap: MainEventTap?
    /// Whether exactly the modifiers are held, as `modifierTap` last heard.
    private var armed = false

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    /// Listens for presses with exactly `modifiers`, each from a key `sides` allows; none stops listening.
    func update(modifiers: KeyCombo.Modifiers, sides: ModifierSides) {
        self.modifiers = modifiers
        self.sides = sides
        guard !modifiers.isEmpty else { return stop() }
        start()
        // The modifiers held now, which may be these or no longer.
        arm(held(in: CGEventSource.flagsState(.combinedSessionState)))
    }

    private func start() {
        guard modifierTap == nil else { return }
        let presses = MainEventTap([.leftMouseDown], options: .defaultTap, enabled: false, owner: self,
                                   callback: dragPressCallback)
        // It has presses too, while a window is held: one without the modifiers still says the release was lost.
        let grabs = MainEventTap([.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved], options: .defaultTap,
                                 enabled: false, owner: self, callback: dragGrabCallback)
        let flags = MainEventTap([.flagsChanged], options: .listenOnly, owner: self, callback: dragModifierCallback)
        guard let presses, let grabs, let flags else {
            [presses, grabs, flags].forEach { $0?.remove() }
            fputs("drag: could not create event tap (Accessibility?)\n", stderr)
            return
        }
        (pressTap, grabTap, modifierTap) = (presses, grabs, flags)
    }

    private func stop() {
        release()
        [pressTap, grabTap, modifierTap].forEach { $0?.remove() }
        (pressTap, grabTap, modifierTap, armed) = (nil, nil, nil, false)
    }

    /// Turns presses on while exactly the modifiers are held, and off once they are not.
    private func arm(_ held: Bool) {
        guard held != armed else { return }
        armed = held
        pressTap?.enable(held)
    }

    /// The modifiers changed.
    fileprivate func modifiersChanged(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            modifierTap?.enable(true)
            // They may have changed while it heard nothing.
            arm(held(in: CGEventSource.flagsState(.combinedSessionState)))
        case .flagsChanged:
            arm(held(in: event.flags))
        default:
            break
        }
    }

    /// A press with exactly the modifiers held, as they were last heard; whether to let it through.
    fileprivate func pressed(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if armed { pressTap?.enable(true) }
        case .leftMouseDown:
            // A window still held lost its release.
            release()
            return !take(at: event.location, flags: event.flags, press: event.timestamp)
        default:
            break
        }
        return true
    }

    /// An event while a window is held; whether to let it through.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            guard let grab else { break }
            grabTap?.enable(true)
            // The release may have come while the tap was off. The session never saw the press, so only the
            // hardware's state knows the button.
            let down = CGEventSource.buttonState(.hidSystemState, button: .left)
            print("\(stamp()) drag: event tap \(type == .tapDisabledByTimeout ? "timed out" : "disabled by input") holding \(grab.id), button \(down ? "down" : "up")")
            if !down { release() }
        case .leftMouseDown:
            // A window still held lost its release, which a press without the modifiers says too. The press that
            // took it is no such press.
            if let grab, grab.press != event.timestamp { release() }
        case .leftMouseDragged where grab != nil, .mouseMoved where grab != nil:
            // The session never saw the press, so the drag can come as plain moves.
            move(to: event.location, dragged: type == .leftMouseDragged)
            return false
        case .leftMouseUp where grab != nil:
            release()
            return false
        default:
            break
        }
        return true
    }

    /// Grabs the window a press at `point` lands in, if exactly the modifiers are held and dinky places it, tiled
    /// or floating. Whether it did.
    private func take(at point: CGPoint, flags: CGEventFlags, press: CGEventTimestamp) -> Bool {
        guard held(in: flags), coordinator.enabled, coordinator.dragging == nil, let window = window(at: point),
              coordinator.model.windows[window.id]?.pid == window.pid, let placement = coordinator.placements[window.id],
              placement.floating || placement.space != nil, !coordinator.isAnimating(window.id) else { return false }
        grab = Grab(id: window.id, pid: window.pid,
                    offset: CGSize(width: point.x - window.frame.minX, height: point.y - window.frame.minY), frame: window.frame,
                    pointer: point, press: press)
        // Within the press's callback, so the tap is on before the drag comes.
        grabTap?.enable(true)
        // Its size stays, so every move writes only its position.
        coordinator.applier.assume([window.id: window.frame.size], pids: [window.id: window.pid])
        // The switchers' modifier at work for something else, as a click with it is.
        WindowSwitcher.shared.dismiss()
        WorkspaceSwitcher.shared.dismiss()
        print("\(stamp()) drag: grabbed \(window.id) with \(modifiers.name), \(placement.space != nil ? "tiled" : "floating")")
        // Its steps start a run: the first size the app is asked for is no step it is slow to follow.
        coordinator.applier.startRun([window.id])
        // Once the press is swallowed: focusing waits on the app.
        DispatchQueue.main.async { [coordinator] in coordinator.focus(window.id) }
        if placement.space != nil { coordinator.startHeldDrag(of: window.id, at: window.frame, pointer: point) }
        return true
    }

    private func move(to point: CGPoint, dragged: Bool) {
        guard var grab else { return }
        grab.frame.origin = CGPoint(x: point.x - grab.offset.width, y: point.y - grab.offset.height)
        grab.pointer = point
        if dragged { grab.drags += 1 } else { grab.moves += 1 }
        self.grab = grab
        coordinator.applier.step([FrameJob(pid: grab.pid, id: grab.id, frame: grab.frame)])
        coordinator.heldDragMoved(grab.id, to: grab.frame, pointer: point)
    }

    /// Lets go of the window held: a tiled one drops by the tile under the pointer.
    private func release() {
        guard let grab else { return }
        self.grab = nil
        grabTap?.enable(false)
        print("\(stamp()) drag: let go of \(grab.id) at \(grab.pointer) after \(grab.drags) drags and \(grab.moves) moves, sent to \(grab.frame)")
        coordinator.endHeldDrag(of: grab.id)
    }

    /// Whether exactly the modifiers are held, each from a key its side allows.
    private func held(in flags: CGEventFlags) -> Bool {
        modifierFlags.allSatisfy { flag in
            modifiers.contains(flag.modifier)
                ? flags.contains(flag.mask) && flag.isHeld(by: sides, in: flags)
                : !flags.contains(flag.mask)
        }
    }

    /// The window a press at `point` lands in: the frontmost at the normal and floating levels, dinky's own
    /// windows looked through, as the placeholders and the borders are clicked through.
    private func window(at point: CGPoint) -> ScreenWindow? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let levels = 0...Int(CGWindowLevelForKey(.floatingWindow)), own = getpid()
        let windows = info.compactMap { w -> ScreenWindow? in
            guard let layer = w[kCGWindowLayer as String] as? Int, levels.contains(layer),
                  (w[kCGWindowAlpha as String] as? Double ?? 0) > 0, let owner = w[kCGWindowOwnerPID as String] as? pid_t,
                  owner != own, let id = w[kCGWindowNumber as String] as? UInt32,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return ScreenWindow(id: id, pid: owner, layer: layer, frame: frame)
        }
        return windowAt(point, in: windows)
    }
}

private func dragModifierCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                  refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<ModifierDrag>.fromOpaque(refcon).takeUnretainedValue().modifiersChanged(type, event) }
    return Unmanaged.passUnretained(event)
}

private func dragPressCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<ModifierDrag>.fromOpaque(refcon).takeUnretainedValue().pressed(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}

private func dragGrabCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<ModifierDrag>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}
