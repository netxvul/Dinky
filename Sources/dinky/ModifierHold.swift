import AppKit
import DinkyConfig
import DinkyLayout

// Holding a modifier on its own, as the switchers use it: held alone for `delayMs`, `show` runs, and while it is
// shown pointer moves go to `moved`; releasing the modifier runs `commit`. While it is shown, the keys a showing from
// the keyboard takes do what they do there, swallowed: the arrows and h, j, k, l `navigate`, Return, Enter or Space
// `commit` at once, Esc runs `hide`. A release commits only once the modifier stays up and no key that moved the pick is
// down, since a remapper such as Karabiner lets the modifiers go for a key it turns into another (hyper-h into left
// arrow) and presses them again after. Any other key, click or scroll with the modifier is the modifier at work for
// something else: it runs `hide` if shown, and goes on to whatever it was for, and a key or click before the delay
// calls the hold off until the modifier is released. Its own event tap, so each switcher holds its own modifier.
//
// With the `double-tap` trigger, holding does nothing: the modifier tapped on its own twice, each tap and the gap
// between them within `doubleTapMs`, shows it as `showFromKeyboard` does, at the pointer, and the keys, pointer and
// clicks drive it as they do there; nothing commits on a release, since the modifier is up already.
//
// `showFromKeyboard`, for a key binding, shows it without the modifier, until a key says what to do: the arrows and
// h, j, k, l go to `navigate`, Tab and Shift-Tab and the binding again to `cycle`, Return, Enter or Space run `commit`, Esc runs
// `hide`, a digit picks what `pickNumber` numbers and a letter what `pickLetter` letters, and runs `commit`, all
// swallowed (a letter held up by the modifier too); any other key or a click runs `hide` and goes on. Shown by a binding with modifiers, letting
// go of them all runs `commit`, as Cmd-Tab does; shown without, from the CLI, it waits for Return or Esc. The mouse
// works too: moves over what is shown, `within` says, go to `moved`, and a click there runs `commit`, swallowed. Shown by a
// trackpad swipe, the swiping fingers drive it too: `fingersMoved` steps the pick and `fingersLifted` commits, as
// `TrackpadGestures` says, or, lifted before a step, leaves it up for the pointer: moves go to `moved` and a click runs
// `commit`, swallowed. Pressing the trackpad while they drive it commits too, and on a Magic Mouse a right click
// runs `hide`, swallowed with its release.
//
// It follows the modifier, the keys and the pointer with a tap that only listens, so no app's input waits on dinky's
// main thread for it. A second tap, ahead of that one, swallows keys, clicks and scrolls, and is on only while it
// shows or the release of a click it took is still to come. Main thread only.
final class ModifierHold {
    private enum State {
        case idle
        /// The modifier is held alone; `show` runs when the work does.
        case arming(DispatchWorkItem)
        /// The modifier is down alone, with the `double-tap` trigger: a tap if it is released in time.
        case tapping(DispatchTime)
        case showing
        /// Shown by a key binding, driven by the keys.
        case keyboard
        /// The modifier was used for something else; nothing until it is released.
        case spoiled
    }

    /// An event older than this as the swallowing tap gets it, with the tap timed out since it happened, was held up
    /// past the timeout: the app has had it.
    private static let timedOut: CFTimeInterval = 1
    /// When the swallowing tap last timed out.
    private var swallowerTimedOutAt = -CFTimeInterval.infinity
    /// The press whose release `swallowUp` or `swallowRightUp` waits for, by type and timestamp.
    private var swallowedPress: (type: CGEventType, time: CGEventTimestamp)?

    /// What the swallowing tap takes; everything else is only ever listened to.
    private static let swallowable: [CGEventType] = [.keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown,
                                                     .rightMouseUp, .scrollWheel]

    /// Shows whatever the hold is for; false if there is nothing to show, which calls the hold off.
    var show: () -> Bool = { false }
    var moved: (CGPoint) -> Void = { _ in }
    /// Moves the pick a step, shown from the keyboard.
    var navigate: (Direction) -> Void = { _ in }
    /// Steps the pick to the next or, with false, the previous of everything shown, round from end to end: Tab,
    /// Shift-Tab and the binding again.
    var cycle: (Bool) -> Void = { _ in }
    var commit: () -> Void = {}
    var hide: () -> Void = {}

    /// Set while a trackpad swipe runs its commands, so a showing from the keyboard is driven by its fingers too.
    static var gesturing = false
    /// Whether the swiping fingers are on a Magic Mouse, whose right click closes what they drive.
    static var fingersOnMouse = false
    /// The hold the swiping fingers drive, while it shows.
    private(set) static weak var driven: ModifierHold?

    private var state = State.idle {
        didSet {
            syncSwallowing()
            if !isShowing {
                cancelLetGo()
                cancelLiftCommit()
            }
        }
    }
    /// Takes the pick once fingers lifted off a mouse stay off for `relanding`: its surface is too short for one
    /// stroke to go far, so they may land again and go on.
    private var liftCommit: DispatchWorkItem?
    private static let relanding: DispatchTimeInterval = .milliseconds(350)
    /// Takes the pick once the modifiers that hold it up stay let go: Karabiner lets them go for a key it turns into
    /// another, as hyper-h into left arrow, and presses them again after.
    private var letGo: DispatchWorkItem?
    /// The last key that moved the pick, which a remapper may still be holding with the modifiers let go.
    private var lastKey: CGKeyCode?
    /// A key moved the pick while `letGo` waited: the modifiers went for that key, not for good.
    private var movedWhileLetGo = false
    private static let letGoCheck: DispatchTimeInterval = .milliseconds(40)
    /// Picks what is numbered `n`, as a digit key asks; false if nothing is.
    var pickNumber: (Int) -> Bool = { _ in false }
    /// Whether something is numbered `n`.
    var hasNumber: (Int) -> Bool = { _ in false }
    /// Picks what carries the letter, as its key asks; false if nothing does.
    var pickLetter: (Character) -> Bool = { _ in false }
    /// Whether something carries the letter.
    var hasLetter: (Character) -> Bool = { _ in false }
    /// Whether a point, in global coordinates with a top-left origin, is over what is shown.
    var within: (CGPoint) -> Bool = { _ in false }
    /// Whether the pick follows the fingers up and down as well as across, as on a map.
    var vertical: () -> Bool = { false }
    /// Shown from the keyboard by a swipe, whose fingers drive it.
    var byFingers: Bool { Self.driven === self && isKeyboard }
    /// Left up by fingers that lifted before a step: the pointer picks and a click commits.
    private var byPointer = false
    /// The click that committed went unseen; its release goes the same way.
    private var swallowUp = false {
        didSet { syncSwallowing() }
    }
    /// Looks again for the release of the click that picked, should it never come to the taps.
    private var releaseCheck: DispatchWorkItem?
    /// The right click that closed it went unseen; its release goes the same way.
    private var swallowRightUp = false {
        didSet { syncSwallowing() }
    }
    /// The modifiers held as it showed from the keyboard; letting go of them all commits.
    private var openedWith: CGEventFlags = []
    /// A press shorter than this is no tap.
    private static let echoNs: UInt64 = 30_000_000
    private static let modifierMasks: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    private var modifier = SwitcherModifier.none
    private var sides = ModifierSides()
    private var delayMs = 200
    private var trigger = SwitcherTrigger.hold
    private var doubleTapMs = 300
    /// When the last tap was released, while a second would make it a double tap.
    private var lastTap: DispatchTime?
    /// Shown by a double tap: at the pointer, and nothing to let go of.
    private var byTap = false
    /// Hears everything it follows and holds none of it up.
    private var listener: MainEventTap?
    /// Takes `swallowable` events, ahead of `listener`; on only while `swallowing`.
    private var swallower: MainEventTap?
    private var swallowing = false
    /// The events `swallower` handled, let through or swallowed, by type and timestamp, oldest first: `listener` hears
    /// those it let through after it, and one it swallowed the window server may deliver all the same after a timeout,
    /// and leaves them be. One it hears that is not here went by while `swallower` was off, or held up.
    private var passedOn: [(type: CGEventType, time: CGEventTimestamp)] = []
    /// The swallowable events `listener` handled while `swallower` was on but had not had them, held up on the way:
    /// gone to the app already, they go through untouched once `swallower` gets them.
    private var heardFirst: [(type: CGEventType, time: CGEventTimestamp)] = []
    private let name: String

    /// `name` is the command that shows it from the keyboard, such as `window-switcher`.
    init(name: String) {
        self.name = name
    }

    var isShowing: Bool {
        switch state {
        case .showing, .keyboard: true
        default: false
        }
    }

    /// Whether a key is one it takes while shown, so key bindings leave it alone: alt-h moves the pick, not the focus,
    /// while alt holds it up or a binding with alt shows it.
    func takes(_ event: CGEvent) -> Bool {
        guard isShowing, let key = key(of: event) else { return false }
        if case .number(let n) = key { return hasNumber(n) }
        if case .letter(let letter) = key { return hasLetter(letter) }
        return true
    }

    /// What a key does to it while shown. Shown from the keyboard, Command with an arrow or h, j, k, l is for
    /// something else; held up by the modifier, which may be Command, they all move the pick.
    private func key(of event: CGEvent) -> SwitcherKey? {
        SwitcherKey(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                    shift: event.flags.contains(.maskShift),
                    command: isKeyboard && event.flags.contains(.maskCommand))
    }

    /// Whether it shows in the middle of the display: shown from the keyboard, but not by a gesture, which shows it
    /// at the pointer like the modifier does.
    var centred: Bool { isKeyboard && !byFingers && !byTap }

    /// Whether it was shown from the keyboard.
    var isKeyboard: Bool {
        if case .keyboard = state { return true }
        return false
    }

    /// Shows it for a key binding, the keys driving it; shown that way already, steps the pick right, as Tab does.
    /// False if there is nothing to show.
    @discardableResult
    func showFromKeyboard(byTap: Bool = false) -> Bool {
        switch state {
        case .keyboard:
            cycle(true)
            return true
        case .showing:
            // Held up by the modifier already: the keys take over.
            state = .keyboard
            openedWith = CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMasks)
            return true
        case .arming(let work):
            work.cancel()
        case .idle, .spoiled, .tapping:
            break
        }
        start()
        state = .keyboard
        Self.driven = Self.gesturing ? self : nil
        byPointer = false
        self.byTap = byTap
        openedWith = Self.gesturing || byTap ? [] : CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMasks)
        guard show() else {
            state = .idle
            settle()
            return false
        }
        return true
    }

    /// Follows `modifier`, its side as `sides` says, held for `delayMs` or tapped twice as `trigger` says; `none`
    /// stops listening, but for a showing from the keyboard.
    func update(modifier: SwitcherModifier, sides: ModifierSides, delayMs: Int, trigger: SwitcherTrigger,
                doubleTapMs: Int) {
        self.modifier = modifier
        self.sides = sides
        self.delayMs = delayMs
        self.trigger = trigger
        self.doubleTapMs = doubleTapMs
        lastTap = nil
        if modifier == .none {
            if !isKeyboard { stop() }
        } else {
            start()
        }
    }

    /// Lets the taps go once a showing from the keyboard is over, with no modifier to listen for.
    private func settle() {
        guard modifier == .none, !isKeyboard, listener != nil else { return }
        state = .idle
        removeTaps()
    }

    /// The swiping fingers moved `steps` steps across, and `rows` down where the pick goes up and down.
    func fingersMoved(steps: Int, rows: Int) {
        guard byFingers else { return }
        for _ in 0..<abs(steps) { navigate(steps > 0 ? .right : .left) }
        if vertical() { for _ in 0..<abs(rows) { navigate(rows > 0 ? .down : .up) } }
    }

    /// The swiping fingers lifted: take the pick if they moved it, or leave it up for the pointer and more swipes.
    func fingersLifted(stepped: Bool) {
        guard byFingers else { return }
        // On a mouse the hand that holds it moves the pointer, so the pointer picks only until fingers land again.
        guard stepped else {
            byPointer = true
            return
        }
        guard Self.fingersOnMouse else { return takeLifted() }
        cancelLiftCommit()
        let work = DispatchWorkItem { [weak self] in
            guard let self, byFingers else { return }
            liftCommit = nil
            takeLifted()
        }
        liftCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.relanding, execute: work)
    }

    /// Fingers landed again on what they drive: on a mouse they go on from where the last stroke left the pick.
    func fingersLanded() {
        guard byFingers else { return }
        cancelLiftCommit()
        if Self.fingersOnMouse { byPointer = false }
    }

    private func takeLifted() {
        state = .idle
        commit()
        settle()
    }

    private func cancelLiftCommit() {
        liftCommit?.cancel()
        liftCommit = nil
    }

    /// Hides what is shown without committing, as a binding that runs while it is up does.
    func dismiss() {
        lastTap = nil
        switch state {
        case .arming(let work):
            work.cancel()
            state = .spoiled
        case .tapping:
            state = .spoiled
        case .showing:
            state = .spoiled
            hide()
        case .keyboard:
            state = .idle
            hide()
            settle()
        case .idle, .spoiled:
            break
        }
    }

    private func start() {
        guard listener == nil else { return }
        let heard: [CGEventType] = [.flagsChanged, .keyDown, .mouseMoved, .leftMouseDragged, .leftMouseDown,
                                    .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .scrollWheel]
        let listener = MainEventTap(heard, options: .listenOnly, owner: self, callback: holdListenCallback)
        // Made second, so it sits ahead of the listener and has each event first.
        let swallower = MainEventTap(Self.swallowable, options: .defaultTap, enabled: false, owner: self,
                                     callback: holdSwallowCallback)
        guard let listener, let swallower else {
            listener?.remove()
            swallower?.remove()
            fputs("\(name): could not create event tap (Accessibility?)\n", stderr)
            return
        }
        (self.listener, self.swallower) = (listener, swallower)
        syncSwallowing()
    }

    private func stop() {
        dismiss()
        state = .idle
        removeTaps()
    }

    private func removeTaps() {
        listener?.remove()
        swallower?.remove()
        (listener, swallower, swallowing) = (nil, nil, false)
        passedOn = []
        heardFirst = []
    }

    /// Turns the swallowing tap on while it shows or the release of a click it took is still to come, and off
    /// otherwise: whatever that tap takes waits for the main thread.
    private func syncSwallowing() {
        let wanted = isShowing || swallowUp || swallowRightUp
        guard let swallower, wanted != swallowing else { return }
        swallowing = wanted
        swallower.enable(wanted)
    }

    /// An event the listener heard.
    fileprivate func heard(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            listener?.enable(true)
            // The modifiers may have changed while it heard nothing.
            flagsChanged(CGEventSource.flagsState(.combinedSessionState))
            return
        default:
            break
        }
        if Self.swallowable.contains(type),
           let index = passedOn.firstIndex(where: { $0.type == type && $0.time == event.timestamp }) {
            // The swallower had it already. Those it swallowed stay till newer push them out: the window server may
            // still deliver one late.
            passedOn.remove(at: index)
            return
        }
        if swallowing, Self.swallowable.contains(type) {
            if heardFirst.count >= 16 { heardFirst.removeFirst() }
            heardFirst.append((type, event.timestamp))
        }
        _ = handle(type, event, canSwallow: false)
    }

    /// An event the swallower has; whether to let it through.
    fileprivate func intercepted(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if type == .tapDisabledByTimeout {
                swallowerTimedOutAt = CACurrentMediaTime()
                // The notice comes behind the event the tap timed out on, so that one was handled as swallowed before
                // the timeout could be known: where it was the press now waiting for its release, the app had the press,
                // and its release goes to the app too, or the app is left with a button down.
                if let press = swallowedPress, let last = passedOn.last, last.type == press.type, last.time == press.time {
                    if press.type == .leftMouseDown, swallowUp { released() }
                    if press.type == .rightMouseDown, swallowRightUp { rightReleased() }
                }
            }
            // What went by meanwhile, the listener heard.
            if swallowing { swallower?.enable(true) }
            return true
        default:
            break
        }
        // Held up past the tap's timeout, the listener has had it already: handled twice, a key would move the pick
        // twice.
        if let index = heardFirst.firstIndex(where: { $0.type == type && $0.time == event.timestamp }) {
            heardFirst.remove(at: index)
            return true
        }
        // Held up past the tap's timeout, the tap timing out since it happened, the window server gave it to the app
        // already, unheard by the listener: handled as one gone to the app, and let through, so a click held so long gets
        // its release. Old only from waiting before this tap, it is this tap's still.
        let canSwallow = eventAge(event) <= Self.timedOut || swallowerTimedOutAt < eventTime(event)
        let passes = handle(type, event, canSwallow: canSwallow) || !canSwallow
        if passedOn.count >= 32 { passedOn.removeFirst() }
        passedOn.append((type, event.timestamp))
        return passes
    }

    /// Whether to let the event through. `canSwallow` is false for an event the listener heard, gone to the app already.
    private func handle(_ type: CGEventType, _ event: CGEvent, canSwallow: Bool) -> Bool {
        // TEMP switcher-keys trace: what a remapper sends while it shows.
        if isShowing, type == .flagsChanged || type == .keyDown {
            print(String(format: "%@ %@ trace: %@ code=%lld flags=%llx state=%@ swallow=%d", stamp(), name,
                         type == .keyDown ? "down" : "flags", event.getIntegerValueField(.keyboardEventKeycode),
                         event.flags.rawValue, "\(state)", canSwallow ? 1 : 0))
            fflush(stdout)
        }
        switch type {
        case .flagsChanged:
            flagsChanged(event.flags)
        case .keyDown where isKeyboard:
            return keyboardKey(event)
        case .keyDown where isShowing:
            return heldKey(event)
        case .keyDown:
            dismiss()
        case .mouseMoved, .leftMouseDragged:
            if case .showing = state { moved(event.location) }
            if pointerPicks(at: event.location) { moved(event.location) }
        case .scrollWheel where byFingers:
            // The swiping fingers scroll too, and their momentum goes on after they lift: none of it is for the app.
            return false
        case .scrollWheel where event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0:
            // Momentum of a stroke before, as a strip's flick: no use of the modifier.
            break
        case .rightMouseDown where byFingers && Self.fingersOnMouse:
            // A right click on the mouse the fingers drive it on closes it, as Esc does.
            guard canSwallow else {
                dismiss()
                return true
            }
            // The taps stay on for its release, swallowed too, and go only then.
            swallowedPress = (type, event.timestamp)
            swallowRightUp = true
            lastTap = nil
            state = .idle
            hide()
            awaitRightRelease()
            return false
        case .rightMouseUp:
            guard swallowRightUp else { return true }
            rightReleased()
            return false
        case .rightMouseDown where byFingers, .otherMouseDown where byFingers:
            // A tap or press of the fingers that drive it, which only lifting them, or the left button, ends.
            break
        case .leftMouseDown where byFingers || pointerPicks(at: event.location):
            // Pressing the trackpad the fingers drive it on takes the pick, as a click on it does.
            // Its release goes the way it went: swallowed too, or, heard only once the app had it, left to the app.
            state = .idle
            guard canSwallow else {
                commitSoon()
                settle()
                return false
            }
            // The commit waits for the release, so the swallowing tap is off before it can wait on another app.
            swallowedPress = (type, event.timestamp)
            swallowUp = true
            awaitRelease()
            return false
        case .leftMouseUp:
            guard swallowUp else { return true }
            // Its press picked; the commit and the tap's going wait only for the release to be swallowed too.
            released()
            return false
        default:
            // A click or scroll with the modifier is the modifier at work for something else.
            dismiss()
        }
        return true
    }

    /// Whether the pointer picks, shown from the keyboard: over what is shown, or anywhere once a swipe's fingers have
    /// left it up, but not while they drive it.
    private func pointerPicks(at point: CGPoint) -> Bool {
        guard isKeyboard else { return false }
        return byFingers ? byPointer : within(point)
    }

    /// A key while shown from the keyboard; whether to let it through.
    private func keyboardKey(_ event: CGEvent) -> Bool {
        switch key(of: event) {
        case .dismiss:
            dismiss()
        case .confirm:
            state = .idle
            commitSoon()
            settle()
        case .number(let n) where pickNumber(n):
            // A digit picks what it numbers and takes it at once.
            state = .idle
            commitSoon()
            settle()
        case .letter(let letter) where pickLetter(letter):
            // So does a letter what carries it.
            state = .idle
            commitSoon()
            settle()
        case .cycle(let forward):
            cycle(forward)
        case .move(let direction):
            lastKey = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if letGo != nil { movedWhileLetGo = true }
            navigate(direction)
        default:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                || AppState.shared.hotkeys.commands(for: event)?.contains(name) == true {
                // The binding that showed it, again or held down: its command steps the pick.
                return true
            }
            dismiss()
            return true
        }
        return false
    }

    /// A key while held up by the modifier; whether to let it through. One it takes it swallows; taking the pick
    /// leaves the hold spoiled until the modifier is let go, so it does not show again meanwhile.
    private func heldKey(_ event: CGEvent) -> Bool {
        switch key(of: event) {
        case .dismiss:
            dismiss()
        case .confirm:
            state = .spoiled
            commitSoon()
        case .number(let n) where pickNumber(n):
            state = .spoiled
            commitSoon()
        case .letter(let letter) where pickLetter(letter):
            state = .spoiled
            commitSoon()
        case .cycle(let forward):
            cycle(forward)
        case .move(let direction):
            lastKey = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if letGo != nil { movedWhileLetGo = true }
            navigate(direction)
        default:
            dismiss()
            return true
        }
        return false
    }

    /// Commits for a click that picked once its release came, the swallowing tap off by then.
    private func released() {
        releaseCheck?.cancel()
        releaseCheck = nil
        swallowUp = false
        commitSoon()
        settle()
    }

    /// The release of the right click that closed it came, or was lost.
    private func rightReleased() {
        swallowRightUp = false
        settle()
    }

    /// Checks now and then that the right button is still down while the release of the click that closed it is
    /// awaited, so a release lost before it reached the taps leaves no click held up.
    private func awaitRightRelease() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            guard let self, swallowRightUp else { return }
            if CGEventSource.buttonState(.combinedSessionState, button: .right) {
                awaitRightRelease()
            } else {
                rightReleased()
            }
        }
    }

    /// Checks now and then that the button is still down while the release of the click that picked is awaited:
    /// one lost before it reached the taps would otherwise leave the pick uncommitted and every click held up.
    private func awaitRelease() {
        releaseCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, swallowUp else { return }
            if CGEventSource.buttonState(.combinedSessionState, button: .left) {
                awaitRelease()
            } else {
                released()
            }
        }
        releaseCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: check)
    }

    /// Runs `commit` once the swallowing tap's callback has returned: it focuses a window or switches a workspace,
    /// which can wait on another app, and the event taken, and those behind it in the tap, should not.
    private func commitSoon() {
        DispatchQueue.main.async { [weak self] in self?.commit() }
    }

    private func flagsChanged(_ flags: CGEventFlags) {
        if isKeyboard {
            // The binding's modifiers all let go: take the pick.
            guard !openedWith.isEmpty else { return }
            guard flags.intersection(openedWith).isEmpty else { return cancelLetGo() }
            whenLetGo(stillHeld: { [unowned self] in !$0.intersection(openedWith).isEmpty }) { [unowned self] in
                state = .idle
                commit()
                settle()
            }
        } else {
            modifiersChanged(flags)
        }
    }

    /// Runs `take` once the modifiers stay let go, as `stillHeld` reads them, and no key that moved the pick is down.
    /// A key that moved the pick meanwhile is a remapper's, such as Karabiner's hyper-h, which lets the modifiers go
    /// and may press them again only with the next key: it stays up for the keys, Return taking the pick and Esc
    /// closing it, as from a key binding, or takes the pick once the modifiers come back and go again.
    private func whenLetGo(stillHeld: @escaping (CGEventFlags) -> Bool, take: @escaping () -> Void,
                           again: Bool = false) {
        guard letGo == nil else { return }
        if !again { movedWhileLetGo = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, isShowing else { return }
            letGo = nil
            // Pressed again, its flagsChanged on the way.
            if stillHeld(CGEventSource.flagsState(.combinedSessionState)) { return }
            if let key = lastKey, CGEventSource.keyState(.combinedSessionState, key: key) {
                return whenLetGo(stillHeld: stillHeld, take: take, again: true)
            }
            if movedWhileLetGo { return keepUp() }
            take()
        }
        letGo = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.letGoCheck, execute: work)
    }

    /// Stays up for the keys once a remapper let the modifier go for a key that moved the pick.
    private func keepUp() {
        guard case .showing = state else { return }
        let masks = modifierFlags.filter { flag in
            modifier == .hyper ? sides.hyper.contains(flag.modifier) : flag.setting == keyPath(modifier)
        }.reduce(CGEventFlags()) { $0.union($1.mask) }
        state = .keyboard
        openedWith = masks
        print("\(stamp()) \(name): the modifier went for a remapped key; up until Return, Esc or the modifier again")
        fflush(stdout)
    }

    private func cancelLetGo() {
        letGo?.cancel()
        letGo = nil
    }

    /// Whether `modifier` is held in `flags`, and held alone; nil for none.
    private func holding(_ flags: CGEventFlags) -> (held: Bool, alone: Bool)? {
        if modifier == .hyper {
            // All of hyper's modifiers, from either side, and no other; letting go of any one is letting go.
            let members = modifierFlags.filter { sides.hyper.contains($0.modifier) }
            let held = members.allSatisfy { flags.contains($0.mask) }
            return (held, held && !modifierFlags.contains { !sides.hyper.contains($0.modifier) && flags.contains($0.mask) })
        }
        guard let target = modifierFlags.first(where: { $0.setting == keyPath(modifier) }) else { return nil }
        let held = flags.contains(target.mask)
        return (held, held && target.isHeld(by: sides, in: flags)
            && !modifierFlags.contains { $0.mask != target.mask && flags.contains($0.mask) })
    }

    private func modifiersChanged(_ flags: CGEventFlags) {
        guard let (held, alone) = holding(flags) else { return }
        switch state {
        case .idle:
            guard alone else { return }
            if trigger == .doubleTap {
                state = .tapping(.now())
            } else {
                arm()
            }
        case .tapping(let pressed):
            guard !alone else { return }
            tapped(pressed: pressed, released: !held)
        case .arming(let work):
            guard !alone else { return }
            work.cancel()
            state = held ? .spoiled : .idle
        case .showing:
            if held {
                cancelLetGo()
            } else {
                whenLetGo(stillHeld: { [unowned self] in holding($0)?.held == true }) { [unowned self] in
                    state = .idle
                    commit()
                }
            }
        case .spoiled:
            if !held { state = .idle }
        case .keyboard:
            break
        }
    }

    private func keyPath(_ modifier: SwitcherModifier) -> KeyPath<ModifierSides, ModifierSide>? {
        switch modifier {
        case .none, .hyper: nil
        case .alt: \.alt
        case .ctrl: \.ctrl
        case .cmd: \.cmd
        case .shift: \.shift
        }
    }

    /// The modifier pressed alone at `pressed` is up again or joined by another: a second tap in time shows it.
    private func tapped(pressed: DispatchTime, released: Bool) {
        let now = DispatchTime.now()
        let window = UInt64(doubleTapMs) * 1_000_000
        // Too short for a finger: a remapper's echo, such as Karabiner pressing hyper again for a few milliseconds
        // as it sends Caps Lock for a hyper key tapped alone. It neither counts nor spoils the tap before it.
        if released, now.uptimeNanoseconds - pressed.uptimeNanoseconds < Self.echoNs {
            state = .idle
            return
        }
        guard released, now.uptimeNanoseconds - pressed.uptimeNanoseconds <= window else {
            state = released ? .idle : .spoiled
            lastTap = nil
            return
        }
        state = .idle
        if let last = lastTap, pressed.uptimeNanoseconds - last.uptimeNanoseconds <= window {
            lastTap = nil
            showFromKeyboard(byTap: true)
        } else {
            lastTap = now
        }
    }

    private func arm() {
        let work = DispatchWorkItem { [weak self] in self?.armed() }
        state = .arming(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: work)
    }

    private func armed() {
        guard case .arming = state else { return }
        // Showing before `show` runs, so what it shows can ask.
        state = .showing
        if !show() { state = .spoiled }
    }
}

private func holdListenCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<ModifierHold>.fromOpaque(refcon).takeUnretainedValue().heard(type, event) }
    return Unmanaged.passUnretained(event)
}

private func holdSwallowCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<ModifierHold>.fromOpaque(refcon).takeUnretainedValue().intercepted(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}

/// An event tap at the head of the session's taps, its events handled on the main run loop. One that only listens
/// holds nothing up; one that can swallow holds up every event it is given until its callback returns, so such a tap
/// is best on only while it has something to swallow.
struct MainEventTap {
    private let port: CFMachPort
    private let source: CFRunLoopSource

    /// Taps `types` for `owner`, which `callback` gets as its user info, on or not as `enabled` says. Nil if macOS
    /// will not have it, as without Accessibility.
    init?(_ types: [CGEventType], options: CGEventTapOptions, enabled: Bool = true, owner: AnyObject,
          callback: CGEventTapCallBack) {
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(owner).toOpaque()) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        CGEvent.tapEnable(tap: port, enable: enabled)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        (self.port, self.source) = (port, source)
    }

    func enable(_ on: Bool) {
        CGEvent.tapEnable(tap: port, enable: on)
    }

    func remove() {
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(port)
    }
}
