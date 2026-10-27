import AppKit
import DinkyLayout

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
    // Near an edge only, where a Dock can be: its bar is read through Accessibility, at most once a second.
    let onDockBar = displays.contains { $0.contains(point) && $0.insetBy(dx: 200, dy: 200).contains(point) == false }
        && dockBarFrame()?.contains(point) == true
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

/// The Dock's bar, as Accessibility has it (its list of items), in global top-left coordinates: nil with no Dock, or
/// none read. Read at most once a second. Main thread.
func dockBarFrame() -> CGRect? {
    let now = CACurrentMediaTime()
    if now - DockBar.readAt < 1 { return DockBar.frame }
    DockBar.readAt = now
    DockBar.frame = nil
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.05)
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success else { return nil }
    for child in children as? [AXUIElement] ?? [] {
        var role: AnyObject?, position: AnyObject?, size: AnyObject?
        guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXListRole,
              AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { continue }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        DockBar.frame = CGRect(origin: origin, size: extent)
        break
    }
    return DockBar.frame
}

/// The last read of the Dock's bar (`dockBarFrame`).
private enum DockBar {
    static var readAt = -CFTimeInterval.infinity
    static var frame: CGRect?
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
