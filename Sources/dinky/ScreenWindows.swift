import AppKit
import DinkyLayout
import DinkyPrivate
import os

/// A window's frame as the window server has it, or nil when it cannot be read, as for a window gone: a local read,
/// with no round trip to the server, for where only the frame is wanted, as on every frame of a glide.
func serverFrame(_ id: WindowID) -> CGRect? {
    var frame = CGRect.zero
    return dinky_window_bounds(id, &frame) ? frame : nil
}

/// The windows on screen, front to back, as the window server lists them, desktop elements left out.
func onScreenWindowInfo() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}

/// The frontmost window at `point` at any level, where a press there lands: a menu, a popover, a banner or the menu bar
/// over a window is it, not the window, and so is the Dock's bar (`dockBarFrame`). Looked through are dinky's own
/// windows, any not drawn, those at the screen saver's level or above, as the pointer's own, and any above the floating
/// level over a whole display, as the Dock keeps one whether its bar shows or not and as Notification Center and overlay
/// apps do, unless its app is the one in front. `info` is a read of `onScreenWindowInfo`. Main thread.
func frontmostWindow(at point: CGPoint, in info: [[String: Any]]) -> ScreenWindow? {
    let own = getpid(), front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let screenSaver = Int(CGWindowLevelForKey(.screenSaverWindow)), floating = Int(CGWindowLevelForKey(.floatingWindow))
    let displays = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
        .map(CGDisplayBounds)
    // Near the bottom, left or right edge only, where a Dock can be, never the top: its bar is the last read of it
    // (`dockBarFrame`), which never waits.
    let onDockBar = displays.contains {
        $0.contains(point) && (point.x < $0.minX + 200 || point.x > $0.maxX - 200 || point.y > $0.maxY - 200)
    } && dockBarFrame()?.contains(point) == true
    for w in info {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer < screenSaver,
              (w[kCGWindowAlpha as String] as? Double ?? 0) > 0, let owner = w[kCGWindowOwnerPID as String] as? pid_t,
              owner != own, let id = w[kCGWindowNumber as String] as? UInt32,
              let bounds = w[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point) else { continue }
        let window = ScreenWindow(id: id, pid: owner, layer: layer, frame: frame)
        if layer > floating, displays.contains(frame), owner != front {
            // The Dock's window over the display is in front where its bar is.
            if onDockBar, w[kCGWindowOwnerName as String] as? String == "Dock" { return window }
            continue
        }
        return window
    }
    return nil
}

/// The Dock's bar, as Accessibility has it (its list of items), in global top-left coordinates, from the last read:
/// nil with no Dock, none read or a read failed. Never waits on the Dock: once that read's keep has passed and none is
/// under way, it starts one on its own queue and gives the last meanwhile. A read is kept from when it ends by what it
/// found: a bar shown (`dockBarShown`) for 0.3 s; one hidden or sliding only till the next look, 0.1 s; a failure for
/// a second. Any thread.
func dockBarFrame() -> CGRect? {
    let now = CACurrentMediaTime()
    let (frame, start) = DockBar.state.withLock { state in
        let start = now >= state.keptTill && !state.reading
        if start { state.reading = true }
        return (state.frame, start)
    }
    if start { DockBar.queue.async(execute: readDockBar) }
    return frame
}

/// Reads the Dock's bar into `DockBar.state`, on `DockBar.queue`. Each element is asked with a 50 ms timeout, no call
/// is made past 50 ms from the start, and a read that took longer counts as failed.
private func readDockBar() {
    let start = CACurrentMediaTime()
    let read = readDockList(by: start + 0.05)
    let end = CACurrentMediaTime()
    let frame = end > start + 0.05 ? nil : read
    var count: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    let displays = CGGetActiveDisplayList(16, &ids, &count) == .success ? ids.prefix(Int(count)).map(CGDisplayBounds) : []
    let keep: CFTimeInterval = frame.map { dockBarShown($0, on: displays) ? 0.3 : 0.1 } ?? 1
    DockBar.state.withLock { $0 = DockBar.State(frame: frame, keptTill: end + keep, reading: false) }
}

/// The Dock's list of items, read before `deadline`, or nil.
private func readDockList(by deadline: CFTimeInterval) -> CGRect? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.05)
    func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        guard CACurrentMediaTime() < deadline else { return nil }
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    for child in value(app, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        AXUIElementSetMessagingTimeout(child, 0.05)
        guard value(child, kAXRoleAttribute) as? String == kAXListRole,
              let position = value(child, kAXPositionAttribute), let size = value(child, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else {
            if CACurrentMediaTime() >= deadline { return nil }
            continue
        }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
    return nil
}

/// The last read of the Dock's bar (`dockBarFrame`), till when it holds, and whether a read is under way.
private enum DockBar {
    struct State {
        var frame: CGRect?
        var keptTill = -CFTimeInterval.infinity
        var reading = false
    }
    static let state = OSAllocatedUnfairLock(initialState: State())
    static let queue = DispatchQueue(label: "dinky.dock-bar", qos: .utility)
}

/// Logs, once per app and level a run, a window in front of a placed strip window that keeps a press or the mouse's hand
/// off it: one that lets clicks through still counts as in front. `info` is the read it was found in.
func noteInFront(_ window: ScreenWindow, over strip: WindowID, in info: [[String: Any]]) {
    let owner = info.first { $0[kCGWindowNumber as String] as? UInt32 == window.id }?[kCGWindowOwnerName as String] as? String ?? "?"
    guard InFront.logged.insert("\(owner) \(window.layer)").inserted else { return }
    print("\(stamp()) mouse-scroll: \(owner)'s window \(window.id) at level \(window.layer), \(window.frame), is in front of strip window \(strip): no press or hand there")
}

private enum InFront {
    static var logged: Set<String> = []
}
