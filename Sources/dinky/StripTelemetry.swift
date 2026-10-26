import AppKit
import DinkyLayout
import DinkyPrivate

// Telemetry for windows that drop out of sight in a scrolling strip, all on lines starting `strip`:
// - `strip N: view` each time the columns in view change, with the focused window and what went to the edges;
// - `strip N: focus` when macOS's focus moves the strip to a window that was parked, and from which window;
// - `strip N: focus … passed over` when macOS reports focus on a window only because dinky is raising it into order,
//   which nothing follows;
// - `strip N: fingers` when fingers take hold of the strip to scroll it (`[gestures.scroll]`), let go or lose it;
// - `strip N: + / -` when a window joins or leaves the strip, and why;
// - `strip N: landed` when a write left a window short of where the strip put it;
// - `strip N: check` a moment after the strip settles, for a window not where the strip has it, or one on the
//   strip's Space that no tree holds, sitting off the screen. Each finding is logged once, and again when it clears.
// N is the Space the strip is on. Main thread only.
final class StripTelemetry {
    /// More than this much of a window on screen counts as in view: a parked column's peek is less.
    private static let inView: CGFloat = Workspace.peek + 1
    /// How far a window may be from where the strip has it before a check reports it: apps that snap their sizes, and
    /// AppKit's padding at a screen edge, account for a few points.
    private static let slack: CGFloat = 4
    /// How long after a pass the check runs, and how many times it waits on a glide still under way.
    private static let settle: TimeInterval = 1.5
    private static let retries = 6

    private var views: [UInt64: String] = [:]
    private var findings: [UInt64: [WindowID: String]] = [:]
    private var checks: [UInt64: Int] = [:]
    private var checkTokens = 0
    /// By strip, the last event that could move it, for the next `view` line.
    private var causes: [UInt64: String] = [:]
    /// By strip, the windows logged as passed over since its last pass, so a raise read twice is logged once.
    private var passed: [UInt64: Set<WindowID>] = [:]

    var name: (WindowID) -> String = { "\($0)" }

    private func log(_ key: UInt64, _ text: String) {
        print("\(stamp()) strip \(key): \(text)")
        fflush(stdout)
    }

    private func names(_ ids: [WindowID]) -> String { "[" + ids.map(name).joined(separator: ", ") + "]" }

    private static func shown(_ frame: CGRect, on screen: CGRect) -> CGFloat {
        let part = frame.intersection(screen)
        return part.isNull ? 0 : part.width
    }

    private static func describe(_ r: CGRect) -> String {
        "(\(Int(r.minX.rounded())), \(Int(r.minY.rounded())), \(Int(r.width.rounded())), \(Int(r.height.rounded())))"
    }

    /// A pass laid out a strip: logs the columns in view, the focused window, and the windows parked at each edge,
    /// when that differs from the last pass's.
    func pass(_ key: UInt64, _ workspace: Workspace, _ layout: Layout) {
        guard workspace.isScrolling, let screen = layout.screen else { return }
        passed[key] = nil
        let columns = workspace.stripColumns
        var view: [WindowID] = [], left: [WindowID] = [], right: [WindowID] = []
        let pinned = workspace.pinnedWindows
        // With a pin, a band window under it is out of view, and its side is the band's.
        let middle = pinned.isEmpty ? screen.midX : workspace.bandRect.midX
        for id in columns.joined() where !pinned.contains(id) {
            guard let frame = layout.frames[id] else { continue }
            if Self.shown(frame, on: screen) > Self.inView, pinned.isEmpty || workspace.isInView(id) { view.append(id) }
            else if frame.midX < middle { left.append(id) }
            else { right.append(id) }
        }
        let focus = workspace.focused.map(name) ?? "none"
        let line = "view \(names(view)), focus \(focus), left \(left.count), right \(right.count)"
            + (pinned.isEmpty ? "" : ", pinned \(names(pinned))")
        let cause = causes.removeValue(forKey: key)
        guard views[key] != line else { return }
        views[key] = line
        log(key, line + (cause.map { ", after \($0)" } ?? ""))
        log(key, "columns " + columns.map { names($0) }.joined(separator: " "))
    }

    /// macOS moved focus to `id` in a strip, from `from`: logged when `id` was not in view, so the strip scrolls away
    /// from what was on screen without a command of dinky's.
    func focus(_ key: UInt64, _ workspace: Workspace, to id: WindowID, from: WindowID?, click: Bool) {
        guard workspace.isScrolling else { return }
        causes[key] = "macOS focused \(name(id))" + (click ? " on a click" : "")
        guard !workspace.isInView(id) else { return }
        log(key, "focus \(name(id)) by macOS, was parked; focus was \(from.map(name) ?? "none")"
            + (click ? ", a click under way" : ", no click"))
    }

    /// dinky moved focus in a strip itself: a command, the window switcher, a peek clicked.
    func command(_ key: UInt64, _ what: String) { causes[key] = what }

    /// Fingers took hold of the strip to scroll it (`[gestures.scroll]`), let go of it, or lost it: logged as
    /// `strip N: fingers …`, and the cause of the next `view` line.
    func fingers(_ key: UInt64, _ what: String) {
        causes[key] = "fingers \(what)"
        log(key, "fingers \(what)")
    }

    /// Pins raised over band windows, and the windows raised after them to keep their apps' focus, logged as
    /// `strip N: pins raised …` with what called for it.
    func pinsRaised(_ key: UInt64, _ ids: [WindowID], _ cause: String) {
        log(key, "pins raised \(names(ids)), \(cause)")
    }

    /// macOS reported focus on `id` only because dinky was raising it into order behind another window, and
    /// `syncFocus` did not follow it. Logged once for each window until the strip's next pass.
    func passedOver(_ key: UInt64, _ workspace: Workspace, _ id: WindowID) {
        guard workspace.isScrolling, passed[key, default: []].insert(id).inserted else { return }
        log(key, "focus \(name(id)) passed over, raised into order; focus stays \(workspace.focused.map(name) ?? "none")")
    }

    /// A window joined the strip (`joined`) or left it, and why.
    func member(_ key: UInt64, _ workspace: Workspace?, _ id: WindowID, joined: Bool, _ why: String) {
        guard workspace?.isScrolling == true else { return }
        causes[key] = "\(joined ? "+" : "-") \(name(id))"
        let live = dinky_window_info(id)
        let at = live.exists ? " at \(Self.describe(live.frame))" : ""
        log(key, "\(joined ? "+" : "-") \(name(id)) (\(why))\(at)")
    }

    /// A strip's write landed: logs each window that came out more than a few points from where it was asked to go,
    /// or could not be read or written.
    func landed(_ key: UInt64, _ workspace: Workspace, _ results: [FrameResult]) {
        guard workspace.isScrolling else { return }
        for result in results {
            let id = result.job.id
            if result.busy { log(key, "landed \(name(id)): app busy, wanted \(Self.describe(result.target))"); continue }
            if result.gone { log(key, "landed \(name(id)): unreadable, wanted \(Self.describe(result.target))"); continue }
            guard let got = result.got else { continue }
            let target = result.target
            guard abs(got.minX - target.minX) > Self.slack || abs(got.minY - target.minY) > Self.slack
                    || abs(got.width - target.width) > Self.slack || abs(got.height - target.height) > Self.slack else { continue }
            log(key, "landed \(name(id)): wanted \(Self.describe(target)) got \(Self.describe(got))"
                + (result.retried ? " after a retry" : ""))
        }
    }

    /// Runs `check` once the strip has been still for a moment: after `settle`, or once more each `settle` while
    /// `moving` holds, up to `retries` times. A later pass replaces a waiting check.
    func schedule(_ key: UInt64, moving: @escaping () -> Bool, check: @escaping () -> Void) {
        checkTokens += 1
        let token = checkTokens
        checks[key] = token
        var left = Self.retries
        func fire() {
            guard checks[key] == token else { return }
            if moving(), left > 0 {
                left -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { fire() }
                return
            }
            checks[key] = nil
            check()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { fire() }
    }

    /// Compares where the window server has each window of the strip with where the strip puts it, and looks for
    /// windows on the strip's Space that no tree holds sitting off the screen (`loose`, with their placements).
    /// Reports what is new since the last check, and what cleared.
    func check(_ key: UInt64, _ workspace: Workspace, loose: [(id: WindowID, placement: String)], busy: (WindowID) -> Bool) {
        guard workspace.isScrolling else { return }
        let layout = workspace.layout()
        guard let screen = layout.screen else { return }
        var now: [WindowID: String] = [:]
        for id in workspace.windows {
            guard let want = layout.frames[id] else { continue }
            let live = dinky_window_info(id)
            guard live.exists else { now[id] = "no window server frame, wanted \(Self.describe(want))"; continue }
            let got = live.frame
            guard abs(got.minX - want.minX) > Self.slack || abs(got.minY - want.minY) > Self.slack
                    || abs(got.width - want.width) > Self.slack || abs(got.height - want.height) > Self.slack else { continue }
            let wantShown = Self.shown(want, on: screen), gotShown = Self.shown(got, on: screen)
            let what = wantShown > Self.inView && gotShown <= Self.inView ? "should be in view but is off screen"
                : wantShown <= Self.inView && gotShown > Self.inView ? "should be parked but shows"
                : "out of place"
            now[id] = "\(what): wanted \(Self.describe(want)) is \(Self.describe(got)), \(Int(gotShown))pt shows"
                + (busy(id) ? ", app busy" : "")
        }
        for (id, placement) in loose {
            let live = dinky_window_info(id)
            guard live.exists, Self.shown(live.frame, on: screen) <= Self.inView else { continue }
            now[id] = "in no strip (\(placement)) and off screen at \(Self.describe(live.frame))"
        }
        let before = findings[key] ?? [:]
        for (id, text) in now.sorted(by: { $0.key < $1.key }) where before[id] != text { log(key, "check \(name(id)) \(text)") }
        for id in before.keys.sorted() where now[id] == nil { log(key, "check \(name(id)) back in place") }
        findings[key] = now.isEmpty ? nil : now
    }
}
