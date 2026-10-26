import AppKit
import os
import DinkyPrivate

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

func windowPID(_ wid: UInt32) -> pid_t? {
    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]] ?? []
    return info.first?[kCGWindowOwnerPID as String] as? pid_t
}

// A non-zero `timeout` (seconds) bounds how long AX calls on the app and the window may block.
// Electron apps like Obsidian can answer AXWindows with an empty list while still naming the window
// as their main or focused one, so those are asked too.
func axWindow(pid: pid_t, wid: UInt32, timeout: Float = 0) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    if timeout > 0 { AXUIElementSetMessagingTimeout(app, timeout) }
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
    let windows = value as? [AXUIElement] ?? []
    guard let window = windows.first(where: { axWindowID($0) == wid })
        ?? [kAXMainWindowAttribute, kAXFocusedWindowAttribute].lazy.compactMap({ axElement(app, $0) })
            .first(where: { axWindowID($0) == wid }) else { return nil }
    if timeout > 0 { AXUIElementSetMessagingTimeout(window, timeout) }
    return window
}

private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func axWindowID(_ element: AXUIElement) -> UInt32 {
    var wid: CGWindowID = 0
    return _AXUIElementGetWindow(element, &wid) == .success ? wid : 0
}

/// The app's main window, wherever it is: the one activating the app brings forward. 0 if it has none.
func mainWindowID(of pid: pid_t) -> UInt32 {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    return axElement(app, kAXMainWindowAttribute).map(axWindowID) ?? 0
}

/// The app's focused window, wherever it is. 0 if it has none.
func focusedWindowID(of pid: pid_t, timeout: Float = 0.25) -> UInt32 {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeout)
    return axElement(app, kAXFocusedWindowAttribute).map(axWindowID) ?? 0
}

func frontWindowID() -> UInt32 {
    guard let app = NSWorkspace.shared.frontmostApplication else { return 0 }
    var value: CFTypeRef?
    let element = AXUIElementCreateApplication(app.processIdentifier)
    // Asked on the main thread, which also runs the event taps: an app slow to answer must not hold every key and
    // click with it, nor dinky, while its own frames wait on WindowServer.
    AXUIElementSetMessagingTimeout(element, 0.1)
    guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
          let window = value else { return 0 }
    AXUIElementSetMessagingTimeout(window as! AXUIElement, 0.1)
    return axWindowID(window as! AXUIElement)
}

/// Focuses a window on a Space that is on screen: AX raise, then activate its app. Never switches Spaces:
/// the activation is dinky's own, so the activation follower is told not to chase the app's frontmost
/// window, which can still be one on another Space when the activation lands. This is the primitive for windows
/// no tree models (e.g. `focusOnScreen` when the coordinator is not running); a window the coordinator models is
/// focused through `Coordinator.focus(_:)`, which also arms the grace against stale focus reads.
///
/// The Accessibility calls into the app run on a queue of their own and the app is activated once they are done:
/// the app can be slow to answer, and the main thread, which also runs the event taps, must not wait on it. An app
/// that is not answering dinky's frame writes either is only activated. A newer focus supersedes one still under
/// way, and so does anything else that brings another app to the front meanwhile: a click, Cmd-Tab. `done` runs on
/// the main thread with whether the app was activated.
func focusWindow(pid: pid_t, id: UInt32, done: ((Bool) -> Void)? = nil) {
    // Focus is on a window again, even when it is the one that had it before a `focus-monitor`.
    AppState.shared.displays.focusOverride = nil
    if let display = AppState.shared.displays.display(ofWindow: id) {
        noteOwnSwitch(to: display.currentSpaceID, on: display.uuid)
    }
    focusRequests += 1
    let request = focusRequests
    focusLatest.withLock { $0 = request }
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let activate = {
        let now = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard request == focusRequests, now == front || now == pid else { done?(false); return }
        NSRunningApplication(processIdentifier: pid)?.activate()
        done?(true)
    }
    if AppState.shared.coordinator?.applier.isBusy(pid) == true { return activate() }
    focusQueue.async {
        let current = { focusLatest.withLock { $0 } == request }
        if current(), let element = axWindow(pid: pid, wid: id, timeout: focusTimeout) {
            // Raise alone makes the window main; the app's key window can stay one on another Space, and the
            // next command would then act on that one. Make this window main and key explicitly.
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            if current() { AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
            if current() { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
        }
        DispatchQueue.main.async(execute: activate)
    }
}

/// Whether the left button is down, or was pressed within `seconds`: a click may still be activating an app, which
/// dinky's windows writes and screen captures should not reach yet.
func clickUnderWay(within seconds: CFTimeInterval) -> Bool {
    CGEventSource.buttonState(.combinedSessionState, button: .left)
        || CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown) < seconds
}

/// Where `focusWindow` talks to the app it focuses, off the main thread.
private let focusQueue = DispatchQueue(label: "dinky.focus", qos: .userInteractive)
/// How long each Accessibility call of `focusWindow` may wait on the app.
private let focusTimeout: Float = 0.5
/// Counts `focusWindow` calls, on the main thread only; the newest is the one that activates its app.
private var focusRequests = 0
/// The newest request, for the queue to skip calls into an app that a later focus has made moot.
private let focusLatest = OSAllocatedUnfairLock(initialState: 0)

/// Activates Finder when `display` has no window to focus, as macOS does on an empty Space with the desktop shown.
/// Without the desktop, or with separate Spaces per display, macOS can leave active an app whose window is on another
/// Space. Left alone when activating Finder would bring one of its windows forward: one on screen, or one anywhere
/// when macOS switches to a Space with the app's windows.
func focusDesktop(of display: Display) {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
          let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != finder.processIdentifier,
          dinky_window_space_id(frontWindowID()) != display.currentSpaceID else { return }
    let app = front.localizedName ?? "the front app"
    let swoosh = dockSetting("workspaces-auto-swoosh") ?? true
    guard normalWindows(of: finder.processIdentifier, swoosh ? [.optionAll] : [.optionOnScreenOnly]).isEmpty else {
        print("\(stamp()) focus: left the keyboard with \(app), activating Finder would show its window")
        fflush(stdout)
        return
    }
    print("\(stamp()) focus: activated Finder in place of \(app), which has no window here")
    fflush(stdout)
    noteOwnSwitch(to: display.currentSpaceID, on: display.uuid)
    finder.activate()
}
