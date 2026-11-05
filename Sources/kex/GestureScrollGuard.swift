import AppKit
import KexConfig
import KexLayout

// `[gestures] swallow-scroll`: fingers that swipe or scroll the strip scroll too, as far as macOS is concerned, and the
// app under the pointer would scroll with them, before the swipe is known, through a swipe whose commands show nothing,
// and on with the momentum after they lift. `ModifierHold` swallows scrolls only while a swipe drives a switcher; this
// takes the rest. `ScrollGuard` decides each event; this hears them.
//
// The tap swallows, so every scroll it is given waits on it: it is on only while a gesture's fingers are down
// (`TrackpadGestures` says so as they land and lift, on MultitouchSupport's thread) or a stroke it took still has events
// or momentum to come, and off otherwise, so scrolling with fewer fingers never passes through kex. It runs on a
// thread of its own rather than the main one, which an animation or an app slow to answer AX can keep busy for longer
// than a scroll should wait: what it decides needs nothing of the main thread. A stroke the tap went on in the middle
// of, as fingers landed on one already going to the app, is heard first mid-way, and ended for the app there.
//
// A stroke with `[gestures.mouse-scroll]`'s modifier held is that table's, which takes it whatever the fingers.
final class GestureScrollGuard {
    static let shared = GestureScrollGuard()

    /// What the tap's thread reads of the config. Under `lock`.
    private struct Settings {
        var enabled = false
        /// `[gestures.mouse-scroll]`'s modifier, while its wheel is on.
        var strip: KeyCombo.Modifiers?
        var sides = ModifierSides()
    }

    private let lock = NSLock()
    /// Under `lock`.
    private var settings = Settings()
    /// Whether a gesture's fingers are down on some device. Under `lock`.
    private var fingersDown = false
    /// Whether the tap is on. Under `lock`, which turning it on or off holds, so the two threads that do never cross.
    private var on = false
    /// Set once, as the tap's thread starts. Under `lock`.
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    /// Main thread.
    private var started = false
    /// The tap's thread only.
    private var stroke = ScrollGuard()

    /// Main thread.
    func update(config: Gestures, modifiers: ModifierSides, enabled: Bool) {
        let mouseScroll = config.mouseScroll
        let settings = Settings(enabled: enabled && config.swallowScroll,
                                strip: mouseScroll.enabled && mouseScroll.wheel ? mouseScroll.modifier : nil,
                                sides: modifiers)
        if settings.enabled, !started {
            started = true
            start()
        }
        lock.withLock { self.settings = settings }
        // Turned off, the tap goes off with the stroke it had; turned on, the next fingers to land turn it on.
        settle()
    }

    /// A gesture's fingers came down on some device, or the last of them lifted. Any thread.
    func fingers(down: Bool) {
        lock.withLock {
            fingersDown = down
            // On at once, before the first scroll they make gets past.
            if down, settings.enabled, !on, let port {
                CGEvent.tapEnable(tap: port, enable: true)
                on = true
            }
        }
        // Off only on the tap's own thread, which knows whether a stroke it took is still going.
        if !down { settle() }
    }

    private func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                               options: .defaultTap, eventsOfInterest: mask,
                                               callback: gestureScrollCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()),
                  let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
                fputs("scroll-guard: could not create event tap (Accessibility?)\n", stderr)
                ready.signal()
                return
            }
            CGEvent.tapEnable(tap: port, enable: false)
            let runLoop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(runLoop, source, .commonModes)
            // A stroke whose end, or its momentum's, never came lets go once stale, and the tap goes off.
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.5, 0.5, 0, 0) { [unowned self] _ in
                if self.stroke.expire(at: CACurrentMediaTime()) {
                    print("\(stamp()) scroll-guard: a stroke went stale")
                    self.settle()
                }
            }
            CFRunLoopAddTimer(runLoop, timer, .commonModes)
            lock.withLock { (self.port, self.runLoop) = (port, runLoop) }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "kex scroll guard"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    /// On the tap's thread: the tap goes off once no gesture's fingers are down and no stroke it took is still going.
    private func settle() {
        guard let runLoop = lock.withLock({ self.runLoop }) else { return }
        guard CFRunLoopGetCurrent() === runLoop else {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [unowned self] in settle() }
            CFRunLoopWakeUp(runLoop)
            return
        }
        lock.withLock {
            guard let port else { return }
            if !settings.enabled {
                stroke.reset()
            } else if fingersDown || stroke.holding {
                return
            }
            guard on else { return }
            CGEvent.tapEnable(tap: port, enable: false)
            on = false
            // What comes of the stroke from here, the tap does not hear.
            stroke.reset()
        }
    }

    /// Whether `event` goes on to the app; rewritten as its stroke's end, it does.
    fileprivate func scrolled(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .scrollWheel else {
            // Off by a timeout or the user while meant to be on, it goes back on; turned off by `settle`, nothing.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                lock.withLock {
                    if on, let port { CGEvent.tapEnable(tap: port, enable: true) }
                }
            }
            return true
        }
        let (settings, down) = lock.withLock { (self.settings, fingersDown) }
        guard settings.enabled else { return true }
        // The strip's own stroke, which `MouseStripScroll` takes.
        let strip = settings.strip.map { exactlyHeld($0, sides: settings.sides, in: event.flags) } ?? false
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let was = stroke.holding
        let verdict = stroke.scroll(phase: phase, momentum: momentum, fingers: down && !strip, at: eventTime(event))
        if stroke.holding != was {
            print("\(stamp()) scroll-guard: \(stroke.holding ? "took a stroke" : "let a stroke go")")
        }
        defer { if !stroke.holding, !down { settle() } }
        switch verdict {
        case .pass:
            return true
        case .swallow:
            return false
        case .end:
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: ScrollGuard.ScrollPhase.ended)
            for field: CGEventField in [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                                        .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2] {
                event.setIntegerValueField(field, value: 0)
            }
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
            return true
        }
    }
}

private func gestureScrollCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                   refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let passes = Unmanaged<GestureScrollGuard>.fromOpaque(refcon).takeUnretainedValue().scrolled(type, event)
    return passes ? Unmanaged.passUnretained(event) : nil
}
