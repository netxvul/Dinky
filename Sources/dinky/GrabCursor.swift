import AppKit
import DinkyLayout
import DinkyPrivate
import os

// The hand the pointer shows for `[gestures.mouse-scroll]`'s drag (`cursor`). AppKit sets the cursor only for the active
// app, which dinky never is, and the app under the pointer sets its own on every move: so a transparent panel, which
// activates nothing, lies over the window a press would drag, just above it, so floating windows, sheets and menus
// stay above it, and over the whole display while a press drags the strip, the windows sliding under the pointer.
// Its cursor rect and the connection's private background setting (`dinky_cursor_in_background`) give the window
// server the hand; a hand another app set over it since is set again (`keep`).
//
// The panel takes the clicks and scrolls over it, so whatever is not the strip's must find it gone: `clear` orders it
// out through the window server at once, before the event it is cleared for is let through, and `GrabGuard`, behind
// dinky's own taps on a thread of its own, orders it out for anything they let through. Main thread only.
final class GrabCursor {
    /// In `eventSourceUserData` of the move posted as the hand goes, so dinky's own taps pass it over.
    static let moveTag: Int64 = 0x64696e6b
    /// How long after the panel shows the hand is set again, the cursor rects being in place by then.
    private static let settleSet: TimeInterval = 0.05
    /// How long the app under the pointer has, once the panel is out, to set its own cursor before the arrow does.
    private static let giveBack: TimeInterval = 0.08
    /// Whether the private calls the hand needs are there.
    static let available = dinky_cursor_available()

    /// The panel's window number while it shows, for `GrabGuard` to order out from its thread.
    private static let shown = OSAllocatedUnfairLock<UInt32>(initialState: 0)
    /// The panel's window number, shown or not.
    private static var panelNumber: UInt32 = 0

    /// Whether `id` is the hand's panel, which hover focus looks through.
    static func isPanel(_ id: UInt32) -> Bool { id != 0 && id == panelNumber }

    /// Whether the panel is shown, as `GrabGuard` would find it: not once it has taken it. Any thread.
    static var isShown: Bool { shown.withLock { $0 != 0 } }

    /// The panel shown, taken so it is ordered out once only: nil with none. Any thread.
    static func takeShown() -> UInt32? {
        shown.withLock { number in
            defer { number = 0 }
            return number == 0 ? nil : number
        }
    }

    /// Called as the pointer leaves the panel, so the hand is looked at again at once.
    var onExit: () -> Void = {}

    private var panel: NSPanel?
    private var view: HandView?
    private(set) var shape: GrabShape?
    /// The window the open hand shows over, and its frame then.
    private var over: (id: WindowID, frame: CGRect)?
    /// Where the hand shows, in global top-left coordinates: the window's frame, or the display's.
    private var shownFrame = CGRect.null
    /// The cursor seed as dinky last set the hand: another since, and an app set its own.
    private var ourSeed: Int32 = -1
    /// Bumped by every show and clear, so a set or a give-back from before does nothing.
    private var generation = 0
    private var tagged = false
    private var inBackground = false

    var isShowing: Bool { shape != nil }

    /// The open hand over `window`, at its level, just above it: ordered there again on every look, as dinky, a pin or
    /// the app may have raised the window over it since.
    func showOpen(over window: ScreenWindow) {
        if shape == .open, over?.id == window.id, over?.frame == window.frame, let panel {
            // The guard ordered it out for an event let through meanwhile: it goes, rather than coming back over it.
            guard Self.isShown else { return clear() }
            panel.order(.above, relativeTo: Int(window.id))
            return
        }
        over = (window.id, window.frame)
        place(window.frame, level: window.layer, above: window.id)
        set(.open)
    }

    /// The closed hand over the whole `display`, a level above the normal one, so no window raised while the strip is
    /// held, a pin ordered in front among them, comes over it; floating windows stay above.
    func showClosed(on display: CGRect) {
        guard shape != .closed else { return }
        over = nil
        place(display, level: Int(CGWindowLevelForKey(.normalWindow)) + 1, above: nil)
        set(.closed)
    }

    /// The hand set again where another app set its own over it, while the pointer is over the panel: called every frame
    /// while it shows. Not once it has left, where the app under it rightly sets its own.
    func keep() {
        guard shape != nil, let here = CGEvent(source: nil)?.location, shownFrame.contains(here) else { return }
        let seed = dinky_cursor_seed()
        guard seed != -1, seed != ourSeed else { return }
        setNow()
    }

    /// The hand goes: the panel out at once, so what comes next reaches the app under it; then a move where the
    /// pointer is, so that app sets its own cursor, and the arrow only where none did (`GrabCursorRule.givesBack`).
    /// `atOnce`, as dinky stops, sets the arrow now rather than waiting on the app, and lets the setting go.
    func clear(atOnce: Bool = false) {
        guard shape != nil else { return }
        shape = nil
        over = nil
        shownFrame = .null
        generation += 1
        _ = Self.takeShown()
        if let panel {
            _ = dinky_window_order_out(UInt32(panel.windowNumber))
            panel.orderOut(nil)
        }
        // Not while a button is down: a move between an app's press and its drag or release would be news to it.
        let down = [CGMouseButton.left, .right, .center].contains { CGEventSource.buttonState(.hidSystemState, button: $0) }
        if !down, let here = CGEvent(source: nil)?.location,
           let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: here, mouseButton: .left) {
            move.setIntegerValueField(.eventSourceUserData, value: Self.moveTag)
            move.post(tap: .cghidEventTap)
        }
        let generation = self.generation, ours = ourSeed
        let giveBack = { [weak self] in
            guard let self, self.generation == generation else { return }
            if GrabCursorRule.givesBack(seed: dinky_cursor_seed(), ours: ours) { NSCursor.arrow.set() }
            _ = dinky_cursor_in_background(false)
            inBackground = false
        }
        if atOnce { giveBack() } else { DispatchQueue.main.asyncAfter(deadline: .now() + Self.giveBack, execute: giveBack) }
    }

    private func place(_ frame: CGRect, level: Int, above window: WindowID?) {
        let panel = panel ?? makePanel()
        let primary = NSScreen.screens.first?.frame.maxY ?? 0
        panel.setFrame(NSRect(x: frame.minX, y: primary - frame.maxY, width: frame.width, height: frame.height), display: false)
        panel.level = NSWindow.Level(rawValue: level)
        // Published before it is ordered in, so the guard can order out a panel that shows by the time an event comes.
        let number = UInt32(panel.windowNumber)
        Self.panelNumber = number
        Self.shown.withLock { $0 = number }
        // Above means just in front of `window`; with none, in front of every window at its level.
        panel.order(.above, relativeTo: window.map(Int.init) ?? 0)
        shownFrame = frame
        if !tagged, number > 0 { tagged = dinky_window_cursor_tag(number) }
        if let view { panel.invalidateCursorRects(for: view) }
    }

    private func set(_ shape: GrabShape) {
        self.shape = shape
        generation += 1
        view?.cursor = shape == .open ? .openHand : .closedHand
        if !inBackground { inBackground = dinky_cursor_in_background(true) }
        setNow()
        let generation = self.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSet) { [weak self] in
            guard let self, self.generation == generation else { return }
            setNow()
        }
    }

    private func setNow() {
        guard let shape else { return }
        (shape == .open ? NSCursor.openHand : NSCursor.closedHand).set()
        ourSeed = dinky_cursor_seed()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        // All but clear: a window the window server sees nothing of passes the mouse through.
        panel.backgroundColor = NSColor.white.withAlphaComponent(0.01)
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = HandView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        view.onMove = { [weak self] in self?.keep() }
        view.onExit = { [weak self] in self?.onExit() }
        panel.contentView = view
        (self.panel, self.view) = (panel, view)
        return panel
    }
}

/// The panel's view: its cursor rect, and a tracking area on whatever app is active, setting the hand again as the
/// pointer moves over it, and telling as it leaves.
private final class HandView: NSView {
    var cursor = NSCursor.openHand {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onMove: () -> Void = {}
    var onExit: () -> Void = {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { onMove() }
    override func mouseEntered(with event: NSEvent) { onMove() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// Orders the hand's panel out for whatever reaches the window under it: a tap of its own, on a thread of its own, so a
/// busy main thread holds up nothing, and behind every other tap of the mouse's (`MouseStripScroll` makes it first). What
/// gets here those let through, or went past them as one timed out: presses of any button, scrolls, the tablet's
/// events and the trackpad's gestures. The main thread hears of each it ordered the panel out for.
final class GrabGuard {
    /// Real gestures among the events of type 29, which also carries the touches of every two-finger scroll.
    private static let gestures: Set<NSEvent.EventType> = [.magnify, .swipe, .rotate, .beginGesture, .endGesture,
                                                           .smartMagnify, .quickLook]
    /// CG event types: tablet pointer and proximity, and the trackpad's gesture, magnify, swipe, rotate, smart magnify,
    /// quick look and begin gesture.
    private static let raw: [UInt32] = [23, 24, 29, 30, 31, 18, 32, 33, 19]

    /// On the main thread, for each event the panel was ordered out for: its type.
    var onOrderedOut: (CGEventType) -> Void = { _ in }

    private let tapRunning = OSAllocatedUnfairLock(initialState: false)
    /// Whether the tap is meant to be on, as `enable` last had it, so one turned off is not turned on again by its own
    /// news of it.
    private let wanted = OSAllocatedUnfairLock(initialState: false)
    /// When it last saw a scroll, the panel shown or not: no open hand while scrolls go on (`GrabCursorRule.scrolling`).
    private let scrolledAt = OSAllocatedUnfairLock(initialState: -CFTimeInterval.infinity)
    private var tap: CFMachPort?

    /// Whether its tap is in place: no hand shows without it.
    var isRunning: Bool { tapRunning.withLock { $0 } }

    /// When it last saw a scroll.
    var lastScroll: CFTimeInterval { scrolledAt.withLock { $0 } }

    /// Turns its tap on or off: on only while the modifier is held with the hand on, or the hand shows. Main thread.
    func enable(_ on: Bool) {
        guard let tap, wanted.withLock({ was in defer { was = on }; return was != on }) else { return }
        CGEvent.tapEnable(tap: tap, enable: on)
    }

    /// Makes the tap here, so it goes in behind those made after it, and runs it on a thread of its own. Once. Main
    /// thread.
    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue } | Self.raw.reduce(CGEventMask(0)) { $0 | 1 << $1 }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: grabGuardCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fputs("mouse-scroll: could not create the hand's guard tap (Accessibility?)\n", stderr)
            return
        }
        self.tap = tap
        tapRunning.withLock { $0 = true }
        // Off till `enable`: it hears every press and scroll while on.
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "dinky.grab-guard"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Tap thread.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, wanted.withLock({ $0 }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if type == .scrollWheel { scrolledAt.withLock { $0 = CACurrentMediaTime() } }
        // Nothing shown: nothing to do, and no event read further.
        guard GrabCursor.isShown else { return }
        autoreleasepool {
            if type.rawValue == 29, !(NSEvent(cgEvent: event).map { Self.gestures.contains($0.type) } ?? false) { return }
            guard let number = GrabCursor.takeShown() else { return }
            _ = dinky_window_order_out(number)
            DispatchQueue.main.async { [self] in onOrderedOut(type) }
        }
    }
}

private func grabGuardCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<GrabGuard>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) }
    return Unmanaged.passUnretained(event)
}
