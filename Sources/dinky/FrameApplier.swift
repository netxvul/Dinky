import AppKit
import DinkyLayout
import DinkyPrivate

@_silgen_name("_AXUIElementGetWindow")
private func axGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// Applies a layout through Accessibility. Scheduling (a queue per app, newest frame wins, one retry)
// lives in FrameScheduler; this file is only the AX side: element lookup, writes, readback, raises.
final class FrameApplier {
    /// A window by its owner too: window ids are reused, so an id alone can name another app's window.
    private struct Key: Hashable {
        let pid: pid_t
        let id: WindowID
    }

    /// A window's element looked up through its app.
    private enum Lookup {
        case found(AXUIElement)
        /// The app did not answer in time.
        case busy
        /// The app answered and named no such window.
        case gone
    }

    /// How long one AX call to an app may block before giving up, so a hung app only stalls its own queue.
    static let timeout: Float = 1

    private var scheduler: FrameScheduler!
    private let lock = NSLock()
    private var elements: [Key: AXUIElement] = [:]
    /// The largest minimum size any window of an app has shown, by bundle id, lowered where a window of the app has
    /// since been seen smaller. Kept across sessions in Application Support, so the write-settle-retry chain that
    /// discovers a minimum runs once per app ever.
    private var appMinimums: [String: CGSize] = [:]
    private let raiseQueue = DispatchQueue(label: "dinky.frames.raise")
    /// The windows a raise is putting into order behind its front one, so that macOS reporting focus on them on the
    /// way is not taken for the user's doing. Under `lock`.
    private var raising = RaiseEchoes()
    private static let minimumsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("dinky/minimum-sizes.json")

    init() {
        appMinimums = Self.loadMinimums()
        scheduler = FrameScheduler(
            prepare: { pid in
                // Enhanced UI (set by VoiceOver and some utilities) makes apps animate and fight frame writes.
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, Self.timeout)
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            },
            read: { [unowned self] job in
                switch element(pid: job.pid, id: job.id) {
                case .found(let element): frame(element, key: Key(pid: job.pid, id: job.id))
                case .busy: .busy
                case .gone: .gone
                }
            },
            write: { [unowned self] job in
                switch element(pid: job.pid, id: job.id) {
                case .found(let element): write(job.frame, to: element, key: Key(pid: job.pid, id: job.id))
                case .busy: false
                case .gone: true
                }
            },
            move: { [unowned self] job in
                switch element(pid: job.pid, id: job.id) {
                case .found(let element): move(job.frame.origin, to: element, key: Key(pid: job.pid, id: job.id))
                case .busy: false
                case .gone: true
                }
            },
            learns: { Self.isOnScreen($0) }
        )
    }

    /// Whether a frame lies wholly on one display, top-left origin as Accessibility has it. A parked column partly off
    /// the screen comes back sized as AppKit keeps it on screen, which says nothing of how small its app lets it be.
    static func isOnScreen(_ frame: CGRect) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return true }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return true }
        return ids.prefix(Int(count)).contains { CGDisplayBounds($0).insetBy(dx: -1, dy: -1).contains(frame) }
    }

    /// Sizes windows refused to shrink below, from readback.
    var minimumSizes: [WindowID: CGSize] { scheduler.minimumSizes }

    /// Windows that refused a size once, waiting for another pass to confirm it.
    var unconfirmedMinimums: Set<WindowID> { scheduler.unconfirmedMinimums }

    /// The size a window refused to shrink below, in each dimension it has refused one; in any other, the largest any
    /// window of its app has refused, so a new window of a known app is laid out right the first time, and one that has
    /// refused only a height keeps the width its app needs.
    func minimumSize(of id: WindowID, app: String?) -> CGSize? {
        let own = scheduler.minimumSizes[id], shared = app.flatMap { app in lock.withLock { appMinimums[app] } }
        guard let own, let shared else { return own ?? shared }
        return CGSize(width: own.width > 0 ? own.width : shared.width, height: own.height > 0 ? own.height : shared.height)
    }

    /// Called on a background queue when an app that was not answering answers again. See
    /// `FrameScheduler.onRecovered`.
    var onRecovered: ((pid_t) -> Void)? {
        get { scheduler.onRecovered }
        set { scheduler.onRecovered = newValue }
    }

    /// Called on a background queue once a step of a window growing to the left is written. See `FrameScheduler.onLeadStep`.
    var onLeadStep: ((WindowID) -> Void)? {
        get { scheduler.onLeadStep }
        set { scheduler.onLeadStep = newValue }
    }

    /// Called on the raise queue once the windows a raise put in order have settled, for focus to be read again: while
    /// they settled, focus on one of them was taken for the raise's doing (see `echoesRaise`), and the user can have
    /// brought it forward meanwhile after all. Set once, on the main thread, before anything is raised.
    var onRaised: (() -> Void)?

    /// Whether `id`, the front app's front window now, is only in front because a raise of dinky's is putting it into
    /// order on the way to putting another window on top of it. See `RaiseEchoes`.
    func echoesRaise(_ id: WindowID) -> Bool {
        let now = CACurrentMediaTime()
        return lock.withLock { raising.echoes(id, at: now) }
    }

    /// Whether the app was too slow to follow an animation step in the current glide. See `FrameScheduler.isSlow`.
    func isSlow(_ pid: pid_t) -> Bool { scheduler.isSlow(pid) }

    /// Forgets which apps were slow, as a glide starts.
    func clearSlow() { scheduler.clearSlow() }

    /// Whether the app stopped answering Accessibility and is being left alone until it does. See `FrameScheduler.isBusy`.
    func isBusy(_ pid: pid_t) -> Bool { scheduler.isBusy(pid) }

    /// The size each window has now, so the animator's first step moves it without writing its size again.
    func assume(_ sizes: [WindowID: CGSize], pids: [WindowID: pid_t]) {
        for (id, size) in sizes { if let pid = pids[id] { scheduler.assume(size, of: id, pid: pid) } }
    }

    /// Forgets a window that is gone: its element and what the scheduler learned about it.
    func forget(_ id: WindowID) {
        lock.withLock { elements = elements.filter { $0.key.id != id } }
        scheduler.forget(id)
    }

    /// The window was seen at `size`, as when the user resized it: its minimum and its app's are lowered to it where
    /// bigger, since it would not go below a minimum that was right, and the app's may have been grown from the window's.
    /// False when neither was bigger.
    @discardableResult
    func saw(_ size: CGSize, of id: WindowID, app: String?) -> Bool {
        let own = scheduler.lowerMinimum(of: id, to: size)
        guard let app, lowerAppMinimum(app, to: size) else { return own }
        saveMinimums()
        return true
    }

    /// Forgets every minimum size learned, this session's and the saved ones.
    func forgetMinimums() {
        scheduler.forgetMinimums()
        lock.withLock { appMinimums = [:] }
        try? FileManager.default.removeItem(at: Self.minimumsURL)
    }

    /// Drops every frame not written yet.
    func cancel() { scheduler.cancel() }

    /// Writes one step of an animation: no readback, no retry, no raising.
    func step(_ jobs: [FrameJob]) { scheduler.step(jobs) }

    /// Write every frame in `layout`, then raise overlapping windows into the layout's order if they are not,
    /// unless that would move focus away from a window other than `front`, the one the layout puts on top.
    /// `completion` runs on a background queue with the readback of every app touched.
    func apply(_ layout: Layout, pids: [WindowID: pid_t], front: WindowID? = nil, ignoringBusy: Bool = false,
               completion: @escaping ([FrameResult]) -> Void = { _ in }) {
        let jobs = layout.order.compactMap { id in
            pids[id].map { FrameJob(pid: $0, id: id, frame: layout.frames[id]!) }
        }
        scheduler.submit(jobs, ignoringBusy: ignoringBusy) { [unowned self] results in
            rememberAppMinimums(results)
            raiseIntoOrder(layout, pids: pids, front: front) { completion(results) }
        }
    }

    /// Raise overlapping windows into the layout's order if they are not, as `apply` does after writing.
    func raiseIntoOrder(_ layout: Layout, pids: [WindowID: pid_t], front: WindowID?, then done: @escaping () -> Void = {}) {
        raiseQueue.async {
            var ids = layout.raises(current: onScreenOrder())
            // Raising makes a window its app's key window, so the front window goes last when its app had another
            // raised: it overlaps nothing (a column in view of a scrolling strip) and would lose focus otherwise.
            if let front, ids.last != front, let pid = pids[front], ids.contains(where: { pids[$0] == pid }) {
                ids = ids.filter { $0 != front } + [front]
            }
            if Self.raisingKeepsFocus(ids, front: front, pids: pids) { self.raise(ids, pids: pids, front: front) }
            done()
        }
    }

    /// Raise pinned windows to the front, back to front, so the last is frontmost: they overlap nothing in view, only
    /// the band's windows sliding under them. Not when that could move focus (see `raisingKeepsFocus`).
    func raisePins(_ ids: [WindowID], pids: [WindowID: pid_t], front: WindowID?) {
        raiseQueue.async {
            guard Self.raisingKeepsFocus(ids, front: front, pids: pids) else { return }
            self.raise(ids, pids: pids, front: front)
        }
    }

    /// Minimums are recorded after a retry; note each new one under its app. A window written that came out smaller than
    /// its app's in a dimension it has none of its own in, and so takes its app's in, where it was put and wholly on
    /// screen, as one asked for less than that where the layout could not make the room, shows the app's is too big for
    /// its windows, as one learned from an app that had not caught up after all: the app's is lowered to it, in each such
    /// dimension the window took at least what it was asked, so coming out smaller than asked, as at a maximum size,
    /// lowers nothing.
    private func rememberAppMinimums(_ results: [FrameResult]) {
        let minimums = scheduler.minimumSizes
        var changed = false
        for result in results where result.written {
            guard let app = NSRunningApplication(processIdentifier: result.job.pid)?.bundleIdentifier else { continue }
            let own = minimums[result.job.id] ?? .zero
            if own != .zero, result.retried {
                lock.withLock {
                    let grown = appMinimums[app]?.grown(to: own) ?? own
                    if appMinimums[app] != grown { appMinimums[app] = grown; changed = true }
                }
            }
            guard let got = result.got, abs(got.minX - result.job.frame.minX) <= 2, abs(got.minY - result.job.frame.minY) <= 2,
                  Self.isOnScreen(result.job.frame) else { continue }
            let size = CGSize(width: own.width == 0 && got.width >= result.job.frame.width - 2 ? got.width : .infinity,
                              height: own.height == 0 && got.height >= result.job.frame.height - 2 ? got.height : .infinity)
            if lowerAppMinimum(app, to: size) { changed = true }
        }
        if changed { saveMinimums() }
    }

    /// Lowers the app's minimum to `size` in each dimension it is more than 2 pt bigger in. False when it has none bigger.
    private func lowerAppMinimum(_ app: String, to size: CGSize) -> Bool {
        lock.withLock {
            guard let minimum = appMinimums[app] else { return false }
            let lowered = minimum.lowered(to: size)
            guard lowered != minimum else { return false }
            appMinimums[app] = lowered == .zero ? nil : lowered
            return true
        }
    }

    private static func loadMinimums() -> [String: CGSize] {
        guard let data = try? Data(contentsOf: minimumsURL),
              let raw = try? JSONDecoder().decode([String: [CGFloat]].self, from: data) else { return [:] }
        return raw.compactMapValues { $0.count == 2 ? CGSize(width: $0[0], height: $0[1]) : nil }
    }

    private func saveMinimums() {
        let raw = lock.withLock { appMinimums.mapValues { [$0.width, $0.height] } }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? FileManager.default.createDirectory(at: Self.minimumsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.minimumsURL, options: .atomic)
    }

    /// Raising a window of the frontmost app makes it that app's key window. So windows are raised only when
    /// that cannot move focus: the focused window is the layout's front one, or its app owns none of them.
    /// Otherwise the layout is older than the focus, say right after Cmd-` or while a pass that started before
    /// a newer one finishes, and raising would take focus back. The next pass raises once the tree has caught up.
    private static func raisingKeepsFocus(_ ids: [WindowID], front: WindowID?, pids: [WindowID: pid_t]) -> Bool {
        let focused = dinky_border_focused_window()
        guard focused != 0, focused != front else { return true }
        let owner = dinky_window_info(focused).pid
        return !ids.contains { pids[$0] == owner }
    }

    /// Raise back to front, so the last raised ends up frontmost. AXRaise does not activate the app.
    /// An app that is not answering is skipped: a raise would only wait in its queue to be acted on long after.
    /// Each raise puts its window in front of its app's others until the ones meant to be in front of it are raised in
    /// turn, and macOS reports that as focus moving to it, for the app in front. So while the raise runs, and for
    /// `RaiseEchoes.settle` after, the windows of the app in front and of `front`'s, which dinky may be activating, count
    /// as raised behind `front` (`echoesRaise`); then `onRaised` has focus read again.
    private func raise(_ ids: [WindowID], pids: [WindowID: pid_t], front: WindowID?) {
        let focused = dinky_border_focused_window()
        var apps: Set<pid_t> = []
        if let front, let pid = pids[front] { apps.insert(pid) }
        if focused != 0 { apps.insert(dinky_window_info(focused).pid) }
        let echoing = RaiseEchoes.echoing(ids, front: front, owners: pids, apps: apps)
        if !echoing.isEmpty {
            let began = CACurrentMediaTime()
            lock.withLock { raising.begin(echoing, front: front, at: began) }
        }
        defer { if !echoing.isEmpty { endRaise() } }
        var unanswered: Set<pid_t> = []
        for id in ids {
            guard let pid = pids[id], !unanswered.contains(pid), !scheduler.isBusy(pid) else { continue }
            switch element(pid: pid, id: id) {
            case .found(let element):
                let started = Date()
                let error = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                if Self.timedOut(error, since: started) { unanswered.insert(pid) }
            case .busy: unanswered.insert(pid)
            case .gone: continue
            }
        }
    }

    /// Ends the raise under way: its windows settle for `RaiseEchoes.settle`, and then focus is read again, a little
    /// after, so the read falls past the settle whatever the clocks' rounding.
    private func endRaise() {
        let ended = CACurrentMediaTime()
        lock.withLock { raising.end(at: ended) }
        raiseQueue.asyncAfter(deadline: .now() + RaiseEchoes.settle + 0.02) { [unowned self] in onRaised?() }
    }

    private func element(pid: pid_t, id: WindowID) -> Lookup {
        let key = Key(pid: pid, id: id)
        if let cached = lock.withLock({ elements[key] }) { return .found(cached) }
        let lookup = Self.lookup(pid: pid, id: id)
        if case .found(let element) = lookup { lock.withLock { elements[key] = element } }
        return lookup
    }

    /// As `axWindow`, telling an app that did not answer from one that named no such window. Electron apps like
    /// Obsidian can answer AXWindows with an empty list while still naming the window as their main or focused one,
    /// so those are asked too.
    private static func lookup(pid: pid_t, id: WindowID) -> Lookup {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var value: CFTypeRef?
        var started = Date()
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if timedOut(error, since: started) { return .busy }
        var found = (value as? [AXUIElement] ?? []).first { windowID($0) == id }
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] where found == nil {
            started = Date()
            value = nil
            let error = AXUIElementCopyAttributeValue(app, attribute as CFString, &value)
            if timedOut(error, since: started) { return .busy }
            if error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID(), windowID(value as! AXUIElement) == id {
                found = (value as! AXUIElement)
            }
        }
        guard let found else { return .gone }
        AXUIElementSetMessagingTimeout(found, timeout)
        return .found(found)
    }

    private static func windowID(_ element: AXUIElement) -> WindowID {
        var wid: CGWindowID = 0
        return axGetWindow(element, &wid) == .success ? wid : 0
    }

    /// Whether a call failed because the app did not answer within the timeout. The same error comes back at once
    /// from an app that cannot take Accessibility messages at all (it has quit, or never answers them); that one is
    /// not busy, and waiting for it would keep its window in a tile it never moves into.
    private static func timedOut(_ error: AXError, since started: Date) -> Bool {
        error == .cannotComplete && Date().timeIntervalSince(started) >= Double(timeout) / 2
    }

    /// Drops a cached element the app no longer knows, so the next call looks the window up afresh.
    private func noteInvalid(_ error: AXError, key: Key) {
        if error == .invalidUIElement { lock.withLock { elements[key] = nil } }
    }

    // Size, position, size: the first size lets a window near the screen edge move, the second
    // fixes the size if the move clamped it. False when the app did not answer; the rest is then not sent.
    private func write(_ frame: CGRect, to element: AXUIElement, key: Key) -> Bool {
        var size = frame.size, origin = frame.origin
        let sizeValue = AXValueCreate(.cgSize, &size)!, originValue = AXValueCreate(.cgPoint, &origin)!
        for (attribute, value) in [(kAXSizeAttribute, sizeValue), (kAXPositionAttribute, originValue), (kAXSizeAttribute, sizeValue)] {
            let started = Date()
            let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
            if Self.timedOut(error, since: started) { return false }
            noteInvalid(error, key: key)
            if error == .invalidUIElement { return true }
        }
        return true
    }

    /// False when the app did not answer.
    private func move(_ origin: CGPoint, to element: AXUIElement, key: Key) -> Bool {
        var origin = origin
        let started = Date()
        let error = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
        noteInvalid(error, key: key)
        return !Self.timedOut(error, since: started)
    }

    private func frame(_ element: AXUIElement, key: Key) -> FrameRead {
        var position: AXValue?, size: AXValue?
        if let failed = copy(kAXPositionAttribute, of: element, key: key, into: &position) { return failed }
        if let failed = copy(kAXSizeAttribute, of: element, key: key, into: &size) { return failed }
        var frame = CGRect.zero
        guard AXValueGetValue(position!, .cgPoint, &frame.origin), AXValueGetValue(size!, .cgSize, &frame.size) else { return .gone }
        return .frame(frame)
    }

    /// Copies one AXValue attribute into `out`. Nil when it was read, otherwise what the failure says of the window.
    private func copy(_ attribute: String, of element: AXUIElement, key: Key, into out: inout AXValue?) -> FrameRead? {
        var value: CFTypeRef?
        let started = Date()
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if Self.timedOut(error, since: started) { return .busy }
        noteInvalid(error, key: key)
        guard error == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return .gone }
        out = (value as! AXValue)
        return nil
    }
}

/// On-screen windows, front to back.
/// The windows on screen front to back, each with its level (`kCGWindowLayer`).
func onScreenStack() -> [(id: WindowID, layer: Int)] {
    let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { window in
        (window[kCGWindowNumber as String] as? WindowID).map { ($0, window[kCGWindowLayer as String] as? Int ?? 0) }
    }
}

func onScreenOrder() -> [WindowID] {
    let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { $0[kCGWindowNumber as String] as? WindowID }
}
