import AppKit
import DinkyConfig
import DinkyLayout

// The mouse scrolling a strip with `[gestures.mouse-scroll] modifier` held, as fingers on the trackpad do
// (`[gestures.scroll]`). With `drag`, a press with exactly the modifier over a window of a strip that can scroll is
// swallowed, its drag and release with it, and once it has gone `MouseDragStart.distance` across it holds the strip,
// which follows the pointer; the release lets go at the speed of its last moves, and the strip coasts and settles as
// the fingers' does. A release before that does nothing. With `wheel`, a stroke of a Magic Mouse's or a trackpad's
// swipe, or of a wheel that turns smoothly with phases, begun with the modifier held over such a strip, holds it the
// same way, scrolled by the stroke's own deltas along the axis it began on (`ScrollAxisLock`); its end lets go, and the
// momentum after it is swallowed too, so the app under the pointer does not scroll on, the modifier released or not. A
// wheel that clicks focuses the column beside for each notch, no more often than `notchGap`. Anything without the
// modifier, or away from a strip, goes on to the app.
//
// As ModifierDrag does it, nothing waits on dinky's main thread for a plain click or scroll: a tap that only listens
// follows the modifiers and turns those for presses and scrolls on only while exactly the modifier is held, or a stroke
// or a press they took is still under way. Main thread only.
final class MouseStripScroll {
    /// A press with the modifier, taken.
    private struct Press {
        let at: CGPoint
        var last: CGPoint
        /// Whether it holds the strip yet, or has given up on it, as one the strip could not be held for.
        var holding = false, spent = false
        var velocity = LetGoVelocity()
    }

    private enum Stroke {
        case idle
        /// A stroke with the modifier over a strip, holding it.
        case holding(ScrollAxisLock, LetGoVelocity)
        /// A stroke going to the app, as one begun without the modifier.
        case passing
        /// A stroke that held the strip ended: the momentum after it is swallowed.
        case coasting
    }

    /// The least time between two notches of a wheel that clicks.
    private static let notchGap: CFTimeInterval = 0.12
    /// Points a smooth wheel without phases turns for a notch.
    private static let notchPoints = 40.0

    private unowned let coordinator: Coordinator
    private var settings = MouseScroll()
    private var sides = ModifierSides()
    private var press: Press?
    private var stroke = Stroke.idle
    private var notchedAt: CFTimeInterval = -.infinity
    private var notchRun = 0.0
    private var modifierTap: MainEventTap?
    /// Takes presses with the modifier; on only while `armed`.
    private var pressTap: MainEventTap?
    /// Takes the drag and the release of a press taken; on only while there is one.
    private var grabTap: MainEventTap?
    /// Takes scrolls; on while `armed`, or while a stroke it took is under way.
    private var wheelTap: MainEventTap?
    private var armed = false

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func update(_ settings: MouseScroll, sides: ModifierSides) {
        self.settings = settings
        self.sides = sides
        guard settings.enabled, settings.drag || settings.wheel else { return stop() }
        start()
        armed = false
        arm(exactlyHeld(settings.modifier, sides: sides, in: CGEventSource.flagsState(.combinedSessionState)))
    }

    private func start() {
        guard modifierTap == nil else { return }
        let presses = MainEventTap([.leftMouseDown], options: .defaultTap, enabled: false, owner: self,
                                   callback: mouseScrollPressCallback)
        let grabs = MainEventTap([.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved], options: .defaultTap,
                                 enabled: false, owner: self, callback: mouseScrollGrabCallback)
        let wheels = MainEventTap([.scrollWheel], options: .defaultTap, enabled: false, owner: self,
                                  callback: mouseScrollWheelCallback)
        let flags = MainEventTap([.flagsChanged], options: .listenOnly, owner: self, callback: mouseScrollModifierCallback)
        guard let presses, let grabs, let wheels, let flags else {
            [presses, grabs, wheels, flags].forEach { $0?.remove() }
            fputs("mouse-scroll: could not create event tap (Accessibility?)\n", stderr)
            return
        }
        (pressTap, grabTap, wheelTap, modifierTap) = (presses, grabs, wheels, flags)
    }

    private func stop() {
        letGo(velocity: 0)
        stroke = .idle
        [pressTap, grabTap, wheelTap, modifierTap].forEach { $0?.remove() }
        (pressTap, grabTap, wheelTap, modifierTap, armed) = (nil, nil, nil, nil, false)
    }

    private func arm(_ held: Bool) {
        armed = held
        pressTap?.enable(held && settings.drag)
        updateWheelTap()
    }

    private func updateWheelTap() {
        let busy: Bool
        switch stroke {
        case .idle: busy = false
        case .holding, .passing, .coasting: busy = true
        }
        wheelTap?.enable(settings.wheel && (armed || busy))
    }

    fileprivate func modifiersChanged(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            modifierTap?.enable(true)
            arm(exactlyHeld(settings.modifier, sides: sides, in: CGEventSource.flagsState(.combinedSessionState)))
        case .flagsChanged:
            let held = exactlyHeld(settings.modifier, sides: sides, in: event.flags)
            if held != armed { arm(held) }
        default:
            break
        }
    }

    // MARK: Drag

    /// A press with the modifier held as last heard; whether it goes on to the app.
    fileprivate func pressed(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if armed, settings.drag { pressTap?.enable(true) }
        case .leftMouseDown:
            // A press still taken lost its release.
            letGo(velocity: 0)
            let point = event.location
            guard exactlyHeld(settings.modifier, sides: sides, in: event.flags), coordinator.dragging == nil,
                  coordinator.mouseCanHold(at: point, press: true) else { return true }
            press = Press(at: point, last: point)
            // Within the press's callback, so the tap is on before the drag comes.
            grabTap?.enable(true)
            // The switchers' modifiers at work for something else, as a click with them is.
            WindowSwitcher.shared.dismiss()
            WorkspaceSwitcher.shared.dismiss()
            return false
        default:
            break
        }
        return true
    }

    /// An event while a press is taken; whether it goes on to the app.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            guard press != nil else { break }
            grabTap?.enable(true)
            // The session never saw the press, so only the hardware knows the button.
            if !CGEventSource.buttonState(.hidSystemState, button: .left) { letGo(velocity: 0) }
        case .leftMouseDown:
            // Another press: the one taken lost its release. The press tap, after this one, takes this one or not.
            letGo(velocity: 0)
        case .leftMouseDragged where press != nil, .mouseMoved where press != nil:
            moved(to: event.location)
            return false
        case .leftMouseUp where press != nil:
            let velocity = press.map { $0.velocity.velocity(at: CACurrentMediaTime()) } ?? 0
            letGo(velocity: velocity)
            return false
        default:
            break
        }
        return true
    }

    private func moved(to point: CGPoint) {
        guard var press, !press.spent else { return }
        defer { self.press = press }
        if !press.holding {
            guard MouseDragStart.holds(dx: point.x - press.at.x, dy: point.y - press.at.y) else { return }
            guard coordinator.mouseTookHold(.drag) else {
                press.spent = true
                print("\(stamp()) mouse-scroll: drag took no hold")
                return
            }
            press.holding = true
            // From where it was pressed: the strip has the grabbed point under the pointer.
            press.last = press.at
        }
        let dx = Double(point.x - press.last.x)
        press.last = point
        press.velocity.add(dx, at: CACurrentMediaTime())
        coordinator.mouseScrolled(dx)
    }

    /// The press taken let go, moving across at `velocity` points a second.
    private func letGo(velocity: Double) {
        guard let press else { return }
        self.press = nil
        grabTap?.enable(false)
        guard press.holding else { return }
        print("\(stamp()) mouse-scroll: drag let go at \(Int(velocity.rounded())) pt/s")
        coordinator.mouseLetGo(velocity: velocity)
    }

    // MARK: Wheel

    /// A scroll; whether it goes on to the app.
    fileprivate func scrolled(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .scrollWheel else {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { updateWheelTap() }
            return true
        }
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let x = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let y = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        defer { updateWheelTap() }
        // The momentum after a stroke: the strip's, swallowed till it ends; anything else's, the app's.
        if momentum != 0 {
            guard case .coasting = stroke else { return true }
            if momentum == 3 { stroke = .idle }
            return false
        }
        if case .coasting = stroke { stroke = .idle }
        let held = exactlyHeld(settings.modifier, sides: sides, in: event.flags)
        switch phase {
        case 0:
            // A wheel without phases: notches.
            guard held, coordinator.mouseCanStep(at: event.location) else { return true }
            notch(x != 0 ? x : y, continuous: continuous)
            return false
        case 128:
            // Fingers resting on the surface before a stroke.
            if case .holding = stroke { return false }
            return !(held && coordinator.mouseCanHold(at: event.location, press: false))
        case 1:
            if case .holding = stroke { letGoStroke(velocity: 0) }
            guard held, coordinator.mouseCanHold(at: event.location, press: false), coordinator.mouseTookHold(.wheel) else {
                stroke = .passing
                return true
            }
            stroke = .holding(ScrollAxisLock(), LetGoVelocity())
            scrollStroke(x: x, y: y)
            return false
        case 2:
            switch stroke {
            case .holding:
                scrollStroke(x: x, y: y)
                return false
            case .passing, .idle, .coasting:
                return true
            }
        default:
            // Ended, or cancelled.
            switch stroke {
            case .holding(_, let velocity):
                letGoStroke(velocity: phase == 4 ? velocity.velocity(at: CACurrentMediaTime()) : 0)
                return false
            case .passing, .idle, .coasting:
                stroke = .idle
                return true
            }
        }
    }

    private func scrollStroke(x: Double, y: Double) {
        guard case .holding(var axis, var velocity) = stroke else { return }
        let delta = axis.delta(x: x, y: y)
        velocity.add(delta, at: CACurrentMediaTime())
        stroke = .holding(axis, velocity)
        if delta != 0 { coordinator.mouseScrolled(delta) }
    }

    private func letGoStroke(velocity: Double) {
        stroke = .coasting
        print("\(stamp()) mouse-scroll: wheel let go at \(Int(velocity.rounded())) pt/s")
        coordinator.mouseLetGo(velocity: velocity)
    }

    /// A wheel without phases turned `delta`, its content going right or down positive: lines for one that clicks,
    /// points for one that turns smoothly, which steps once it has turned `notchPoints` one way.
    private func notch(_ delta: Double, continuous: Bool) {
        guard delta != 0 else { return }
        if continuous {
            if notchRun * delta < 0 { notchRun = 0 }
            notchRun += delta
            guard abs(notchRun) >= Self.notchPoints else { return }
            notchRun = 0
        }
        let now = CACurrentMediaTime()
        guard now - notchedAt >= Self.notchGap else { return }
        notchedAt = now
        coordinator.mouseStepped(left: delta < 0)
    }
}

private func mouseScrollModifierCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<MouseStripScroll>.fromOpaque(refcon).takeUnretainedValue().modifiersChanged(type, event) }
    return Unmanaged.passUnretained(event)
}

private func mouseScrollPressCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                      refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<MouseStripScroll>.fromOpaque(refcon).takeUnretainedValue().pressed(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}

private func mouseScrollGrabCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                     refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<MouseStripScroll>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}

private func mouseScrollWheelCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                      refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<MouseStripScroll>.fromOpaque(refcon).takeUnretainedValue().scrolled(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}
