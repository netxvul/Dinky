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
//
// `[gestures.scroll]`: its `fingers` fingers on a trackpad scroll the strip instead, once they have moved
// `scrollStart` of its width across (about 2 mm) and twice as far across as up or down. That first stretch goes over
// at once, then each frame's, in trackpad widths, a still frame's too, so the coordinator hears the fingers are still
// down; their speed across, smoothed over the frames by the trackpad's own times, goes with the end, when they lift
// or a finger lands or lifts. They may rest before they move. Up or down, the same fingers still swipe as
// `[gestures.trackpad]` binds them, soon after they land as ever. Fingers still landing within `gather` of the first
// may pass through another count on the way, as three on the way to four, and land as the last: fingers that scroll,
// where more may yet join them, wait till `gather` is up.

/// A scroll of the strip by `[gestures.scroll]`'s fingers, in trackpad widths, to the right positive. Main thread.
enum FingerScroll {
    /// The fingers moved across far enough to scroll: `dx` is that first stretch.
    case began(dx: Double)
    /// They moved on, or held still (`dx` 0).
    case moved(dx: Double)
    /// They lifted, or a finger landed or lifted, moving across at `velocity` widths a second; 0 for a scroll cut
    /// short.
    case ended(velocity: Double)
}

final class TrackpadGestures {
    static let shared = TrackpadGestures()
    /// Seconds from the first finger landing within which the rest must, for a swipe on a trackpad.
    private static let gather: Double = 0.15
    /// Seconds from the fingers landing within which they must swipe.
    private static let window: Double = 0.6
    /// How far fingers move across before they scroll, as a share of the trackpad's width: about 2 mm.
    private static let scrollStart = 0.015

    private enum Phase {
        case idle
        /// Fewer fingers are down than swipe or scroll, the first since `time`.
        case gathering(time: Double)
        /// `down` fingers are down since `time`, not yet a swipe or a scroll; the first of them landed at `first`.
        case landed(at: CGPoint, time: Double, down: Int, first: Double)
        /// A swipe ran its commands; the fingers drive whatever it showed. `anchor` is where the last step was, with
        /// `down` fingers.
        case driving(anchor: CGPoint, down: Int, stepped: Bool)
        /// `down` fingers scroll the strip, last at `at` at `time`, moving across at `velocity` millimetres a second.
        case scrolling(at: CGPoint, time: Double, velocity: Double, down: Int)
        /// Nothing until every finger is up.
        case spent
    }

    /// What swipes on one kind of device, the trackpads or the mice.
    private struct Settings {
        var fingers = 3
        var distance: CGFloat = 15
        var step: CGFloat = 12
        var swipes: [GestureSwipe: [String]] = [:]
        /// How many fingers scroll the strip; nil while `[gestures.scroll]` is off, and on a mouse.
        var scrollFingers: Int? = nil

        /// The finger counts that land: the swiping one while a swipe is bound, and the scrolling one.
        var counts: [Int] {
            var counts = swipes.isEmpty ? [] : [fingers]
            if let scrollFingers { counts.append(scrollFingers) }
            return counts
        }
    }

    private let lock = NSLock()
    /// Each device's swipe, by the device.
    private var phases: [UInt: Phase] = [:]
    /// Bumped by `update` as it starts every device over, so a scroll queued for the main thread before then is
    /// known as stale there. Under `lock`.
    private var generation = 0
    private var trackpad = Settings()
    private var mouse = Settings()
    /// Whether the trackpads are being read. Main thread.
    private var running = false

    /// Reads the trackpads and mice while dinky is enabled and a swipe is bound or the strip scrolls. Main thread.
    func update(config: Gestures, enabled: Bool) {
        let trackpad = Settings(fingers: config.trackpad.fingers, distance: config.trackpad.distance,
                                step: config.trackpad.step, swipes: config.trackpadSwipes,
                                scrollFingers: config.scroll.enabled ? config.scroll.fingers : nil)
        let mouse = Settings(fingers: config.mouse.fingers, distance: config.mouse.distance, step: config.mouse.step,
                             swipes: config.mouseSwipes)
        let wasScrolling: Bool = lock.withLock {
            let scrolling = phases.values.contains { phase in
                if case .scrolling = phase { return true }
                return false
            }
            self.trackpad = trackpad
            self.mouse = mouse
            generation &+= 1
            phases = [:]
            return scrolling
        }
        // A scroll cut short by a reload, or by dinky turning off, ends where it is.
        if wasScrolling { AppState.shared.coordinator?.fingersScrolled(.ended(velocity: 0)) }
        let wanted = enabled && !(trackpad.counts.isEmpty && mouse.counts.isEmpty)
        if wanted, !running {
            running = dinky_touches_start { [unowned self] fingers, x, y, time, device, mouse, width in
                frame(fingers: Int(fingers), at: CGPoint(x: x, y: y), time: time, device: device, mouse: mouse,
                      width: width)
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
        case scroll(FingerScroll)
    }

    /// `width` is the surface's, in millimetres.
    private func frame(fingers down: Int, at point: CGPoint, time: Double, device: UInt, mouse: Bool, width: Double) {
        var made = 0
        let action: Action? = lock.withLock {
            made = generation
            let settings = mouse ? self.mouse : trackpad
            let counts = settings.counts
            guard let fewest = counts.min(), let most = counts.max() else { return nil }
            var phase = phases[device] ?? .idle
            defer { phases[device] = phase }
            let fingers = settings.fingers
            /// Whether `n` fingers are those that swipe: landing, they drive a switcher a swipe left up.
            func swiping(_ n: Int) -> Bool { !settings.swipes.isEmpty && n == fingers }
            switch phase {
            case .idle:
                if counts.contains(down) {
                    phase = .landed(at: point, time: time, down: down, first: time)
                    return swiping(down) ? .landed : nil
                } else if down > most {
                    phase = .spent
                } else if down > 0 {
                    phase = .gathering(time: time)
                }
                return nil
            case .gathering(let since):
                // Fingers rest on a mouse as it is held, so the last to land starts the swipe.
                let timely = mouse || time - since <= Self.gather
                if down == 0 {
                    phase = .idle
                } else if counts.contains(down), timely {
                    phase = .landed(at: point, time: time, down: down, first: since)
                    return swiping(down) ? .landed : nil
                } else if down > most || (!timely && down >= fewest) {
                    phase = .spent
                }
                return nil
            case .landed(let start, let since, let count, let first):
                guard down == count else {
                    if down == 0 {
                        phase = .idle
                    } else if mouse {
                        // A finger lifting off a mouse goes back to resting on it.
                        phase = down < fingers ? .gathering(time: time) : .spent
                    } else if down > count, down <= most, time - first <= Self.gather {
                        // Still landing, as a fourth finger just after three: they may yet scroll or swipe.
                        guard counts.contains(down) else {
                            phase = .gathering(time: first)
                            return nil
                        }
                        phase = .landed(at: point, time: time, down: down, first: first)
                        return swiping(down) ? .landed : nil
                    } else {
                        phase = .spent
                    }
                    return nil
                }
                let (dx, dy) = (point.x - start.x, point.y - start.y)
                let scrolls = count == settings.scrollFingers
                // Still landing, as three on the way to the four that swipe: more may come, so no scroll till `gather`
                // is up. Their way across since they landed then goes over at once.
                let landing = time - first <= Self.gather && counts.contains { $0 > count }
                // Across, the fingers that scroll do so long before they would be a swipe.
                if scrolls, !landing, Double(abs(dx)) > Self.scrollStart * width, abs(dx) > 2 * abs(dy) {
                    phase = .scrolling(at: point, time: time, velocity: 0, down: down)
                    return .scroll(.began(dx: Double(dx) / width))
                }
                // Fingers that only swipe must do so soon after they land, as must those that also scroll, but those
                // may rest before they move across.
                let late = time - since > Self.window
                guard swiping(count), !(scrolls && late), max(abs(dx), abs(dy)) >= settings.distance else {
                    if !scrolls, late { phase = .spent }
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
            case .scrolling(let last, let when, let velocity, let count):
                guard down == count else {
                    // Lifted, or a finger landed or lifted: the scroll ends at the speed it had.
                    phase = down == 0 ? .idle : .spent
                    return .scroll(.ended(velocity: velocity / width))
                }
                let dx = Double(point.x - last.x)
                // Smoothed, by the trackpad's own frame times rather than when the frames got here.
                let speed = 0.7 * velocity + 0.3 * dx / max(time - when, 0.001)
                phase = .scrolling(at: point, time: time, velocity: speed, down: down)
                // Still frames too, so the coordinator hears the fingers are down.
                return .scroll(.moved(dx: dx / width))
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
        let queuedIn = made
        DispatchQueue.main.async {
            switch action {
            case .landed:
                if ModifierHold.driven?.byFingers == true { self.adopt(device, mouse: mouse) }
            case .run(let commands):
                guard AppState.shared.enabled else { return }
                // A mouse has nothing to tick; the trackpad would, under the other hand.
                if !mouse {
                    print("\(stamp()) haptic: trackpad swipe ran \(commands.joined(separator: ", "))")
                    fflush(stdout)
                    _ = dinky_trackpad_tap(4)
                }
                ModifierHold.gesturing = true
                ModifierHold.fingersOnMouse = mouse
                defer { ModifierHold.gesturing = false }
                runBound(commands)
            case .move(let steps, let rows):
                ModifierHold.driven?.fingersMoved(steps: steps, rows: rows)
            case .lift(let stepped):
                ModifierHold.driven?.fingersLifted(stepped: stepped)
            case .scroll(let scroll):
                // Off, dinky moves nothing; `update` ended any scroll as it turned off or reloaded. A start queued before
                // then would take hold of the strip after that end, for fingers it no longer follows. A move or an end
                // queued before finds nothing held, or is the last of a scroll that update did not see.
                guard AppState.shared.enabled else { return }
                if case .began = scroll, queuedIn != self.lock.withLock({ self.generation }) { return }
                AppState.shared.coordinator?.fingersScrolled(scroll)
            }
        }
    }

    /// Fingers that just landed drive the switcher a swipe left up, from where they landed.
    private func adopt(_ device: UInt, mouse: Bool) {
        let adopted = lock.withLock { () -> Bool in
            let fingers = (mouse ? self.mouse : trackpad).fingers
            // Landed as the fingers that swipe, and not since joined by more that scroll.
            let point: CGPoint
            switch phases[device] {
            case .landed(let at, _, let count, _) where count == fingers: point = at
            // The same fingers scroll, and moved across before this got here: the scroll they set off finds a
            // switcher showing and takes nothing (`beginStripScroll`), so they drive it instead.
            case .scrolling(let at, _, _, let count) where count == fingers: point = at
            default: return false
            }
            phases[device] = .driving(anchor: point, down: fingers, stepped: false)
            return true
        }
        if adopted {
            ModifierHold.fingersOnMouse = mouse
            ModifierHold.driven?.fingersLanded()
        }
    }

    /// `dinky debug scroll-gesture <millimetres> [<milliseconds>] [<before-ms>] [<after-ms>]`, for tests:
    /// `[gestures.scroll]`'s fingers land on a trackpad that is not there, 130 mm wide, rest `before-ms`, move
    /// `millimetres` across, to the right positive, over `milliseconds` (300 by default), rest `after-ms` and lift, a
    /// frame every 10 ms, through the same recogniser as a real trackpad's. Answers at once; the frames follow off the
    /// main thread. Main thread.
    func debug(_ args: [String]) -> Reply {
        let usage = "usage: dinky debug scroll-gesture <millimetres> [<milliseconds>] [<before-ms>] [<after-ms>]"
        let numbers = args.dropFirst().compactMap { Double($0) }
        guard args.first == "scroll-gesture", (1...4).contains(numbers.count), numbers.count == args.count - 1 else {
            return .error(usage)
        }
        let distance = numbers[0], duration = numbers.count > 1 ? numbers[1] : 300
        let before = numbers.count > 2 ? numbers[2] : 0, after = numbers.count > 3 ? numbers[3] : 0
        guard abs(distance) <= 1000, (10...10_000).contains(duration), (0...10_000).contains(before),
              (0...10_000).contains(after) else { return .error(usage) }
        guard let fingers = lock.withLock({ trackpad.scrollFingers }) else { return .error("[gestures.scroll] is off") }
        let width = 130.0, from = width / 2 - distance / 2, y = 40.0
        let resting = Int((before / 10).rounded()) + 1, moving = max(1, Int((duration / 10).rounded()))
        let lingering = Int((after / 10).rounded())
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            let start = CACurrentMediaTime()
            var frames = 0
            func send(_ down: Int, at x: Double) {
                self.frame(fingers: down, at: CGPoint(x: x, y: y), time: start + Double(frames) / 100, device: UInt.max,
                           mouse: false, width: width)
                frames += 1
                Thread.sleep(forTimeInterval: 0.01)
            }
            for _ in 0..<resting { send(fingers, at: from) }
            for i in 1...moving { send(fingers, at: from + distance * Double(i) / Double(moving)) }
            for _ in 0..<lingering { send(fingers, at: from + distance) }
            send(0, at: from + distance)
        }
        return .ok("")
    }
}
