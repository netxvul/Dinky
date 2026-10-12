import AppKit
import DinkyConfig
import DinkyLayout

// Dragging a tiled window from anywhere in it while `[drag] modifier` is held, as yabai's mouse_modifier does. A
// default tap takes the left button's down, drags and up from the app under the pointer for a drag of its own, so
// the app never sees the click. dinky moves the window itself, keeping the spot that was grabbed under the pointer,
// and on release hands it to the coordinator, which drops it by zone (Drag.swift). A click with the modifier anywhere
// else, or with other modifiers too, goes to the app as usual. Main thread only, but for the window's moves: each is
// a round trip to the app over Accessibility, so they go to a queue of their own (`Mover`), and the tap and the
// placeholders never wait on a slow app.
final class ModifierDrag {
    private var modifier: KeyCombo.Modifiers = []
    private var sides = ModifierSides()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var grab: Grab?
    private var placeholdersQueued = false
    private let mover = Mover()

    private struct Grab {
        let id: WindowID
        /// The grabbed spot, from the window's top-left corner.
        let offset: CGPoint
        let start: CGPoint
        var pointer: CGPoint
        /// Whether the pointer has gone `minimumMove` from where it grabbed; until then the window stays put.
        var moved = false
        var lastEvent = uptime()
    }

    private static let minimumMove: CGFloat = 3
    /// How long without an event of the drag before a released button is taken to mean the release was missed.
    private static let missedRelease: UInt64 = 500_000_000

    /// Starts or stops the tap for this config. Called at startup and on every config load.
    func update(config: Drag, sides: ModifierSides) {
        modifier = config.modifier
        self.sides = sides
        if modifier.isEmpty {
            end()
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseDragged.rawValue
            | 1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: modifierDragCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fputs("drag: could not create event tap (Accessibility?)\n", stderr)
            return
        }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
        (self.tap, source) = (nil, nil)
    }

    /// Nil swallows the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off that keeps it waiting; a mouse-down meanwhile went to the app.
            print("\(stamp()) drag: tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), enabling again")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown:
            // A drag whose release the tap missed ends here.
            end()
            return held(event.flags) && begin(at: event.location) ? nil : pass
        case .leftMouseDragged:
            guard grab != nil else { return pass }
            follow(event.location)
            return nil
        case .leftMouseUp:
            guard grab != nil else { return pass }
            end()
            return nil
        default:
            return pass
        }
    }

    /// Exactly the configured modifiers, each from a key `[modifiers]` allows.
    private func held(_ flags: CGEventFlags) -> Bool {
        modifierFlags.allSatisfy { flag in
            (flags.contains(flag.mask) && flag.isHeld(by: sides, in: flags)) == modifier.contains(flag.modifier)
        }
    }

    /// Grabs the frontmost window at `point` if it is a tile on a current Space. Hover's rules for what is on screen
    /// apply: nothing while a menu or modal panel is open.
    private func begin(at point: CGPoint) -> Bool {
        let state = AppState.shared
        guard state.enabled, !MissionControl.shared.active, let coordinator = state.coordinator,
              let id = OnScreenWindows().window(at: point), coordinator.placements[id]?.space != nil,
              let window = coordinator.model.windows[id] else { return false }
        guard coordinator.beginModifierDrag(id) else { return false }
        let offset = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        grab = Grab(id: id, offset: offset, start: point, pointer: point)
        mover.begin(pid: window.pid, id: id)
        watchRelease()
        return true
    }

    /// Takes the pointer's new spot and queues a write, so a burst of drag events moves the window once.
    private func follow(_ point: CGPoint) {
        guard var grab else { return }
        grab.pointer = point
        grab.lastEvent = uptime()
        if hypot(point.x - grab.start.x, point.y - grab.start.y) >= Self.minimumMove { grab.moved = true }
        self.grab = grab
        guard grab.moved else { return }
        mover.move(to: CGPoint(x: point.x - grab.offset.x, y: point.y - grab.offset.y))
        // The drop's zone follows the pointer, not the window, so the placeholders need not wait for it; once per
        // pass of the run loop is enough.
        guard !placeholdersQueued else { return }
        placeholdersQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.placeholdersQueued = false
            if self?.grab != nil { AppState.shared.coordinator?.showPlaceholders() }
        }
    }

    private func end() {
        guard let grab else { return }
        self.grab = nil
        // Dropped by where the pointer is now; the retile waits for the window's last move to land.
        let mover = mover
        AppState.shared.coordinator?.endModifierDrag(grab.id, moved: grab.moved) { retile in mover.end(grab.id, retile) }
    }

    /// The tap can be disabled for a moment and miss the release; then the button is up and the drag has gone quiet.
    private func watchRelease() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let grab = self.grab else { return }
            if !CGEventSource.buttonState(.hidSystemState, button: .left), uptime() - grab.lastEvent > Self.missedRelease {
                self.end()
            } else {
                self.watchRelease()
            }
        }
    }
}

/// Moves the dragged window on a queue of its own, always to the latest spot asked for: moves asked for while one
/// is under way collapse into the next. The window's Accessibility element is looked up there too, on the first move.
private final class Mover: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dinky.drag.mover", qos: .userInteractive)
    private let lock = NSLock()
    private var target: (pid: pid_t, id: WindowID)?
    private var element: AXUIElement?
    private var pending: CGPoint?
    private var draining = false
    /// For the log at the end of a drag: moves asked for, writes made, and the slowest write.
    private var asked = 0, written = 0, slowest: UInt64 = 0

    /// Main thread.
    func begin(pid: pid_t, id: WindowID) {
        lock.withLock { (target, element, pending, asked, written, slowest) = ((pid, id), nil, nil, 0, 0, 0) }
    }

    /// Main thread.
    func move(to origin: CGPoint) {
        let start = lock.withLock { () -> Bool in
            pending = origin
            asked += 1
            defer { draining = true }
            return !draining
        }
        if start { queue.async { self.drain() } }
    }

    /// Main thread. `done` runs on the main thread once the moves asked for so far have been written. A drag that has
    /// begun since is left alone.
    func end(_ id: WindowID, _ done: @escaping @MainActor () -> Void) {
        queue.async {
            let counts = self.lock.withLock { () -> (Int, Int, UInt64)? in
                guard self.target?.id == id else { return nil }
                (self.target, self.element, self.pending) = (nil, nil, nil)
                return (self.asked, self.written, self.slowest)
            }
            if let (asked, written, slowest) = counts, asked > 0 {
                print("\(stamp()) drag: \(id) moved \(written) times for \(asked) drag events, slowest write \(slowest / 1_000_000) ms")
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }

    private func drain() {
        while true {
            let next = lock.withLock { () -> (CGPoint, pid_t, WindowID, AXUIElement?)? in
                guard let origin = pending, let target else {
                    draining = false
                    return nil
                }
                pending = nil
                return (origin, target.pid, target.id, element)
            }
            guard let (point, pid, id, known) = next else { return }
            var origin = point
            guard let window = known ?? axWindow(pid: pid, wid: id, timeout: 0.25) else { continue }
            if known == nil { lock.withLock { if target?.id == id { element = window } } }
            let start = uptime()
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
            let took = uptime() - start
            lock.withLock { written += 1; slowest = max(slowest, took) }
        }
    }
}

private func modifierDragCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                  refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<ModifierDrag>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}
