import AppKit
import DinkyConfig
import DinkyLayout

// The mouse scrolling a strip with `[gestures.mouse-scroll] modifier` held, as fingers on the trackpad do
// (`[gestures.scroll]`). With `drag`, a press with exactly the modifier over a window of a strip that can scroll is
// swallowed, its drag and release with it, and once it has gone `MouseDragStart.distance` across it holds the strip,
// which follows the pointer; the release lets go at the speed of its last moves, and the strip coasts and settles as
// the fingers' does. A release before that does nothing. With `wheel`, a stroke that reports scroll phases, a Magic
// Mouse's or a trackpad's swipe or a smooth wheel whose driver sends them, begun with the modifier held over such a
// strip, holds it the same way, scrolled by the stroke's own deltas along the axis it chooses (`ScrollAxisLock`); its end
// lets go, and the momentum after it is swallowed too, so the app under the pointer does not scroll on, the modifier
// released or not. Any other wheel focuses the column beside for each notch, or each `notchPoints` of a smooth one, no
// more often than `notchGap`. Anything without the modifier, or away from a strip that can scroll, goes on to the app.
//
// Each hold is numbered (`Coordinator.mouseTookHold`), and the press or stroke that took it moves and lets go of that
// one only: one that loses the strip to the other, or to anything else, is spent, its events still swallowed but
// moving nothing. Speeds come from the events' own times (`eventTime`), not from when they got here.
//
// As ModifierDrag does it, nothing waits on dinky's main thread for a plain click or scroll: a tap that only listens
// follows the modifiers and turns those for presses and scrolls on only while exactly the modifier is held, or a stroke
// or a press they took is still under way. Main thread only.
final class MouseStripScroll {
    /// A press with the modifier, taken.
    private struct Press {
        let at: CGPoint
        var last: CGPoint
        /// The hold it took, once it has; spent, it holds nothing and never will, as one the strip could not be held for.
        var hold: Int?
        var spent = false
        var velocity: LetGoVelocity
    }

    private enum Stroke {
        case idle
        /// A stroke with the modifier over a strip, holding it: hold `Int`.
        case holding(Int, ScrollAxisLock, LetGoVelocity)
        /// A stroke that lost its hold before it ended: the rest of it, and its momentum, are swallowed.
        case spent
        /// A stroke going to the app, as one begun without the modifier.
        case passing
        /// A stroke that held the strip ended: the momentum after it is swallowed.
        case coasting
    }

    /// The least time between two notches of a wheel without phases.
    private static let notchGap: CFTimeInterval = 0.12
    /// Points a smooth wheel without phases turns for a notch.
    private static let notchPoints = 40.0
    /// A press older than this as it gets here was held up on the way: the app may have had it already.
    private static let stalePress: CFTimeInterval = 0.25

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
    /// Whether `wheelTap` is meant to be on. Turned on or off only as that changes: turning a tap off tells its callback
    /// so, which must not turn it off again.
    private var wheelOn = false
    private var armed = false

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func update(_ settings: MouseScroll, sides: ModifierSides) {
        self.settings = settings
        self.sides = sides
        guard settings.enabled, settings.drag || settings.wheel else { return stop() }
        start()
        // The wheel turned off mid-stroke: the stroke lets go, as stopping would.
        if !settings.wheel {
            if case .holding(let hold, _, _) = stroke { coordinator.mouseLetGo(velocity: 0, hold: hold) }
            stroke = .idle
        }
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
        if case .holding(let hold, _, _) = stroke { coordinator.mouseLetGo(velocity: 0, hold: hold) }
        stroke = .idle
        [pressTap, grabTap, wheelTap, modifierTap].forEach { $0?.remove() }
        (pressTap, grabTap, wheelTap, modifierTap, armed, wheelOn) = (nil, nil, nil, nil, false, false)
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
        case .holding, .spent, .passing, .coasting: busy = true
        }
        let on = settings.wheel && (armed || busy)
        guard on != wheelOn else { return }
        wheelOn = on
        wheelTap?.enable(on)
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
            // Off by a timeout, the app may have had the press meanwhile: its drag and release go on to it. Turned off
            // as the modifier was let go of, a press still dragging goes on.
            if type == .tapDisabledByTimeout { letGo(velocity: 0) }
        case .leftMouseDown:
            // A press still taken lost its release.
            letGo(velocity: 0)
            let point = event.location
            guard eventAge(event) <= Self.stalePress, exactlyHeld(settings.modifier, sides: sides, in: event.flags),
                  coordinator.dragging == nil, coordinator.mouseCanHold(at: point, press: true) else { return true }
            press = Press(at: point, last: point, velocity: LetGoVelocity(since: eventTime(event)))
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
        case .mouseMoved where press != nil && !CGEventSource.buttonState(.hidSystemState, button: .left)
            && eventAge(event) < CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseUp):
            // The button came up and its release never got here: the pointer is free again. Not for a move from before
            // the release, still on its way.
            letGo(velocity: 0)
        case .leftMouseDragged where press != nil, .mouseMoved where press != nil:
            moved(to: event.location, at: eventTime(event))
            return false
        case .leftMouseUp where press != nil:
            let velocity = press.map { $0.velocity.velocity(at: eventTime(event)) } ?? 0
            letGo(velocity: velocity)
            return false
        default:
            break
        }
        return true
    }

    private func moved(to point: CGPoint, at time: CFTimeInterval) {
        guard var press, !press.spent else { return }
        defer { self.press = press }
        if press.hold == nil {
            guard MouseDragStart.holds(dx: point.x - press.at.x, dy: point.y - press.at.y) else { return }
            // A stroke holding the strip loses it to the press.
            if case .holding = stroke { stroke = .spent }
            guard let hold = coordinator.mouseTookHold(.drag) else {
                press.spent = true
                print("\(stamp()) mouse-scroll: drag took no hold")
                return
            }
            press.hold = hold
            // From where it was pressed: the strip has the grabbed point under the pointer.
            press.last = press.at
        }
        guard let hold = press.hold else { return }
        let dx = Double(point.x - press.last.x)
        press.last = point
        press.velocity.add(dx, at: time)
        coordinator.mouseScrolled(dx, hold: hold)
    }

    /// The press taken let go, moving across at `velocity` points a second.
    private func letGo(velocity: Double) {
        guard let press else { return }
        self.press = nil
        grabTap?.enable(false)
        guard let hold = press.hold, !press.spent else { return }
        print("\(stamp()) mouse-scroll: drag let go at \(Int(velocity.rounded())) pt/s")
        coordinator.mouseLetGo(velocity: velocity, hold: hold)
    }

    /// The coordinator found the button up with no release heard: the press taken, if any, lets go where it is. False
    /// if there was none to let go.
    func releaseLost() -> Bool {
        guard press?.hold != nil else { return false }
        print("\(stamp()) mouse-scroll: release lost, letting go")
        letGo(velocity: 0)
        return true
    }

    // MARK: Wheel

    /// A scroll; whether it goes on to the app.
    fileprivate func scrolled(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .scrollWheel else {
            // Off by a timeout while meant to be on, the tap goes back on, and a stroke held lets go, its end maybe lost
            // meanwhile. Off because it was turned off, as `updateWheelTap` does, nothing.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, wheelOn {
                wheelTap?.enable(true)
                // Whatever the stroke was doing, its end may have gone by: none is left waiting on it.
                switch stroke {
                case .holding: letGoStroke(velocity: 0)
                case .spent: stroke = .coasting
                case .passing: stroke = .idle
                case .idle, .coasting: break
                }
                updateWheelTap()
            }
            return true
        }
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let x = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let y = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let time = eventTime(event)
        defer { updateWheelTap() }
        // The momentum after a stroke: the strip's, swallowed till it ends; anything else's, the app's.
        if momentum != 0 {
            switch stroke {
            case .coasting, .spent:
                if momentum == 3 { stroke = .idle }
                return false
            case .idle, .holding, .passing:
                return true
            }
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
            switch stroke {
            case .holding, .spent: return false
            case .idle, .passing, .coasting: return !(held && coordinator.mouseCanHold(at: event.location, press: false))
            }
        case 1:
            if case .holding = stroke { letGoStroke(velocity: 0) }
            guard held, coordinator.mouseCanHold(at: event.location, press: false),
                  let hold = coordinator.mouseTookHold(.wheel) else {
                stroke = .passing
                return true
            }
            // A press holding the strip loses it to the stroke.
            if press?.hold != nil { press?.spent = true }
            stroke = .holding(hold, ScrollAxisLock(), LetGoVelocity())
            scrollStroke(x: x, y: y, at: time)
            return false
        case 2:
            switch stroke {
            case .holding:
                scrollStroke(x: x, y: y, at: time)
                return false
            case .spent:
                return false
            case .passing, .idle, .coasting:
                return true
            }
        default:
            // Ended, or cancelled.
            switch stroke {
            case .holding(_, _, let velocity):
                letGoStroke(velocity: phase == 4 ? velocity.velocity(at: time) : 0)
                return false
            case .spent:
                stroke = .coasting
                return false
            case .passing, .idle, .coasting:
                stroke = .idle
                return true
            }
        }
    }

    private func scrollStroke(x: Double, y: Double, at time: CFTimeInterval) {
        guard case .holding(let hold, var axis, var velocity) = stroke else { return }
        let delta = axis.delta(x: x, y: y)
        velocity.add(delta, at: time)
        stroke = .holding(hold, axis, velocity)
        // Even moving nothing along its axis, the stroke is heard from.
        coordinator.mouseScrolled(delta, hold: hold)
    }

    private func letGoStroke(velocity: Double) {
        guard case .holding(let hold, _, _) = stroke else { return }
        stroke = .coasting
        print("\(stamp()) mouse-scroll: wheel let go at \(Int(velocity.rounded())) pt/s")
        coordinator.mouseLetGo(velocity: velocity, hold: hold)
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

/// When `event` happened, in `CACurrentMediaTime` seconds: its own timestamp, not when it got here. An event that
/// came through the session carries nanoseconds since startup, measured as `CACurrentMediaTime` is (seen on macOS 27,
/// where the host's ticks are not nanoseconds); one made here and never posted carries none, and is taken as now.
func eventTime(_ event: CGEvent) -> CFTimeInterval {
    event.timestamp == 0 ? CACurrentMediaTime() : CFTimeInterval(event.timestamp) / 1_000_000_000
}

/// How long ago `event` happened.
func eventAge(_ event: CGEvent) -> CFTimeInterval {
    CACurrentMediaTime() - eventTime(event)
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
