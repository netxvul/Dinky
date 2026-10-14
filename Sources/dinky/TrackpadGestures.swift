import AppKit
import DinkyConfig
import DinkyPrivate

// `[gestures]`: a swipe on the trackpad with `fingers` fingers runs its commands, as a key binding does. It starts
// as that many fingers are down and is a swipe once their centre has moved `trigger` millimetres, mostly one way,
// within `window` seconds; anything else, or another finger, spends it until every finger is up. A swipe that
// showed a switcher drives it with the same fingers: every `step` millimetres they move is a step of the pick, and
// lifting them takes it, as releasing a switcher's modifier does; another finger closes it. Lifted before a step, the
// switcher stays up for the pointer, and fingers landing again drive it once more. Touches arrive on
// MultitouchSupport's thread, so the swipe is kept under a lock and only what it does goes to the main thread.
final class TrackpadGestures {
    static let shared = TrackpadGestures()
    /// Millimetres the fingers move before it is a swipe.
    private static let trigger: CGFloat = 10
    /// Seconds from the fingers landing within which they must swipe.
    private static let window: Double = 0.6

    private enum Phase {
        case idle
        /// The fingers are down, not yet a swipe.
        case landed(device: UInt, at: CGPoint, time: Double)
        /// A swipe ran its commands; the fingers drive whatever it showed. `anchor` is where the last step was.
        case driving(device: UInt, anchor: CGPoint, stepped: Bool)
        /// Nothing until every finger is up.
        case spent(device: UInt)
    }

    private let lock = NSLock()
    private var phase = Phase.idle
    private var fingers = 3
    private var step: CGFloat = 12
    private var swipes: [GestureSwipe: [String]] = [:]
    /// Whether the trackpads are being read. Main thread.
    private var running = false

    /// Reads the trackpads while dinky is enabled and a swipe is bound. Main thread.
    func update(config: Gestures, enabled: Bool) {
        lock.withLock {
            fingers = config.fingers
            step = config.step
            swipes = config.swipes
            phase = .idle
        }
        let wanted = enabled && !config.swipes.isEmpty
        if wanted, !running {
            running = dinky_touches_start { [unowned self] fingers, x, y, time, device in
                frame(fingers: Int(fingers), at: CGPoint(x: x, y: y), time: time, device: device)
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
        case landed(UInt)
        case run([String])
        case move(steps: Int, rows: Int)
        case lift(stepped: Bool)
        case cancel
    }

    private func frame(fingers down: Int, at point: CGPoint, time: Double, device: UInt) {
        let action: Action? = lock.withLock {
            switch phase {
            case .idle:
                if down == fingers {
                    phase = .landed(device: device, at: point, time: time)
                    return .landed(device)
                } else if down > fingers {
                    phase = .spent(device: device)
                }
                return nil
            case .landed(let landed, let start, let since):
                guard device == landed else { return nil }
                guard down == fingers else {
                    phase = down == 0 ? .idle : .spent(device: device)
                    return nil
                }
                let (dx, dy) = (point.x - start.x, point.y - start.y)
                guard max(abs(dx), abs(dy)) >= Self.trigger else {
                    if time - since > Self.window { phase = .spent(device: device) }
                    return nil
                }
                // Mostly one way; the trackpad's y goes up.
                let swipe: GestureSwipe? = abs(dx) >= 2 * abs(dy) ? (dx > 0 ? .swipeRight : .swipeLeft)
                                         : abs(dy) >= 2 * abs(dx) ? (dy > 0 ? .swipeUp : .swipeDown) : nil
                guard let swipe, let commands = swipes[swipe] else {
                    phase = .spent(device: device)
                    return nil
                }
                phase = .driving(device: device, anchor: point, stepped: false)
                return .run(commands)
            case .driving(let driving, var anchor, let stepped):
                guard device == driving else { return nil }
                if down > fingers {
                    phase = .spent(device: device)
                    return .cancel
                }
                if down < fingers {
                    phase = down == 0 ? .idle : .spent(device: device)
                    return .lift(stepped: stepped)
                }
                // A step each time the fingers get a whole `step` from where the last one was, so a tremor at the
                // edge of one never steps back and forth.
                let steps = Int((point.x - anchor.x) / step), rows = Int((anchor.y - point.y) / step)
                guard steps != 0 || rows != 0 else { return nil }
                anchor.x += CGFloat(steps) * step
                anchor.y -= CGFloat(rows) * step
                phase = .driving(device: device, anchor: anchor, stepped: true)
                return .move(steps: steps, rows: rows)
            case .spent(let spent):
                if device == spent, down == 0 { phase = .idle }
                return nil
            }
        }
        guard let action else { return }
        DispatchQueue.main.async {
            switch action {
            case .landed(let device):
                if ModifierHold.driven?.byFingers == true { self.adopt(device) }
            case .run(let commands):
                guard AppState.shared.enabled else { return }
                _ = dinky_trackpad_tap(4)
                ModifierHold.gesturing = true
                defer { ModifierHold.gesturing = false }
                runBound(commands)
            case .move(let steps, let rows):
                ModifierHold.driven?.fingersMoved(steps: steps, rows: rows)
            case .lift(let stepped):
                ModifierHold.driven?.fingersLifted(stepped: stepped)
            case .cancel:
                ModifierHold.driven?.dismiss()
            }
        }
    }

    /// Fingers that just landed drive the switcher a swipe left up, from where they landed.
    private func adopt(_ device: UInt) {
        lock.withLock {
            guard case .landed(let landed, let point, _) = phase, landed == device else { return }
            phase = .driving(device: device, anchor: point, stepped: false)
        }
    }
}
