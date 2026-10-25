import AppKit
import DinkyPrivate

// `dinky debug events` prints the WindowServer event stream with the model's view of each window until
// killed; `dinky debug windows` prints the model's windows and exits. Both run without the app, as do the
// window and app actions below, which the fuzzer (scripts/fuzz.py) uses in place of Apple Events.
func runDebug(_ args: [String]) -> Int32 {
    // A gesture for the running app to feel as from a trackpad, for tests (see `TrackpadGestures.debug`).
    if args.first == "scroll-gesture" { return sendAndPrint((["debug"] + args).joined(separator: " ")) }
    if args.count >= 2, let n = Int32(args[1]), let result = debugAction(args[0], n, args.dropFirst(2).compactMap(Double.init)) {
        return result
    }
    guard args == ["events"] || args == ["windows"] else {
        fputs("usage: dinky debug events|windows|ax-close <id>|ax-minimize <id>|ax-unminimize <id>|ax-frame <id> <x> <y> <w> <h>|hide-app <pid>|unhide-app <pid>|scroll-gesture <mm> [<ms>] [<before-ms>] [<after-ms>]\n", stderr)
        return 64
    }
    let model = WindowModel()
    // SkyLight only delivers notifications while AppKit drains the connection's event port.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    guard model.start() else {
        fputs("debug: could not register for WindowServer notifications\n", stderr)
        return 1
    }

    if args == ["windows"] {
        for window in model.windows.values.sorted(by: { $0.id < $1.id }) { print(describe(window)) }
        return 0
    }

    let clock = DateFormatter()
    clock.dateFormat = "HH:mm:ss.SSS"
    print("watching \(model.windows.count) windows, ctrl-c to stop")
    model.observe { event in
        let t = clock.string(from: event.time)
        let kind = name(event.kind)
        var line = "\(t) \(kind.padding(toLength: 14, withPad: " ", startingAt: 0)) \(event.change)"
        if event.pid != 0 { line += " pid=\(event.pid)" }
        if event.spaceID != 0 { line += " space=\(event.spaceID)" }
        if let window = event.window { line += "  " + describe(window) }
        print(line)
        fflush(stdout)
    }
    app.run()
    return 0
}

/// Runs a window or app action; nil for an unknown action. 0 on success, 1 when the target is not there.
private func debugAction(_ action: String, _ n: Int32, _ values: [Double]) -> Int32? {
    func window() -> AXUIElement? {
        let info = dinky_window_info(UInt32(n))
        return info.exists ? axWindow(pid: info.pid, wid: UInt32(n), timeout: 1) : nil
    }
    func done(_ ok: Bool) -> Int32 {
        if !ok { fputs("debug: \(action) \(n) failed\n", stderr) }
        return ok ? 0 : 1
    }
    switch action {
    case "ax-close":
        var button: CFTypeRef?
        guard let element = window(),
              AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success else { return done(false) }
        return done(AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success)
    case "ax-minimize", "ax-unminimize":
        let value = action == "ax-minimize" ? kCFBooleanTrue! : kCFBooleanFalse!
        guard let element = window() else { return done(false) }
        return done(AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value) == .success)
    case "ax-frame":
        guard values.count == 4, let element = window() else { return done(false) }
        var origin = CGPoint(x: values[0], y: values[1]), size = CGSize(width: values[2], height: values[3])
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
        let sized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        return done(moved == .success && sized == .success)
    case "hide-app", "unhide-app":
        // NSRunningApplication.hide() answers false from an ssh session; the AX attribute works there.
        let value = action == "hide-app" ? kCFBooleanTrue! : kCFBooleanFalse!
        return done(AXUIElementSetAttributeValue(AXUIElementCreateApplication(n), kAXHiddenAttribute as CFString, value) == .success)
    default:
        return nil
    }
}

private func describe(_ w: Window) -> String {
    let f = "\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))x\(Int(w.frame.height))"
    var flags: [String] = []
    if w.isNormal { flags.append("normal") }
    if !w.isOrderedIn { flags.append("hidden") }
    if w.isMinimized { flags.append("minimized") }
    if !w.isVisible { flags.append("non-visible") }
    if !w.isDocument { flags.append("non-document") }
    return "wid=\(w.id) pid=\(w.pid) space=\(w.spaceID) level=\(w.level) radius=\(w.cornerRadius) \(f) [\(flags.joined(separator: ","))] \(w.appName ?? "?") \(w.bundleID ?? "")"
}

private func name(_ kind: DinkyEventKind) -> String {
    switch kind {
    case .windowUpdate: "update"
    case .windowClose: "close"
    case .windowMove: "move"
    case .windowResize: "resize"
    case .windowReorder: "reorder"
    case .windowLevel: "level"
    case .windowUnhide: "unhide"
    case .windowHide: "hide"
    case .windowTitle: "title"
    case .windowCreate: "create"
    case .windowDestroy: "destroy"
    case .spaceCreated: "space-created"
    case .spaceDestroyed: "space-destroyed"
    case .spaceChange: "space-change"
    case .frontApp: "front-app"
    @unknown default: "\(kind.rawValue)"
    }
}
