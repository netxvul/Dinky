import AppKit
import DinkyConfig
import DinkyLayout

// Holding a modifier on its own, as the switchers use it: held alone for `delayMs`, `show` runs, and while it is
// shown pointer moves go to `moved`; releasing the modifier runs `commit`. Esc runs `hide` and is swallowed. Any
// other key, click or scroll with the modifier is the modifier at work for something else: it runs `hide` if shown,
// and goes on to whatever it was for, and a key or click before the delay calls the hold off until the modifier is
// released. Its own event tap, so each switcher holds its own modifier.
//
// `showFromKeyboard`, for a key binding, shows it without the modifier, until a key says what to do: the arrows and
// h, j, k, l go to `navigate`, Tab and Shift-Tab and the binding again to `cycle`, Return, Enter or Space run `commit`, Esc runs
// `hide`, a digit picks what `pickNumber` numbers and runs `commit`, all swallowed; any other key or a click runs `hide` and goes on. Shown by a binding with modifiers, letting
// go of them all runs `commit`, as Cmd-Tab does; shown without, from the CLI, it waits for Return or Esc. The mouse
// works too: moves over what is shown, `within` says, go to `moved`, and a click there runs `commit`, swallowed. Shown by a
// trackpad swipe, the swiping fingers drive it too: `fingersMoved` steps the pick and `fingersLifted` commits, as
// `TrackpadGestures` says, or, lifted before a step, leaves it up for the pointer: moves go to `moved` and a click runs
// `commit`, swallowed. Main thread only.
final class ModifierHold {
    private enum State {
        case idle
        /// The modifier is held alone; `show` runs when the work does.
        case arming(DispatchWorkItem)
        case showing
        /// Shown by a key binding, driven by the keys.
        case keyboard
        /// The modifier was used for something else; nothing until it is released.
        case spoiled
    }

    private static let escape: Int64 = 53
    private static let tab: Int64 = 48
    /// Keys that move the pick: the arrows, and h, j, k, l.
    private static let directions: [Int64: Direction] = [123: .left, 124: .right, 125: .down, 126: .up,
                                                         4: .left, 38: .down, 40: .up, 37: .right]
    /// The digit keys, the row's and the keypad's, by the number they type; 0 is 10.
    private static let digits: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10,
                                                83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 10]
    /// Return, keypad Enter and Space.
    private static let confirms: Set<Int64> = [36, 76, 49]

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
    /// The hold the swiping fingers drive, while it shows.
    private(set) static weak var driven: ModifierHold?

    private var state = State.idle
    /// Picks what is numbered `n`, as a digit key asks; false if nothing is.
    var pickNumber: (Int) -> Bool = { _ in false }
    /// Whether something is numbered `n`.
    var hasNumber: (Int) -> Bool = { _ in false }
    /// Whether a point, in global coordinates with a top-left origin, is over what is shown.
    var within: (CGPoint) -> Bool = { _ in false }
    /// Whether the pick follows the fingers up and down as well as across, as on a map.
    var vertical: () -> Bool = { false }
    /// Shown from the keyboard by a swipe, whose fingers drive it.
    var byFingers: Bool { Self.driven === self && isKeyboard }
    /// Left up by fingers that lifted before a step: the pointer picks and a click commits.
    private var byPointer = false
    /// The click that committed went unseen; its release goes the same way.
    private var swallowUp = false
    /// The modifiers held as it showed from the keyboard; letting go of them all commits.
    private var openedWith: CGEventFlags = []
    private static let modifierMasks: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    private var modifier = SwitcherModifier.none
    private var sides = ModifierSides()
    private var delayMs = 200
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
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

    /// Whether a key is one it takes while shown from the keyboard, so key bindings leave it alone: alt-h moves the
    /// pick, not the focus, while a binding with alt shows it.
    func takes(_ event: CGEvent) -> Bool {
        guard isKeyboard else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        return code == Self.escape || code == Self.tab || Self.confirms.contains(code)
            || (Self.directions[code] != nil && !event.flags.contains(.maskCommand))
            || (Self.digits[code].map(hasNumber) ?? false)
    }

    /// Whether it shows in the middle of the display: shown from the keyboard, but not by a gesture, which shows it
    /// at the pointer like the modifier does.
    var centred: Bool { isKeyboard && !byFingers }

    /// Whether it was shown from the keyboard.
    var isKeyboard: Bool {
        if case .keyboard = state { return true }
        return false
    }

    /// Shows it for a key binding, the keys driving it; shown that way already, steps the pick right, as Tab does.
    /// False if there is nothing to show.
    @discardableResult
    func showFromKeyboard() -> Bool {
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
        case .idle, .spoiled:
            break
        }
        start()
        state = .keyboard
        Self.driven = Self.gesturing ? self : nil
        byPointer = false
        openedWith = Self.gesturing ? [] : CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMasks)
        guard show() else {
            state = .idle
            settle()
            return false
        }
        return true
    }

    /// Follows `modifier`, its side as `sides` says, held for `delayMs`; `none` stops listening, but for a showing
    /// from the keyboard.
    func update(modifier: SwitcherModifier, sides: ModifierSides, delayMs: Int) {
        self.modifier = modifier
        self.sides = sides
        self.delayMs = delayMs
        if modifier == .none {
            if !isKeyboard { stop() }
        } else {
            start()
        }
    }

    /// Lets the tap go once a showing from the keyboard is over, with no modifier to listen for.
    private func settle() {
        guard modifier == .none, !isKeyboard, let tap else { return }
        state = .idle
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
        (self.tap, source) = (nil, nil)
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
        guard stepped else {
            byPointer = true
            return
        }
        state = .idle
        commit()
        settle()
    }

    /// Hides what is shown without committing, as a binding that runs while it is up does.
    func dismiss() {
        switch state {
        case .arming(let work):
            work.cancel()
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
        guard tap == nil else { return }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .mouseMoved, .leftMouseDragged, .leftMouseDown,
                                    .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: holdCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fputs("\(name): could not create event tap (Accessibility?)\n", stderr)
            return
        }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    private func stop() {
        dismiss()
        state = .idle
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
        (self.tap, source) = (nil, nil)
    }

    /// Whether to let the event through.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged where isKeyboard:
            // The binding's modifiers all let go: take the pick.
            if !openedWith.isEmpty, event.flags.intersection(openedWith).isEmpty {
                state = .idle
                commit()
                settle()
            }
        case .flagsChanged:
            modifiersChanged(event.flags)
        case .keyDown where isKeyboard:
            return keyboardKey(event)
        case .keyDown:
            if isShowing, event.getIntegerValueField(.keyboardEventKeycode) == Self.escape {
                dismiss()
                return false
            }
            dismiss()
        case .mouseMoved, .leftMouseDragged:
            if case .showing = state { moved(event.location) }
            if pointerPicks(at: event.location) { moved(event.location) }
        case .scrollWheel where byFingers:
            // The swiping fingers scroll too, and their momentum goes on after they lift: none of it is for the app.
            return false
        case .leftMouseDown where pointerPicks(at: event.location):
            state = .idle
            swallowUp = true
            commit()
            return false
        case .leftMouseUp:
            guard swallowUp else { return true }
            // Its press committed; the tap goes once the release is swallowed too.
            swallowUp = false
            settle()
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
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == Self.escape {
            dismiss()
        } else if let n = Self.digits[code], pickNumber(n) {
            // A digit picks what it numbers and takes it at once.
            state = .idle
            commit()
            settle()
        } else if Self.confirms.contains(code) {
            state = .idle
            commit()
            settle()
        } else if code == Self.tab {
            cycle(!event.flags.contains(.maskShift))
        } else if let direction = Self.directions[code], !event.flags.contains(.maskCommand) {
            navigate(direction)
        } else if event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    || AppState.shared.hotkeys.commands(for: event)?.contains(name) == true {
            // The binding that showed it, again or held down: its command steps the pick.
            return true
        } else {
            dismiss()
            return true
        }
        return false
    }

    private func modifiersChanged(_ flags: CGEventFlags) {
        guard let target = modifierFlags.first(where: { $0.setting == keyPath(modifier) }) else { return }
        let held = flags.contains(target.mask)
        let alone = held && target.isHeld(by: sides, in: flags)
            && !modifierFlags.contains { $0.mask != target.mask && flags.contains($0.mask) }
        switch state {
        case .idle:
            if alone { arm() }
        case .arming(let work):
            guard !alone else { return }
            work.cancel()
            state = held ? .spoiled : .idle
        case .showing:
            if !held {
                state = .idle
                commit()
            }
        case .spoiled:
            if !held { state = .idle }
        case .keyboard:
            break
        }
    }

    private func keyPath(_ modifier: SwitcherModifier) -> KeyPath<ModifierSides, ModifierSide>? {
        switch modifier {
        case .none: nil
        case .alt: \.alt
        case .ctrl: \.ctrl
        case .cmd: \.cmd
        case .shift: \.shift
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

private func holdCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                          refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<ModifierHold>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}
