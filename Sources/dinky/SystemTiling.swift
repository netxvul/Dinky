import AppKit
import DinkyLayout

@_silgen_name("_AXUIElementGetWindow")
private func tilingWindowID(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// macOS's own window tiling: Window > Fill and Window > Move & Resize > Return to Previous Size, which every AppKit app
// (Electron and GPUI ones too) has in its Window menu and animates itself. The app sets its window's whole frame on every
// step, so the window never shows the half-done frame that an Accessibility size and move one after the other do (see
// ResizeOnce): a window on the right grows to the left as if dragged by its left edge. dinky presses the menu item, found
// by its identifier, which does not change with the system language, without opening the menu. Only the front app's key
// window takes it.
enum SystemTiling {
    /// The Window-menu items, by their accessibility identifiers.
    static let fill = "_zoomFill:", untile = "_zoomUntile:"

    /// How long the columns a window going fullscreen through the system pushes take, in seconds of a spring's
    /// response or an easing's time, however long a glide is (never quicker than one): well longer than the system's
    /// animation, about a third of a second after a tenth or more, so they follow it, held at its edge, rather than run
    /// ahead or arrive first. Six times the 150 ms glides once were.
    static let followTime = 0.9

    /// The margin macOS keeps round a tiled window when "Tiled windows have margins" is on.
    static let margin: CGFloat = 8

    private static let settings = UserDefaults(suiteName: "com.apple.WindowManager")

    /// Where Fill puts a window on `display`: its visible area, inside the margins when macOS keeps them, as it does
    /// unless they were turned off.
    static func fillFrame(on display: Display) -> CGRect {
        let margins = settings?.object(forKey: "EnableTiledWindowMargins") as? Bool ?? true
        return margins ? display.visibleArea.insetBy(dx: margin, dy: margin) : display.visibleArea
    }
}

/// Presses an app's tiling menu items for one of its windows, off the main thread. The items are looked up once per app
/// and kept.
final class SystemTiler {
    private let queue = DispatchQueue(label: "dinky.system-tiling")
    /// Menu items found, by app and identifier. Queue only.
    private var items: [pid_t: [String: AXUIElement]] = [:]

    /// Presses `identifier` in the Window menu of `pid` for its window `id`, when its app is active, that is its focused
    /// window, just before the press, and the item is enabled. `done` gets whether it was pressed, on the main queue.
    func press(_ identifier: String, pid: pid_t, window id: WindowID, done: @escaping (Bool) -> Void) {
        queue.async { [self] in
            let pressed = pressNow(identifier, pid: pid, window: id)
            DispatchQueue.main.async { done(pressed) }
        }
    }

    private func pressNow(_ identifier: String, pid: pid_t, window id: WindowID) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        // A kept item can be stale once its app has rebuilt its menu: looked up again then.
        for fresh in [false, true] {
            if fresh { items[pid]?[identifier] = nil }
            guard let item = items[pid]?[identifier] ?? find(identifier, in: app) else { return false }
            items[pid, default: [:]][identifier] = item
            var enabled: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled)
            if error == .cannotComplete { return false }
            guard error == .success else { continue }
            guard (enabled as? Bool) == true, isKey(id, of: app, pid: pid) else { return false }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
        return false
    }

    /// Whether `id` is the focused window of the app, and the app the active one: the window the menu item acts on.
    private func isKey(_ id: WindowID, of app: AXUIElement, pid: pid_t) -> Bool {
        guard NSRunningApplication(processIdentifier: pid)?.isActive == true,
              let focused = Self.element(app, kAXFocusedWindowAttribute) else { return false }
        var wid: CGWindowID = 0
        return tilingWindowID(focused, &wid) == .success && wid == id
    }

    /// How long one Accessibility call to the app may take: a hung app only holds up its own press.
    private static let timeout: Float = 0.5

    /// The menu item with `identifier` in the app's menu bar, a few levels down at most (Window > Move & Resize > …).
    /// The menus are searched from the last, where the Window menu is, towards the first.
    private func find(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        guard let bar = Self.element(app, kAXMenuBarAttribute) else { return nil }
        func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            AXUIElementSetMessagingTimeout(element, Self.timeout)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
                  let children = value as? [AXUIElement] else { return nil }
            for child in depth == 0 ? children.reversed() : children {
                AXUIElementSetMessagingTimeout(child, Self.timeout)
                var name: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, "AXIdentifier" as CFString, &name) == .success,
                   name as? String == identifier { return child }
                if depth < 4, let found = search(child, depth: depth + 1) { return found }
            }
            return nil
        }
        return search(bar, depth: 0)
    }

    private static func element(_ of: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(of, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
