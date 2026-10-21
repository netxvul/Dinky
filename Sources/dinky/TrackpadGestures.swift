import AppKit
import DinkyConfig
import DinkyPrivate

// `[gestures.trackpad]`: a swipe on the trackpad with `fingers` fingers runs its commands, as a key binding does. It starts
// as that many fingers are down, the first of them no more than `gather` seconds before, and is a swipe once their
// centre has moved `distance` millimetres, mostly one way, within `window` seconds; anything else, or another
// finger, spends it until every finger is up. Fingers gathering slowly, as a third joining two that scroll or a
// thumb coming to rest, are no swipe. A swipe that
// showed a switcher drives it with the same fingers, or with however many of them stay down, more or fewer: every
// `step` millimetres they move is a step of the pick, and lifting them all takes it, as releasing a switcher's
// modifier does. Lifted before a step, the
// switcher stays up for the pointer, and fingers landing again drive it once more. `[gestures.mouse]` does the same
// on a Magic Mouse with its own lengths, but fingers resting on it are no reason to wait for them all to land
// together, lifted fingers may land again soon and go on, as `ModifierHold.fingersLifted` waits for them, and,
// swiping with more, two fingers drive nothing, since macOS may swipe two across the mouse between
// full-screen apps. Each
// trackpad and mouse has its own swipe. Touches arrive on MultitouchSupport's thread, so the swipes are kept under a
// lock and only what they do goes to the main thread.
final class TrackpadGestures {
    static let shared = TrackpadGestures()
    /// Seconds from the first finger landing within which the rest must, for a swipe on a trackpad.
    private static let gather: Double = 0.15
    /// Seconds from the fingers landing within which they must swipe.
    private static let window: Double = 0.6

    private enum Phase {
        case idle
        /// Fewer than `fingers` are down, the first since `time`.
        case gathering(time: Double)
        /// The fingers are down, not yet a swipe.
        case landed(at: CGPoint, time: Double)
        /// A swipe ran its commands; the fingers drive whatever it showed. `anchor` is where the last step was, with
        /// `down` fingers.
        case driving(anchor: CGPoint, down: Int, stepped: Bool)
        /// Nothing until every finger is up.
        case spent
    }

    /// What swipes on one kind of device, the trackpads or the mice.
    private struct Settings {
        var fingers = 3
        var distance: CGFloat = 15
        var step: CGFloat = 12
        var swipes: [GestureSwipe: [String]] = [:]
    }

    private let lock = NSLock()
    /// Each device's swipe, by the device.
    private var phases: [UInt: Phase] = [:]
    private var trackpad = Settings()
    private var mouse = Settings()
    /// Whether the trackpads are being read. Main thread.
    private var running = false

    /// Reads the trackpads and mice while dinky is enabled and a swipe is bound. Main thread.
    func update(config: Gestures, enabled: Bool) {
        let trackpad = Settings(fingers: config.trackpad.fingers, distance: config.trackpad.distance,
                                step: config.trackpad.step, swipes: config.trackpadSwipes)
        let mouse = Settings(fingers: config.mouse.fingers, distance: config.mouse.distance, step: config.mouse.step,
                             swipes: config.mouseSwipes)
        lock.withLock {
            self.trackpad = trackpad
            self.mouse = mouse
            phases = [:]
        }
        let wanted = enabled && !(trackpad.swipes.isEmpty && mouse.swipes.isEmpty)
        if wanted, !running {
            running = dinky_touches_start { [unowned self] fingers, x, y, time, device, mouse in
                frame(fingers: Int(fingers), at: CGPoint(x: x, y: y), time: time, device: device, mouse: mouse)
            }
            if !running { fputs("gestures: MultitouchSupport's calls are missing\n", stderr) }
        } else if !wanted, running {
            dinky_touches_stop()
            running = false
        }
    }

    /// What a frame makes the main thread do.
    private enum Action {
        /// The fingers are down, which drive a switcher a swipe left up.
        case landed
        case run([String])
        case move(steps: Int, rows: Int)
        case lift(stepped: Bool)
    }

    private func frame(fingers down: Int, at point: CGPoint, time: Double, device: UInt, mouse: Bool) {
        let action: Action? = lock.withLock {
            let settings = mouse ? self.mouse : trackpad
            guard !settings.swipes.isEmpty else { return nil }
            var phase = phases[device] ?? .idle
            defer { phases[device] = phase }
            let fingers = settings.fingers
            switch phase {
            case .idle:
                if down == fingers {
                    phase = .landed(at: point, time: time)
                    return .landed
                } else if down > fingers {
                    phase = .spent
                } else if down > 0 {
                    phase = .gathering(time: time)
                }
                return nil
            case .gathering(let since):
                if down == 0 {
                    phase = .idle
                } else if down == fingers, mouse || time - since <= Self.gather {
                    // Fingers rest on a mouse as it is held, so the last to land starts the swipe.
                    phase = .landed(at: point, time: time)
                    return .landed
                } else if down >= fingers {
                    phase = .spent
                }
                return nil
            case .landed(let start, let since):
                guard down == fingers else {
                    // A finger lifting off a mouse goes back to resting on it.
                    phase = down == 0 ? .idle : mouse && down < fingers ? .gathering(time: time) : .spent
                    return nil
                }
                let (dx, dy) = (point.x - start.x, point.y - start.y)
                guard max(abs(dx), abs(dy)) >= settings.distance else {
                    if time - since > Self.window { phase = .spent }
                    return nil
                }
                // Mostly one way; the surface's y goes up.
                let swipe: GestureSwipe? = abs(dx) >= 2 * abs(dy) ? (dx > 0 ? .swipeRight : .swipeLeft)
                                         : abs(dy) >= 2 * abs(dx) ? (dy > 0 ? .swipeUp : .swipeDown) : nil
                guard let swipe, let commands = settings.swipes[swipe] else {
                    phase = .spent
                    return nil
                }
                phase = .driving(anchor: point, down: down, stepped: false)
                return .run(commands)
            case .driving(var anchor, let was, let stepped):
                if down == 0 {
                    phase = .idle
                    return .lift(stepped: stepped)
                }
                // A finger lifting or landing moves their centre without them moving: measure afresh from there.
                // Two on a mouse may swipe between full-screen apps, so unless they are what swipes there they only
                // keep it measured afresh.
                guard down == was, !(mouse && down == 2 && fingers != 2) else {
                    phase = .driving(anchor: point, down: down, stepped: stepped)
                    return nil
                }
                // A step each time the fingers get a whole `step` from where the last one was, so a tremor at the
                // edge of one never steps back and forth.
                let step = settings.step
                let steps = Int((point.x - anchor.x) / step), rows = Int((anchor.y - point.y) / step)
                guard steps != 0 || rows != 0 else { return nil }
                anchor.x += CGFloat(steps) * step
                anchor.y -= CGFloat(rows) * step
                phase = .driving(anchor: anchor, down: down, stepped: true)
                return .move(steps: steps, rows: rows)
            case .spent:
                // A mouse is seldom let go of entirely: fewer fingers than swipe on it are resting ones.
                if down == 0 {
                    phase = .idle
                } else if mouse, down < fingers {
                    phase = .gathering(time: time)
                }
                return nil
            }
        }
        guard let action else { return }
        DispatchQueue.main.async {
            switch action {
            case .landed:
                if ModifierHold.driven?.byFingers == true { self.adopt(device, mouse: mouse) }
            case .run(let commands):
                guard AppState.shared.enabled else { return }
                // A mouse has nothing to tick; the trackpad would, under the other hand.
                if !mouse { _ = dinky_trackpad_tap(4) }
                ModifierHold.gesturing = true
                ModifierHold.fingersOnMouse = mouse
                defer { ModifierHold.gesturing = false }
                runBound(commands)
            case .move(let steps, let rows):
                ModifierHold.driven?.fingersMoved(steps: steps, rows: rows)
            case .lift(let stepped):
                ModifierHold.driven?.fingersLifted(stepped: stepped)
            }
        }
    }

    /// Fingers that just landed drive the switcher a swipe left up, from where they landed.
    private func adopt(_ device: UInt, mouse: Bool) {
        let adopted = lock.withLock {
            guard case .landed(let point, _) = phases[device] else { return false }
            phases[device] = .driving(anchor: point, down: (mouse ? self.mouse : trackpad).fingers, stepped: false)
            return true
        }
        if adopted {
            ModifierHold.fingersOnMouse = mouse
            ModifierHold.driven?.fingersLanded()
        }
    }
}
