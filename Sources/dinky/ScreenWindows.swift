import AppKit
import DinkyLayout

/// The windows on screen, front to back, as the window server lists them, desktop elements left out.
func onScreenWindowInfo() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}

/// The frontmost window at `point` at any level, where a press there lands: a menu, a popover, a banner or the menu bar
/// over a window is it, not the window. Looked through are dinky's own windows, any not drawn, the pointer's own window,
/// and the Dock's window over a whole display, which it keeps whether the Dock shows or not; a press on the Dock itself
/// lands in that window too, so it cannot be told from one under it. `info` is a read of `onScreenWindowInfo`.
func frontmostWindow(at point: CGPoint, in info: [[String: Any]]) -> ScreenWindow? {
    let own = getpid(), pointer = Int(CGWindowLevelForKey(.cursorWindow))
    let displays = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
        .map(CGDisplayBounds)
    for w in info {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer < pointer,
              (w[kCGWindowAlpha as String] as? Double ?? 0) > 0, let owner = w[kCGWindowOwnerPID as String] as? pid_t,
              owner != own, let id = w[kCGWindowNumber as String] as? UInt32,
              let bounds = w[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point) else { continue }
        if w[kCGWindowOwnerName as String] as? String == "Dock", displays.contains(frame) { continue }
        return ScreenWindow(id: id, pid: owner, layer: layer, frame: frame)
    }
    return nil
}
