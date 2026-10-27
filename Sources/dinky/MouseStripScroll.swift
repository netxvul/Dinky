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
//
// With `cursor`, the pointer shows the hand for the drag (`GrabCursor`): open over a window a press would take
// (`Coordinator.mousePressWindow`, which the press asks too), looked at as the pointer moves with the modifier held
// (`HoverThrottle`), and closed while a press is taken or holds the strip (`GrabCursorRule`). Its panel takes what lands
// on it, so nothing that is not the strip's may find it there: each tap that lets such an event through clears it
// first, and `GrabGuard`, behind them all, orders it out for anything else that would land on it.
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
    /// The hand for the drag.
    private let grab = GrabCursor()
    /// Hears moves and keys while armed with the hand on (`hovered`).
    private var hoverTap: MainEventTap?
    /// Orders the hand's panel out for what goes past the other taps to the window under it.
    private let grabGuard = GrabGuard()
    private var throttle: HoverThrottle?
    /// When a scroll last went to the app: no open hand while scrolls go on (`GrabCursorRule.scrolling`).
    private var passedScrollAt: CFTimeInterval = -.infinity
    /// Bumped as the modifier goes down or the hand is interrupted, so a look scheduled before does nothing.
    private var hoverGeneration = 0
    private var armedAt: CFTimeInterval = 0
    /// A key went down with the modifier, or the hand let an event through to the app: no open hand till the modifier is
    /// let go of.
    private var spoiled = false
    /// Every frame while armed with the hand on, or while it shows (`tick`).
    private var keeper: Timer?
    private var lookedAt: CFTimeInterval = 0
    /// The hand on, and all it needs there: its taps and the private calls that order its panel out.
    private var cursorOn: Bool {
        settings.enabled && settings.drag && settings.cursor && hoverTap != nil && grabGuard.isRunning && GrabCursor.available
    }

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        grabGuard.onOrderedOut = { [weak self] type in self?.guardOrderedOut(type) }
        grab.onExit = { [weak self] in self?.updateCursor() }
    }

    func update(_ settings: MouseScroll, sides: ModifierSides) {
        self.settings = settings
        self.sides = sides
        grab.clear()
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
        // First, so it goes in behind every tap made after it: off till the hand may show, so it costs nothing with the
        // cursor off, and there should the cursor be turned on later.
        if GrabCursor.available { grabGuard.start() }
        let presses = MainEventTap([.leftMouseDown], options: .defaultTap, enabled: false, owner: self,
                                   callback: mouseScrollPressCallback)
        let grabs = MainEventTap([.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved], options: .defaultTap,
                                 enabled: false, owner: self, callback: mouseScrollGrabCallback)
        let wheels = MainEventTap([.scrollWheel], options: .defaultTap, enabled: false, owner: self,
                                  callback: mouseScrollWheelCallback)
        let flags = MainEventTap([.flagsChanged], options: .listenOnly, owner: self, callback: mouseScrollModifierCallback)
        let hovers = MainEventTap([.mouseMoved, .keyDown], options: .listenOnly, enabled: false, owner: self,
                                  callback: mouseScrollHoverCallback)
        guard let presses, let grabs, let wheels, let flags, let hovers else {
            [presses, grabs, wheels, flags, hovers].forEach { $0?.remove() }
            fputs("mouse-scroll: could not create event tap (Accessibility?)\n", stderr)
            return
        }
        (pressTap, grabTap, wheelTap, modifierTap, hoverTap) = (presses, grabs, wheels, flags, hovers)
    }

    private func stop() {
        letGo(velocity: 0)
        if case .holding(let hold, _, _) = stroke { coordinator.mouseLetGo(velocity: 0, hold: hold) }
        stroke = .idle
        stopCursor()
        grabGuard.enable(false)
        [pressTap, grabTap, wheelTap, modifierTap, hoverTap].forEach { $0?.remove() }
        (pressTap, grabTap, wheelTap, modifierTap, hoverTap, armed, wheelOn) = (nil, nil, nil, nil, nil, false, false)
    }

    private func arm(_ held: Bool) {
        armed = held
        pressTap?.enable(held && settings.drag)
        updateWheelTap()
        hoverGeneration += 1
        hoverTap?.enable(held && cursorOn)
        if held, cursorOn {
            // Nothing shows till the hold settles: a chord such as alt-1 is over by then.
            armedAt = CACurrentMediaTime()
            throttle = HoverThrottle(armedAt: armedAt)
            if let due = throttle?.moved(at: armedAt) { lookAgain(at: due) }
        } else {
            throttle = nil
            spoiled = false
            updateCursor()
        }
        updateKeeper()
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
                  coordinator.mouseCanHold(at: point, press: true) else {
                letThrough()
                return true
            }
            press = Press(at: point, last: point, velocity: LetGoVelocity(since: eventTime(event)))
            // Within the press's callback, so the tap is on before the drag comes.
            grabTap?.enable(true)
            updateCursor()
            // The switchers' modifiers at work for something else, as a click with them is: a capsule up closes, and a
            // modifier a switcher double-taps is no tap, whatever its own taps hear of the press swallowed here.
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

    /// The press is written back before each call into the coordinator, never after one: the coordinator can end the
    /// hold meanwhile (`holdEnded`), which a stale copy written back would undo.
    private func moved(to point: CGPoint, at time: CFTimeInterval) {
        guard var press, !press.spent else { return }
        if press.hold == nil {
            guard MouseDragStart.holds(dx: point.x - press.at.x, dy: point.y - press.at.y) else { return }
            // A stroke holding the strip loses it to the press.
            if case .holding = stroke { stroke = .spent }
            // The strip of the display pressed, however far the pointer has gone since.
            guard let hold = coordinator.mouseTookHold(.drag, at: press.at) else {
                self.press?.spent = true
                print("\(stamp()) mouse-scroll: drag took no hold")
                DispatchQueue.main.async { [weak self] in self?.updateCursor() }
                return
            }
            // From where it was pressed: the strip has the grabbed point under the pointer.
            press.hold = hold
            press.last = press.at
            self.press = press
            // A hold ended to take this one cleared the hand: closed again, once the press is noted holding.
            DispatchQueue.main.async { [weak self] in self?.updateCursor() }
        }
        guard let hold = press.hold else { return }
        let dx = Double(point.x - press.last.x)
        press.last = point
        press.velocity.add(dx, at: time)
        self.press = press
        coordinator.mouseScrolled(dx, hold: hold)
    }

    /// The coordinator ended hold `hold`, as a Space changing or Mission Control mid-drag, or the strip taken over: a
    /// press holding it moves nothing more, and shows no hand, till the button comes up.
    func holdEnded(_ hold: Int) {
        if press?.hold == hold { press?.spent = true }
    }

    /// The press taken let go, moving across at `velocity` points a second.
    private func letGo(velocity: Double) {
        guard let press else { return }
        self.press = nil
        // Back to the open hand over the window under the pointer, if still armed, or none.
        defer { updateCursor() }
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

    /// A scroll; whether it goes on to the app, the hand cleared first if it does.
    fileprivate func scrolled(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let passes = scroll(type, event)
        if passes, type == .scrollWheel { scrollPassed() }
        return passes
    }

    private func scroll(_ type: CGEventType, _ event: CGEvent) -> Bool {
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
            // A wheel without phases: notches. While a press of ours holds the strip, swallowed, not the app's with the
            // modifier.
            guard held else { return true }
            if pressHolds { return false }
            guard coordinator.mouseCanStep(at: event.location) else { return true }
            // A capsule up closes, as for a press with the modifier.
            WindowSwitcher.shared.dismiss()
            WorkspaceSwitcher.shared.dismiss()
            spoilSwitcherTaps()
            notch(x != 0 ? x : y, continuous: continuous)
            return false
        case 128:
            // Fingers resting on the surface before a stroke.
            switch stroke {
            case .holding, .spent: return false
            case .idle, .passing, .coasting:
                // A press of ours taken: the stroke about to begin is its, not the app's.
                if pressTaken { return false }
                return !(held && coordinator.mouseCanHold(at: event.location, press: false))
            }
        case 1:
            if case .holding = stroke { letGoStroke(velocity: 0) }
            // A press of ours taken, holding or yet to: the stroke is spent, swallowed, not the app's with the modifier.
            if pressTaken {
                stroke = .spent
                return false
            }
            guard held, coordinator.mouseCanHold(at: event.location, press: false) else {
                stroke = .passing
                return true
            }
            guard let hold = coordinator.mouseTookHold(.wheel) else {
                stroke = .passing
                return true
            }
            spoilSwitcherTaps()
            stroke = .holding(hold, ScrollAxisLock(), LetGoVelocity())
            // A stroke holding the strip shows no hand.
            updateCursor()
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

    /// Whether a press of ours holds the strip, and is not spent.
    private var pressHolds: Bool { press.map { $0.hold != nil && !$0.spent } ?? false }
    /// Whether a press of ours is taken, holding the strip or yet to, and not spent.
    private var pressTaken: Bool { press.map { !$0.spent } ?? false }

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
        defer { updateCursor() }
        print("\(stamp()) mouse-scroll: wheel let go at \(Int(velocity.rounded())) pt/s")
        coordinator.mouseLetGo(velocity: velocity, hold: hold)
    }

    /// The modifier, held to scroll, is no tap of a switcher that double-taps the same one: its own taps hear the
    /// modifier go down and up, but not the scroll in between, which this swallows.
    private func spoilSwitcherTaps() {
        let config = AppState.shared.config
        let same = { (modifier: SwitcherModifier) in
            modifier != .none && modifier.modifiers(hyper: config.modifiers.hyper) == self.settings.modifier
        }
        if same(config.windowSwitcher.modifier) { WindowSwitcher.shared.spoilTap() }
        if same(config.workspaceSwitcher.modifier) { WorkspaceSwitcher.shared.spoilTap() }
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

// MARK: Hand

extension MouseStripScroll {
    /// Shows the hand `GrabCursorRule` asks for, at the pointer, or none.
    private func updateCursor() {
        let state: GrabCursorRule.Press = press.map { $0.spent ? .spent : $0.hold != nil ? .holding : .taken } ?? .none
        let point = CGEvent(source: nil)?.location ?? .zero
        let strokeBusy = switch stroke {
        case .holding, .passing: true
        default: false
        }
        let now = CACurrentMediaTime(), lastScroll = max(passedScrollAt, grabGuard.lastScroll)
        let scrolling = GrabCursorRule.scrolling(at: now, lastScroll: lastScroll, stroke: strokeBusy)
        // A scroll going on to the app through a press: swallowed spent strokes stamp no time, so they hide nothing. By
        // time alone, as each event of a passing stroke stamps it: one left resting, as a finger on a Magic Mouse, or
        // whose end goes unheard, keeps the closed hand off no longer.
        let passing = GrabCursorRule.scrolling(at: now, lastScroll: lastScroll, stroke: false)
        // While a right or other button is down its drag and release go to the app that got the press: no panel.
        let otherDown = CGEventSource.buttonState(.hidSystemState, button: .right)
            || CGEventSource.buttonState(.hidSystemState, button: .center)
        // The window under the pointer is looked for only where an open hand could show.
        let looks = state == .none && armed && cursorOn && !spoiled && !scrolling && !otherDown
        let window = looks ? coordinator.mousePressWindow(at: point) : nil
        let shape = cursorOn ? GrabCursorRule.shape(enabled: settings.enabled, cursor: settings.cursor, drag: settings.drag,
                                                    press: state, armed: armed,
                                                    buttonDown: CGEventSource.buttonState(.hidSystemState, button: .left),
                                                    over: window != nil, spoiled: spoiled, scrolling: scrolling,
                                                    passing: passing) : nil
        switch otherDown ? nil : shape {
        case .open?:
            grab.showOpen(over: window!)
        case .closed?:
            if let at = press?.at, let display = coordinator.displayFrame(at: at) { grab.showClosed(on: display) } else { grab.clear() }
        case nil:
            grab.clear()
        }
        updateKeeper()
    }

    /// An event not the strip's goes on to the app: the hand goes first, so it reaches the window under it, and no
    /// open hand shows again till the modifier is let go of.
    private func letThrough() {
        guard grab.isShowing else { return }
        grab.clear()
        spoiled = true
        updateKeeper()
    }

    /// A scroll the app had: the hand goes first, and no open hand shows while scrolls go on, but the hold is not
    /// spoiled for it, as momentum from an earlier flick would spoil it.
    private func scrollPassed() {
        passedScrollAt = CACurrentMediaTime()
        if grab.isShowing {
            grab.clear()
            updateKeeper()
        }
    }

    /// `GrabGuard` ordered the panel out for an event of `type` going past the taps.
    private func guardOrderedOut(_ type: CGEventType) {
        if type == .scrollWheel { return scrollPassed() }
        grab.clear()
        // A right or other press, a gesture or the tablet: the modifier at work for something else.
        spoiled = true
        updateKeeper()
    }

    /// The hand goes for something it has no place over (`Coordinator.mouseCursorInterrupted`), and the pointer is
    /// looked at again: once that settles, or with `settle` false, as a hold of the strip ends, at once.
    func interruptCursor(settle: Bool) {
        grab.clear()
        hoverGeneration += 1
        guard armed, cursorOn else { return updateKeeper() }
        if settle {
            armedAt = CACurrentMediaTime()
            throttle = HoverThrottle(armedAt: armedAt)
            if let due = throttle?.moved(at: armedAt) { lookAgain(at: due) }
        } else {
            // Looked at now: a look the throttle had due is taken by this one, so moves go on asking for looks.
            throttle?.checked(at: CACurrentMediaTime())
            updateCursor()
        }
        updateKeeper()
    }

    /// The hand goes now, the arrow set at once where it was dinky's, as dinky is turned off or quits.
    func stopCursor() {
        grab.clear(atOnce: true)
        hoverGeneration += 1
        throttle = nil
        keeper?.invalidate()
        keeper = nil
    }

    /// dinky turned on again: the modifier may be held already, so the hand follows it.
    func rearm() {
        guard modifierTap != nil else { return }
        arm(exactlyHeld(settings.modifier, sides: sides, in: CGEventSource.flagsState(.combinedSessionState)))
    }

    /// Looks at the pointer at `due`, unless the modifier went down again or the hand was interrupted meanwhile.
    private func lookAgain(at due: CFTimeInterval) {
        let generation = hoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, due - CACurrentMediaTime())) { [weak self] in
            guard let self, hoverGeneration == generation, throttle != nil else { return }
            let now = CACurrentMediaTime()
            throttle?.checked(at: now)
            lookedAt = now
            updateCursor()
        }
    }

    /// A move or a key heard while armed with the hand on.
    fileprivate func hovered(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout:
            if armed, cursorOn { hoverTap?.enable(true) }
        case .keyDown where armed:
            // A chord with the modifier, as alt-1: not a hold for the strip.
            guard !spoiled else { return }
            spoiled = true
            updateCursor()
        case .mouseMoved:
            guard event.getIntegerValueField(.eventSourceUserData) != GrabCursor.moveTag else { return }
            // The modifier let go of while its release went unheard; as it is now, not as a move queued a while ago had it.
            guard exactlyHeld(settings.modifier, sides: sides, in: CGEventSource.flagsState(.combinedSessionState)) else {
                return arm(false)
            }
            if let due = throttle?.moved(at: CACurrentMediaTime()) { lookAgain(at: due) }
        default:
            break
        }
    }

    private func updateKeeper() {
        // While a press is taken too, so the closed hand comes back once a scroll passed meanwhile goes quiet, even with
        // the modifier let go mid-drag.
        let wanted = (armed && cursorOn) || grab.isShowing || (cursorOn && pressTaken)
        // The guard hears presses and scrolls only while the hand may show, its scrolls keeping the open hand off.
        grabGuard.enable(wanted)
        guard wanted != (keeper != nil) else { return }
        if wanted {
            let keeper = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(keeper, forMode: .common)
            self.keeper = keeper
        } else {
            keeper?.invalidate()
            keeper = nil
        }
    }

    /// Every frame: the hand set again over another app's cursor; every tenth of a second, the modifiers and the
    /// window under the pointer looked at again, as a window may slide under it or a release go unheard.
    private func tick() {
        grab.keep()
        let now = CACurrentMediaTime()
        guard now - lookedAt >= 0.1 else { return }
        lookedAt = now
        let held = exactlyHeld(settings.modifier, sides: sides, in: CGEventSource.flagsState(.combinedSessionState))
        if held != armed { return arm(held) }
        if !armed || now >= armedAt + HoverThrottle.settle { updateCursor() }
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

private func mouseScrollHoverCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                      refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<MouseStripScroll>.fromOpaque(refcon).takeUnretainedValue().hovered(type, event) }
    return Unmanaged.passUnretained(event)
}
