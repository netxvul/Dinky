import AppKit
import DinkyLayout
import os

// A click on a scrolling strip's window that only peeks in at a screen edge brings that window into view and then
// focuses it; the click itself goes to dinky, not to the app. An app activated while its window sits mostly off
// screen, and then has that window scrolled in under it as it takes the click, can stall for seconds (Zed, measured:
// its frame commit waits on WindowServer). Scrolled in first and activated once it rests, it takes no click while it
// moves. The tap runs on a thread of its own and hears only presses and releases, so a busy main thread holds up no
// click, and only a press on a peek costs more than a look-up.
final class PeekClicks {
    static let shared = PeekClicks()

    /// A window's sliver on screen, in global top-left coordinates.
    struct Peek: Sendable {
        let id: WindowID
        let rect: CGRect
    }

    /// The most of a window on screen that still counts as a peek: the strip's peek, with room for a gap.
    static let widest: CGFloat = Workspace.peek + 16

    /// Called on the main thread with the window whose peek was clicked.
    var onClick: ((WindowID) -> Void)?

    /// Peeks by Space, written on the main thread, read by the tap.
    private let peeks = OSAllocatedUnfairLock(initialState: [UInt64: [Peek]]())
    /// Whether the release of a press the tap kept is still to come. Tap thread only.
    private var swallowUp = false
    private var tap: CFMachPort?
    private var started = false

    /// The peeks of a strip as it was last laid out, replacing what the Space had; none when it has no strip.
    func update(_ new: [Peek], space: UInt64) {
        peeks.withLock { $0[space] = new.isEmpty ? nil : new }
    }

    /// Forgets every peek, as when tiling stops.
    func clear() {
        peeks.withLock { $0 = [:] }
    }

    /// Starts the tap on its own thread, the first time. Main thread.
    func start() {
        guard !started else { return }
        started = true
        let thread = Thread { [self] in
            let types: [CGEventType] = [.leftMouseDown, .leftMouseUp]
            let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: peekClickCallback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                fputs("peek clicks: could not create event tap (Accessibility?)\n", stderr)
                return
            }
            self.tap = tap
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "dinky.peek-clicks"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Whether to let the event through. Tap thread.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown:
            swallowUp = false
            // A press with a modifier is someone else's: a modifier drag, a Cmd-click.
            let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty else { break }
            let point = event.location
            let hit = peeks.withLock { $0.values.lazy.flatMap { $0 }.first { $0.rect.contains(point) } }
            // Only where the peeking window is the one on top: a floating window can cover the edge.
            guard let hit, Self.frontWindow(at: point) == hit.id else { break }
            swallowUp = true
            DispatchQueue.main.async { [self] in onClick?(hit.id) }
            return false
        case .leftMouseUp where swallowUp:
            swallowUp = false
            return false
        default:
            break
        }
        return true
    }

    /// The frontmost window at `point` at the normal or floating levels, dinky's own windows looked through.
    private static func frontWindow(at point: CGPoint) -> WindowID? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let levels = 0...Int(CGWindowLevelForKey(.floatingWindow)), own = getpid()
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, levels.contains(layer),
                  (window[kCGWindowOwnerPID as String] as? pid_t) != own,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point) else { continue }
            return window[kCGWindowNumber as String] as? WindowID
        }
        return nil
    }
}

private func peekClickCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let clicks = Unmanaged<PeekClicks>.fromOpaque(refcon).takeUnretainedValue()
    return clicks.handle(type, event) ? Unmanaged.passUnretained(event) : nil
}
