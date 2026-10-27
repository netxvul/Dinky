import AppKit
import DinkyLayout
import DinkyPrivate

// The hand the pointer shows for `[gestures.mouse-scroll]`'s drag (`cursor`). AppKit sets the cursor only for the active
// app, which dinky never is, and the app under the pointer sets its own on every move: so a transparent panel, which
// activates nothing, lies over the window a press would drag, just above it, so floating windows, sheets and menus
// stay above it, and over the whole display while a press drags the strip, the windows sliding under the pointer.
// Its cursor rect and the connection's private background setting (`dinky_cursor_in_background`) give the window
// server the hand; a hand another app set over it since is set again (`keep`).
//
// The panel takes the clicks and scrolls over it, so whatever is not the strip's must find it gone: `clear` orders it
// out through the window server at once, before the event it is cleared for is let through. Main thread only.
final class GrabCursor {
    /// In `eventSourceUserData` of the move posted as the hand goes, so dinky's own taps pass it over.
    static let moveTag: Int64 = 0x64696e6b
    /// How long after the panel shows the hand is set again, the cursor rects being in place by then.
    private static let settleSet: TimeInterval = 0.05
    /// How long the app under the pointer has, once the panel is out, to set its own cursor before the arrow does.
    private static let giveBack: TimeInterval = 0.08

    private var panel: NSPanel?
    private var view: HandView?
    private(set) var shape: GrabShape?
    /// The window the open hand shows over, and its frame then.
    private var over: (id: WindowID, frame: CGRect)?
    /// The cursor seed as dinky last set the hand: another since, and an app set its own.
    private var ourSeed: Int32 = -1
    /// Bumped by every show and clear, so a set or a give-back from before does nothing.
    private var generation = 0
    private var tagged = false
    private var inBackground = false

    var isShowing: Bool { shape != nil }

    /// The open hand over `window`, at its level, just above it.
    func showOpen(over window: ScreenWindow) {
        guard shape != .open || over?.id != window.id || over?.frame != window.frame else { return }
        over = (window.id, window.frame)
        place(window.frame, level: window.layer, above: window.id)
        set(.open)
    }

    /// The closed hand over the whole `display`, in front of the normal level.
    func showClosed(on display: CGRect) {
        guard shape != .closed else { return }
        over = nil
        place(display, level: Int(CGWindowLevelForKey(.normalWindow)), above: nil)
        set(.closed)
    }

    /// The hand set again where another app set its own over it: called every frame while it shows.
    func keep() {
        guard shape != nil else { return }
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
        generation += 1
        if let panel {
            _ = dinky_window_order_out(UInt32(panel.windowNumber))
            panel.orderOut(nil)
        }
        // Not mid-press: a move between an app's press and its drag would be news to it.
        if !CGEventSource.buttonState(.hidSystemState, button: .left), let here = CGEvent(source: nil)?.location,
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
        // Above means just in front of `window`; with none, in front of every window at its level.
        panel.order(.above, relativeTo: window.map(Int.init) ?? 0)
        if !tagged, panel.windowNumber > 0 { tagged = dinky_window_cursor_tag(UInt32(panel.windowNumber)) }
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
        panel.contentView = view
        (self.panel, self.view) = (panel, view)
        return panel
    }
}

/// The panel's view: its cursor rect, and a tracking area on whatever app is active, setting the hand again as the
/// pointer moves over it.
private final class HandView: NSView {
    var cursor = NSCursor.openHand {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onMove: () -> Void = {}

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
}
