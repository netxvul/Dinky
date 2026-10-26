import AppKit
import DinkyCommands
import DinkyConfig
import DinkyPrivate

// `dinky doctor [--config <path>]`: checks the config and the environment without needing the app. Exit 1 on errors.
func runDoctor(_ args: [String]) -> Int32 {
    var errors = 0, warnings = 0
    func ok(_ text: String) { print("  ok: \(text)") }
    func warn(_ text: String) { warnings += 1; print("  warning: \(text)") }
    func fail(_ text: String) { errors += 1; print("  error: \(text)") }

    let os = ProcessInfo.processInfo.operatingSystemVersion
    print("dinky doctor")
    print("  macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), dinky was built against 27.0")

    var url = Config.userConfigURL
    if let i = args.firstIndex(of: "--config"), i + 1 < args.count { url = URL(fileURLWithPath: args[i + 1]) }
    print("  config: \(url.path)")
    print("  log: \(logURL.path)")
    var config = Config.default
    if !FileManager.default.fileExists(atPath: url.path) {
        warn("no config file yet; the app writes the default one on first run")
    } else {
        do {
            config = try Config.load(from: url)
            ok("parses: \(config.workspaces) workspaces, \(config.modes.count) modes, \(config.rules.count) window rules")
        } catch {
            fail("\(error)")
        }
    }
    for finding in checkConfig(config) {
        finding.level == .error ? fail(finding.message) : warn(finding.message)
    }

    // Dock settings the design depends on. Both default to on when unset.
    if dockSetting("mru-spaces") ?? true {
        warn("\"Automatically rearrange Spaces based on most recent use\" is on; workspace numbers will move around. Turn it off in System Settings > Desktop & Dock")
    } else {
        ok("Spaces are not auto-rearranged")
    }
    if config.followAppActivation {
        if dockSetting("workspaces-auto-swoosh") ?? true {
            warn("\"When switching to an application, switch to a Space with open windows\" is on; Cmd-Tab will use macOS's slow switch instead of dinky's. The app's onboarding can turn it off")
        } else {
            ok("Cmd-Tab switching goes through dinky")
        }
    }

    if !config.gestures.trackpadSwipes.isEmpty {
        let fingers = config.gestures.trackpad.fingers
        let clashes = gestureClashes(fingers: fingers, swipes: Set(config.gestures.trackpadSwipes.keys))
        clashes.isEmpty ? ok("\(fingers)-finger swipes clash with nothing macOS does")
                        : warn("\(fingers)-finger swipes also \(clashes.joined(separator: " and ")) in macOS; "
                               + "change it in System Settings > Trackpad > More Gestures, or [gestures.trackpad] fingers")
    }
    let mouse = config.gestures.mouse
    if !config.gestures.mouseSwipes.isEmpty {
        let clashes = mouseGestureClashes(fingers: mouse.fingers, swipes: Set(config.gestures.mouseSwipes.keys))
        clashes.isEmpty ? ok("\(mouse.fingers)-finger swipes on a Magic Mouse clash with nothing macOS does")
                        : warn("\(mouse.fingers)-finger swipes on a Magic Mouse also \(clashes.joined(separator: " and ")) in macOS; "
                               + "change it in System Settings > Mouse, or [gestures.mouse]")
    }
    if config.gestures.scroll.enabled {
        let fingers = config.gestures.scroll.fingers
        let clashes = scrollGestureClashes(fingers: fingers)
        clashes.isEmpty ? ok("\(fingers)-finger strip scrolls clash with nothing macOS does")
                        : warn("\(fingers)-finger strip scrolls also \(clashes.joined(separator: " and ")) in macOS; "
                               + "turn that off in System Settings > Trackpad > More Gestures, or change [gestures.scroll] fingers")
    }

    // macOS's own tiling by dragging a window to a screen edge, or the top, fights a drag dinky drops.
    let edgeTiling = ["EnableTilingByEdgeDrag": "to a screen edge", "EnableTopTilingByEdgeDrag": "to the top of the screen"]
        .filter { key, _ in windowManagerSetting(key) ?? true }
    if edgeTiling.isEmpty {
        ok("macOS does not tile windows dragged to the screen's edges")
    } else {
        warn("macOS tiles a window dragged \(edgeTiling.values.sorted().joined(separator: " or ")), over dinky's drop; "
             + "turn off \"Drag windows to screen edges to tile\" and \"Drag windows to menu bar to fill screen\" in System Settings > Desktop & Dock")
    }

    // Where the workspaces go with the displays connected now; the app arranges the Spaces to match.
    let connected = dinky_displays()
    let displays = connected.map { d in
        PlanDisplay(uuid: d.uuid, monitor: Monitor(name: screen(of: d.displayID)?.localizedName ?? "",
                                                   isMain: CGDisplayIsMain(d.displayID) != 0, count: connected.count),
                    spaces: d.spaces.filter(\.isUser).map(\.spaceID), current: d.currentSpaceID)
    }
    let homes = WorkspacePlan(config).homes(displays)
    for (i, display) in displays.enumerated() {
        let label = display.monitor.name.isEmpty ? "display \(i + 1)" : "display \(i + 1) (\(display.monitor.name))"
        let here = homes.filter { $0.value == display.uuid }.keys.sorted()
        let spaces = "\(display.spaces.count) Space\(display.spaces.count == 1 ? "" : "s")"
        ok(here.isEmpty ? "\(label) has \(spaces) and no workspaces"
                        : "\(label) has \(spaces) for workspace\(here.count == 1 ? "" : "s") \(here.map(String.init).joined(separator: ", "))")
    }

    let tilers = runningOtherTilers()
    tilers.isEmpty ? ok("no other tiling window manager is running") : warn(otherTilersWarning(tilers))

    ok(AXIsProcessTrusted() ? "this terminal has Accessibility (the app needs its own grant)" : "this terminal has no Accessibility grant; only the app needs one")
    if let reply = sendToApp("list-monitors --focused --format '%{monitor-name}'"), reply.ok {
        ok("app is running, focused display: \(reply.text)")
    } else {
        warn("app is not running (\(socketPath))")
    }

    print("\(errors) errors, \(warnings) warnings")
    return errors == 0 ? 0 : 1
}

/// A boolean setting of macOS's window tiling (com.apple.WindowManager), nil when unset, which is on.
func windowManagerSetting(_ key: String) -> Bool? {
    CFPreferencesCopyAppValue(key as CFString, "com.apple.WindowManager" as CFString) as? Bool
}

/// A boolean Dock setting, nil when unset.
func dockSetting(_ key: String) -> Bool? {
    CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? Bool
}

/// What macOS does with the `swipes` dinky has bound for `fingers` fingers on a Magic Mouse, from its mouse settings:
/// one finger scrolls and swipes between pages, two scroll up and down and swipe across between full-screen apps.
func mouseGestureClashes(fingers: Int, swipes: Set<GestureSwipe>) -> [String] {
    guard fingers == 2 else { return [] }
    let swipe = CFPreferencesCopyAppValue("MouseTwoFingerHorizSwipeGesture" as CFString,
                                          "com.apple.AppleMultitouchMouse" as CFString) as? Int
    var clashes: [String] = []
    if swipes.contains(.swipeLeft) || swipes.contains(.swipeRight), (swipe ?? 2) != 0 {
        clashes.append("swipe between full-screen apps")
    }
    if swipes.contains(.swipeUp) || swipes.contains(.swipeDown) { clashes.append("scroll") }
    return clashes
}

/// What macOS does with the `swipes` dinky has bound for `fingers` fingers, from its trackpad settings.
func gestureClashes(fingers: Int, swipes: Set<GestureSwipe>) -> [String] {
    func setting(_ key: String) -> Int? {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.AppleMultitouchTrackpad" as CFString) as? Int
    }
    let across = swipes.contains(.swipeLeft) || swipes.contains(.swipeRight)
    let upDown = swipes.contains(.swipeUp) || swipes.contains(.swipeDown)
    var clashes: [String] = []
    switch fingers {
    case 2:
        clashes.append("scroll")
    case 3, 4:
        let count = fingers == 3 ? "Three" : "Four"
        if across, (setting("Trackpad\(count)FingerHorizSwipeGesture") ?? 2) != 0 { clashes.append("switch Spaces") }
        if upDown, (setting("Trackpad\(count)FingerVertSwipeGesture") ?? 2) != 0 { clashes.append("open Mission Control") }
        if fingers == 3, (setting("TrackpadThreeFingerDrag") ?? 0) != 0 { clashes.append("drag") }
    default:
        break
    }
    return clashes
}

/// What macOS does as `fingers` fingers move across the trackpad, which scrolling a strip with them would set off too,
/// from the built-in trackpad's settings and, once one has been set up, a Magic Trackpad's (see
/// `ScrollGesture.clashes`). Unset, macOS swipes three and four fingers across between full-screen apps.
func scrollGestureClashes(fingers: Int) -> [String] {
    var clashes: [String] = []
    for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
        func setting(_ key: String) -> Int? {
            CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int
        }
        let three = setting("TrackpadThreeFingerHorizSwipeGesture"), four = setting("TrackpadFourFingerHorizSwipeGesture")
        if domain != "com.apple.AppleMultitouchTrackpad", three == nil, four == nil { continue }
        let found = ScrollGesture.clashes(fingers: fingers, three: three ?? 2, four: four ?? 2,
                                          drag: (setting("TrackpadThreeFingerDrag") ?? 0) != 0)
        for clash in found where !clashes.contains(clash) { clashes.append(clash) }
    }
    return clashes
}
