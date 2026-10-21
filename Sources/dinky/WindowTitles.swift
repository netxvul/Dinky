import AppKit
import DinkyLayout

// Window titles for the switchers' `show-titles`: what the window server names at once, which it does only with
// Screen Recording granted, and the rest asked of the apps off the main thread, each briefly, so a hung app holds
// nothing up. A window with no title is named by its app.
enum WindowTitles {
    /// The titles the window server gives for `ids`, at once.
    static func known(_ ids: [WindowID]) -> [WindowID: String] {
        guard !ids.isEmpty else { return [:] }
        let array = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) } as CFArray
        let info = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
        var names: [WindowID: String] = [:]
        for window in info {
            guard let id = window[kCGWindowNumber as String] as? WindowID,
                  let name = window[kCGWindowName as String] as? String, !name.isEmpty else { continue }
            names[id] = name
        }
        return names
    }

    /// Asks the apps for the titles of `asks`, each its window, owner and app name, calling `found` on the main thread
    /// with each as it comes.
    static func ask(_ asks: [(id: WindowID, pid: pid_t, app: String)], found: @escaping (WindowID, String) -> Void) {
        guard !asks.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            for ask in asks {
                var value: CFTypeRef?
                if let element = axWindow(pid: ask.pid, wid: ask.id, timeout: 0.1) {
                    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
                }
                let title = (value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ask.app
                DispatchQueue.main.async { found(ask.id, title) }
            }
        }
    }
}
