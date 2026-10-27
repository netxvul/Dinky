import AppKit
import DinkyLayout
import DinkyPrivate

// Glides windows to their tiles. Each window rides a spring, or an easing over a fixed time, from where it is to its
// tile, stepped on every frame of the display the tree is on and written through the applier's per-app queues without
// readback. Once a tree's windows have arrived, its pass finishes as an unanimated one would: the full write with
// readback, retry and raises. A new pass mid-flight retargets the windows: on the spring they curve to their new
// tiles, keeping their speed; an easing starts over from where they are. A scrolling strip glides as a whole: its
// windows ride in strip coordinates, unparked, and each frame the tree's `place` puts them all on screen together,
// so a long scroll passes the columns between across the screen in turn.
//
// Frames are stepped and written at the full rate of the display the tree last set gliding is on (120 a second on a
// ProMotion display), each step taken to when its frame shows, with App Nap held off meanwhile. Each app moves its own
// windows; one that takes longer than `FrameScheduler.slowStep` over a step is then moved only every third frame
// rather than dropped for the rest of the glide, so it keeps gliding at a pace it can hold instead of freezing and
// jumping to its tile at the end; frames coalesce per window in the scheduler, so a throttled app never has a backlog
// to leap through. A strip's column of a slow app's window and a quick app's would come apart that way, so its quick
// windows keep with the slow one as it shows, and wait for it at the end (see `ColumnHold`).
//
// A tree can glide something other than its windows instead, such as their Dock transforms (see ScriptingAddition): its
// frames go to its `sink` and nowhere else, at the display's full rate, since no app has to keep up.
//
// A tree can also follow fingers (`follow`): its windows ride a stiff spring towards targets that move with every touch
// frame, and never arrive, however still they hold, until the fingers let go and its next pass glides them on from
// where they are, at their speed, on the configured spring. Main thread only.
final class Animator: NSObject {
    private struct Entry {
        var animation: FrameAnimation
        let pid: pid_t
        var key: UInt64
        /// How long this pass takes, as a multiple of the configured time: longer for a long strip scroll.
        var stretch = 1.0
        /// How it glides growing to the left, if it does. See `ResizeOnce.Anchor`.
        var anchor: ResizeOnce.Anchor?
        /// Since when it has stood at its start, growing to the left, until its first step is written and it was led
        /// past the screen edge with it, which can take its app a frame or more: set off sooner, it would jump.
        var heldSince: CFTimeInterval?

        /// Where its steps write it now.
        var frame: CGRect { anchor.map { $0.frame(animation.frame) } ?? animation.frame }
    }

    private let applier: FrameApplier
    private var entries: [WindowID: Entry] = [:]
    /// By tree, how its frames go on screen, for a strip: `place` takes every window's frame in strip coordinates,
    /// those resting at their targets, `base`, with the moving ones where they are now. A resting window's place can
    /// change as the others move (a parked one tucking under the column arriving at the edge), so `resting` has where
    /// each one is on screen, with its app, and it is written when that changes.
    private var placers: [UInt64: (base: [WindowID: CGRect], place: ([WindowID: CGRect]) -> [WindowID: CGRect],
                                   resting: [WindowID: (pid: pid_t, frame: CGRect)])] = [:]
    /// By tree, where its frames go instead of to its windows.
    private var sinks: [UInt64: ([WindowID: CGRect]) -> Void] = [:]
    /// The frame last written for each moving window, so a parked window that stays put is not written every frame.
    private var written: [WindowID: CGRect] = [:]
    /// Counts steps, to move a slow app on only some of them.
    private var stepCount = 0
    /// By tree, the rest of its latest pass, run once its windows have arrived.
    private var finishes: [UInt64: () -> Void] = [:]
    private var link: CADisplayLink?
    /// The display the link was made for, as `displayOf` found it; nil where that was unknown. Its link is on its
    /// screen, or on the main one where no screen shows it, so a display with no screen yet does not have the link
    /// made again on every call: the screens changing makes it again (`screensChanged`).
    private var linkDisplay: CGDirectDisplayID?
    /// When the last frame stepped was to show, so each step goes as far as when its own will.
    private var lastTarget: CFTimeInterval?
    /// Since when the link has run, how many frames it stepped, the longest wait between two and when it ended, and the
    /// longest a tree's placer or sink took over one frame, for the log once it pauses: how evenly the glides went.
    private var pace: (since: CFTimeInterval, frames: Int, longest: CFTimeInterval, longestAt: Date?,
                       slowestCall: CFTimeInterval)?
    /// Held while windows glide, so App Nap does not bunch the frames, as SlideScroll holds it.
    private var activity: NSObjectProtocol?
    /// When a frame was last stepped, on the wall clock, so a display link that stopped firing is noticed.
    private var lastStepAt = CACurrentMediaTime()
    private var watchdog: Timer?
    /// The configured spring, which windows the fingers let go of glide on whatever `curve` is.
    private var spring = Spring(response: 0.363, damping: 1)
    private var curve = AnimationCurve.spring(Spring(response: 0.363, damping: 1))
    /// By tree, the curve its windows glide on in place of `curve`, as fingers following or letting go have it.
    private var curves: [UInt64: AnimationCurve] = [:]
    /// Trees whose windows follow fingers (`follow`): they never arrive, however still, until `endFollow`.
    private var following: Set<UInt64> = []
    /// How long a window growing to the left stands at its start at most, waiting for its lead-in to be written.
    private static let leadInWait: CFTimeInterval = 0.25
    private var timeout = 1.0
    /// Where windows came to rest the last time they were written unanimated, by the frame they were asked for.
    /// An app that snaps to a grid (Terminal) or keeps a minimum size never reaches its tile exactly, and
    /// must not be sent gliding towards it on every pass.
    private var landed: [WindowID: (asked: CGRect, got: CGRect)] = [:]
    /// Called with the windows that just arrived.
    var onArrive: ([WindowID]) -> Void = { _ in }
    /// By tree, the strip's columns, so the windows of one glide together.
    var columns: (UInt64) -> [[WindowID]] = { AppState.shared.coordinator?.workspaces[$0]?.stripColumns ?? [] }
    /// By tree, the display its windows are on, so the link steps at that display's rate.
    var displayOf: (UInt64) -> CGDirectDisplayID? = { _ in nil }
    /// The tree last set gliding, whose display the link steps on unless another gliding is faster.
    private var lastKey: UInt64?
    /// The display chosen for the link this turn of the main queue (`run`).
    /// Chosen for the trees then gliding: chosen again within the turn when that set changes.
    private var choice: (keys: Set<UInt64>, display: CGDirectDisplayID?)?
    /// Apps found too slow to follow a glide frame by frame, in this glide or an earlier one: a column holds to their
    /// windows from a glide's first frame, rather than snapping back to them once they have fallen behind.
    private var slowPids: Set<pid_t> = []
    /// Apps of `slowPids` that have kept up again during the glide: no longer slow once the next one starts.
    private var recovered: Set<pid_t> = []
    /// Each window's app, as the passes have it, so a column still knows its slow window once that has arrived.
    private var windowPids: [WindowID: pid_t] = [:]
    /// Since when each window at its target has waited for the slow window of its column to land.
    private var waitingSince: [WindowID: CFTimeInterval] = [:]
    /// How long a window at its target waits for the slow window of its column at most.
    private static let columnWait: CFTimeInterval = 0.5
    /// The spring windows follow fingers on: SlideScroll's, stiffness 3000 or so, about 31 ms behind them at 120 frames
    /// a second, which smooths their uneven frames.
    private static let followCurve = AnimationCurve.spring(Spring(response: 0.115, damping: 1))

    init(applier: FrameApplier) {
        self.applier = applier
        super.init()
        applier.onLeadStep = { [weak self] id in DispatchQueue.main.async { self?.entries[id]?.heldSince = nil } }
        // The link is made for one screen; with that screen gone it never fires again.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.screensChanged() }
    }

    /// How long a window takes to arrive, roughly on the spring and exactly along an easing; nil for the spring, whose
    /// `damping` 1 eases in without overshooting, and less overshoots.
    func configure(durationMs ms: Int, easing: Easing?, damping: Double) {
        let duration = Double(ms) / 1000
        spring = Spring(response: duration, damping: damping)
        curve = easing.map { .eased($0, duration: duration) } ?? .spring(spring)
        timeout = max(1, 4 * duration)
    }

    /// What windows the fingers let go of glide on: the configured spring, whatever the curve, since it carries on at
    /// the speed they had where an easing would start over from rest.
    var releaseCurve: AnimationCurve { .spring(spring) }

    /// Whether dinky is moving the window right now, so its frame changes are not the user's.
    func isAnimating(_ id: WindowID) -> Bool { entries[id] != nil }
    /// Whether the tree has a glide under way: windows stepping, or its finish, placer or sink still held.
    func isGliding(_ key: UInt64) -> Bool {
        finishes[key] != nil || placers[key] != nil || sinks[key] != nil || entries.values.contains { $0.key == key }
    }

    /// The windows moving now.
    var animating: [WindowID] { Array(entries.keys) }

    /// Where a gliding window's steps write it now; nil for one not gliding.
    func frame(of id: WindowID) -> CGRect? { entries[id]?.frame }

    /// A new glide: every app gets another chance to keep up, and one that kept up again in the last, its recovery
    /// heard by now, is slow no longer.
    private func clearSlow() {
        recovered.formUnion(applier.takeRecovered())
        recovered = recovered.filter { !applier.isSlow($0) }
        slowPids.subtract(recovered)
        recovered = []
        applier.clearSlow()
    }

    /// A tree sets off with none of its windows gliding: apps that kept up again are slow no longer, unless a window of
    /// theirs glides on elsewhere where a column can hold to it: placed on screen by its tree, not handed to a sink.
    private func settleRecovered() {
        let gliding = Set(entries.values.filter { placers[$0.key] != nil && sinks[$0.key] == nil }.map(\.pid))
        slowPids.subtract(recovered.subtracting(gliding))
        recovered.formIntersection(gliding)
    }

    /// Move the tree's windows from `starts` to `targets`, then run `finish`. Windows already there, or with
    /// no start, are left to `finish`; with none left to move, it runs at once. With `place`, the starts and targets
    /// are in strip coordinates and `place` puts them on screen on every frame; a window that was moving without it,
    /// or with it, starts over from `starts`. `resting` has where the strip's windows are on screen now, so one that
    /// does not glide is moved as soon as `place` puts it elsewhere. A window in `slower` takes that many times as
    /// long as `stretch` has the others take. A window in `anchors` grows to the left as it glides, its right edge held
    /// past the screen's; one that did so before and no longer does carries on from where it was written. A window in
    /// `restart` sets out from its start even if it is moving already, as one a strip's long scroll takes straight on
    /// out of view does (see ScrollShortcut.swift). `curve` is the tree's own in place of the configured one, till its
    /// next glide; a tree that followed fingers no longer does.
    func animate(_ key: UInt64, from starts: [WindowID: CGRect], to targets: [WindowID: CGRect],
                 pids: [WindowID: pid_t], place: (([WindowID: CGRect]) -> [WindowID: CGRect])? = nil,
                 resting: [WindowID: CGRect] = [:], stretch: Double = 1, slower: [WindowID: Double] = [:],
                 anchors: [WindowID: ResizeOnce.Anchor] = [:], restart: Set<WindowID> = [], curve: AnimationCurve? = nil,
                 sink: (([WindowID: CGRect]) -> Void)? = nil, then finish: @escaping () -> Void) {
        // A new glide: every app gets another chance to keep up.
        if entries.isEmpty { clearSlow() } else if !entries.values.contains(where: { $0.key == key }) { settleRecovered() }
        // Windows setting off now: their first size is no step an app is slow to follow.
        let gliding = Set(entries.keys)
        defer { applier.startRun(entries.keys.filter { !gliding.contains($0) }) }
        following.remove(key)
        // What each moving window glided on till now, so one whose curve changes can start over on the new one.
        let before = curves
        curves[key] = curve
        windowPids.merge(pids) { $1 }
        let wasPlaced = placers[key] != nil
        let still = Dictionary(uniqueKeysWithValues: resting.compactMap { id, frame in pids[id].map { (id, ($0, frame)) } })
        placers[key] = place.map { (targets, $0, still) }
        sinks[key] = sink
        for (id, entry) in entries where entry.key == key
            && (targets[id] == nil || wasPlaced != (place != nil) || restart.contains(id)) {
            entries[id] = nil
            written[id] = nil
        }
        for (id, target) in targets {
            waitingSince[id] = nil
            if entries[id] != nil {
                let was = (before[entries[id]!.key] ?? self.curve).stretched(entries[id]!.stretch)
                if entries[id]!.anchor != nil, anchors[id] == nil { entries[id]!.animation.carryOn(from: entries[id]!.frame) }
                if entries[id]!.anchor == nil, anchors[id] != nil { entries[id]!.heldSince = CACurrentMediaTime() }
                if anchors[id] == nil { entries[id]!.heldSince = nil }
                entries[id]!.animation.retarget(target)
                entries[id]!.key = key
                entries[id]!.stretch = stretch * (slower[id] ?? 1)
                entries[id]!.anchor = anchors[id]
                // Another curve, its target the same or not: an easing over from here, as a retarget starts one, and a
                // spring after an easing from rest, since an easing keeps no speed. A spring after a spring keeps its own.
                let now = (curve ?? self.curve).stretched(entries[id]!.stretch)
                if was != now, case .eased = now {
                    entries[id]!.animation.restart()
                } else if case .eased = was, case .spring = now {
                    entries[id]!.animation.restart()
                }
            } else if let start = starts[id], let pid = pids[id], !isResting(id, at: start, for: target) {
                entries[id] = Entry(animation: FrameAnimation(from: start, to: target), pid: pid, key: key,
                                    stretch: stretch * (slower[id] ?? 1), anchor: anchors[id],
                                    heldSince: anchors[id] == nil ? nil : CACurrentMediaTime())
            }
        }
        // The link steps on the display of the tree last set gliding, not of one that had nothing to move.
        if entries.values.contains(where: { $0.key == key }) { lastKey = key }
        finishes[key] = finish
        finishArrived()
        if !entries.isEmpty { run() }
    }

    /// Has the tree's windows follow `targets` closely, on a stiff spring, as fingers move a strip: called again with
    /// each move, they bend towards the new targets keeping their speed, and they never arrive, however still they
    /// hold, until `endFollow`. A window not moving yet sets out from its start. As with `animate`, `place` puts strip
    /// frames on screen and `sink` takes the frames instead of the windows. The rest of the tree's last pass, to have
    /// run once its windows arrived, is dropped: the pass after the fingers lift runs its own.
    func follow(_ key: UInt64, from starts: [WindowID: CGRect], to targets: [WindowID: CGRect], pids: [WindowID: pid_t],
                place: (([WindowID: CGRect]) -> [WindowID: CGRect])? = nil, sink: (([WindowID: CGRect]) -> Void)? = nil) {
        if entries.isEmpty { clearSlow() } else if !entries.values.contains(where: { $0.key == key }) { settleRecovered() }
        let gliding = Set(entries.keys)
        defer { applier.startRun(entries.keys.filter { !gliding.contains($0) }) }
        windowPids.merge(pids) { $1 }
        if following.insert(key).inserted { finishes[key] = nil }
        let before = curves
        curves[key] = Self.followCurve
        // Every window of the strip follows, so none rests meanwhile.
        let resting: [WindowID: (pid: pid_t, frame: CGRect)] = [:]
        placers[key] = place.map { (targets, $0, resting) }
        sinks[key] = sink
        for (id, entry) in entries where entry.key == key && targets[id] == nil {
            entries[id] = nil
            written[id] = nil
        }
        for (id, target) in targets {
            waitingSince[id] = nil
            if entries[id] != nil {
                // Coming off an easing, which keeps no speed: the stiff spring sets out from rest.
                if case .eased = (before[entries[id]!.key] ?? curve) { entries[id]!.animation.restart() }
                if entries[id]!.anchor != nil { entries[id]!.animation.carryOn(from: entries[id]!.frame) }
                entries[id]!.anchor = nil
                entries[id]!.heldSince = nil
                entries[id]!.stretch = 1
                entries[id]!.key = key
                entries[id]!.animation.retarget(target)
            } else if let start = starts[id], let pid = pids[id] {
                entries[id] = Entry(animation: FrameAnimation(from: start, to: target), pid: pid, key: key)
            }
        }
        if entries.values.contains(where: { $0.key == key }) { lastKey = key }
        if !entries.isEmpty { run() }
    }

    /// Lets the tree's windows arrive again, as the pass after the fingers lift glides them on.
    func endFollow(_ key: UInt64) { following.remove(key) }

    /// Whether a window at `frame` is where it came to rest when last asked for `asked`, or on it: not moved since by
    /// its app or the user. An app that snaps to a grid or keeps a minimum size rests a few points off.
    func rests(_ id: WindowID, at frame: CGRect, askedFor asked: CGRect) -> Bool {
        isResting(id, at: frame, for: asked)
    }

    /// Whether a window at `start` is as close to `target` as it gets: on it, or where it came to rest when last asked for it.
    private func isResting(_ id: WindowID, at start: CGRect, for target: CGRect) -> Bool {
        if start.isClose(to: target, within: 1) { return true }
        guard let landed = landed[id], landed.asked == target else { return false }
        return start.isClose(to: landed.got, within: 1)
    }

    /// Note where written windows came to rest.
    func noteLanded(_ results: [FrameResult]) {
        for result in results { landed[result.job.id] = result.got.map { (result.job.frame, $0) } }
    }

    /// Stops the tree's windows where they are, without finishing its pass.
    func stop(_ key: UInt64) {
        for (id, entry) in entries where entry.key == key {
            entries[id] = nil
            written[id] = nil
            waitingSince[id] = nil
        }
        finishes[key] = nil
        placers[key] = nil
        sinks[key] = nil
        curves[key] = nil
        following.remove(key)
    }

    /// Forgets a window that is gone, so a new window given its id starts fresh.
    func forget(_ id: WindowID) {
        entries[id] = nil
        landed[id] = nil
        written[id] = nil
        waitingSince[id] = nil
        windowPids[id] = nil
    }

    /// Stops every animation where it is. Nothing is finished.
    func cancel() {
        entries = [:]
        finishes = [:]
        placers = [:]
        sinks = [:]
        curves = [:]
        following = []
        written = [:]
        waitingSince = [:]
        link?.isPaused = true
        lastTarget = nil
        pace = nil
        endActivity()
        watchdog?.invalidate()
        watchdog = nil
    }

    private func run() {
        // On the fastest display of the trees gliding, the one it is on if that is as fast, else the tree last set
        // gliding's; made again once that is another, the main one while unknown. Chosen once a turn of the main queue,
        // as every move of the fingers calls this, and again when the trees gliding are others.
        let keys = Set(entries.values.map(\.key))
        if choice?.keys != keys {
            let wasChosen = choice != nil
            let candidates = Set(keys.compactMap(displayOf)).map { id in
                (id: id, rate: Double(screen(of: id)?.maximumFramesPerSecond ?? 60))
            }
            let last = lastKey.flatMap(displayOf)
            choice = (keys, LinkChoice.display(current: linkDisplay, preferred: last, among: candidates) ?? last)
            if !wasChosen { DispatchQueue.main.async { [weak self] in self?.choice = nil } }
        }
        let display = choice?.display
        let fresh = link == nil || (display != nil && display != linkDisplay)
        if fresh { makeLink(on: display) }
        // Called again with every move of the fingers: only a link setting off starts the clocks again, so one that
        // stops firing is still noticed (`checkStalled`).
        if fresh || link?.isPaused == true {
            link?.isPaused = false
            lastStepAt = CACurrentMediaTime()
            pace = (lastStepAt, 0, 0, nil, 0)
        }
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                             reason: "Gliding windows")
        }
        if watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkStalled() }
        }
    }

    /// A link on `display`'s screen, or the main one, at its full rate: snapshots and real windows alike, an app that
    /// cannot keep up moved every third step instead (see `step`), so it glides at its own pace rather than dragging
    /// the rate down. Logged, as the pace glides go at.
    private func makeLink(on display: CGDirectDisplayID?) {
        link?.invalidate()
        lastTarget = nil
        let own = display.flatMap { screen(of: $0) }
        let shown = own ?? NSScreen.main ?? NSScreen.screens.first
        linkDisplay = display
        link = shown?.displayLink(target: self, selector: #selector(tick))
        let rate = Float(max(shown?.maximumFramesPerSecond ?? 60, 1))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(rate, 60), maximum: rate, preferred: rate)
        link?.add(to: .main, forMode: .common)
        if link != nil {
            print("\(stamp()) animator: \(Int(rate)) frames a second on \(shown?.localizedName ?? "no screen")")
            fflush(stdout)
        }
    }

    /// App Nap may come back once nothing glides.
    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    /// Drops the link, so the next pass makes one for the screens there are now, and carries on with a pass in flight.
    private func screensChanged() {
        dropLink()
        if entries.isEmpty { idle() } else { run() }
    }

    /// A link that has not fired for a while (its screen went away without a screen change reaching us) would
    /// leave windows mid-glide for good: put them on their tiles now and start over with a new link next time.
    private func checkStalled() {
        // Emptied by `stop` or `forget` with no tick to follow, as after a dropped link.
        guard !entries.isEmpty else { return idle() }
        guard CACurrentMediaTime() - lastStepAt > 2 else { return }
        dropLink()
        step(dt: timeout)
    }

    /// Nothing glides: the link paused, its pace logged, App Nap allowed again, the watchdog stopped.
    private func idle() {
        link?.isPaused = true
        lastTarget = nil
        if let pace, pace.frames > 0 {
            let seconds = lastStepAt - pace.since
            print("\(stamp()) animator: \(pace.frames) frames in \(Int((seconds * 1000).rounded())) ms, "
                  + "\(Int((Double(pace.frames) / max(seconds, 0.001)).rounded())) a second, "
                  + "the longest wait \(String(format: "%.1f", pace.longest * 1000)) ms"
                  + (pace.longestAt.map { " at \(stamp($0))" } ?? "")
                  + ", the slowest placing \(String(format: "%.1f", pace.slowestCall * 1000)) ms")
            fflush(stdout)
        }
        pace = nil
        endActivity()
        watchdog?.invalidate()
        watchdog = nil
    }

    private func dropLink() {
        link?.invalidate()
        link = nil
        linkDisplay = nil
        lastTarget = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Each step goes as far as when its frame will show, a frame after the last at the display's rate, or more
        // after a frame missed. A stalled clock (sleep, a busy main thread) resumes where it was rather than leaping
        // ahead.
        let gap = lastTarget.map { link.targetTimestamp - $0 } ?? link.duration
        lastTarget = link.targetTimestamp
        if var counted = pace {
            counted.frames += 1
            if gap > counted.longest { (counted.longest, counted.longestAt) = (gap, Date()) }
            pace = counted
        }
        step(dt: min(max(gap, 0), 1.0 / 30))
    }

    /// `work`, timed for the pace line: the longest a tree's placer or sink took over a frame.
    private func timed<T>(_ work: () -> T) -> T {
        let began = CACurrentMediaTime()
        let result = work()
        if pace != nil { pace!.slowestCall = max(pace!.slowestCall, CACurrentMediaTime() - began) }
        return result
    }

    /// Advances every window by `dt` seconds and writes the frames; `dt` of `timeout` or more lands them all.
    private func step(dt: Double) {
        lastStepAt = CACurrentMediaTime()
        var frames: [WindowID: CGRect] = [:], arrived: [WindowID] = [], done: Set<WindowID> = []
        let moving = entries
        for id in moving.keys {
            // Standing at its start until its lead-in is written, or for long enough that the app has not answered.
            if let since = entries[id]!.heldSince, lastStepAt - since < Self.leadInWait {
                frames[id] = entries[id]!.frame
                continue
            }
            entries[id]!.heldSince = nil
            let stretch = entries[id]!.stretch, key = entries[id]!.key
            let along = (curves[key] ?? curve).stretched(stretch)
            let finished = entries[id]!.animation.step(along, dt: dt, timeout: timeout * stretch)
            frames[id] = entries[id]!.frame
            // A window following fingers holds there, at its target, however long.
            if finished, !following.contains(key) { done.insert(id) }
        }
        for entry in moving.values where applier.isSlow(entry.pid) { slowPids.insert(entry.pid) }
        // An app that has kept up again is followed frame by frame again, but its column holds to it till the glide
        // ends, rather than coming apart mid-glide; unless it falls behind again meanwhile.
        recovered.formUnion(applier.takeRecovered())
        recovered = recovered.filter { !applier.isSlow($0) }
        // A tree gliding something else takes its frames, and its windows are left alone.
        for (key, sink) in sinks {
            let ours = frames.filter { moving[$0.key]?.key == key }
            frames = frames.filter { moving[$0.key]?.key != key }
            if !ours.isEmpty { timed { sink(ours) } }
        }
        // A strip's windows go on screen together, each tree's resting ones where they rest, and each column's quick
        // windows where its slow one shows.
        var restingJobs: [FrameJob] = [], held: Set<WindowID> = []
        for (key, placer) in placers {
            let ours = frames.filter { moving[$0.key]?.key == key }
            guard !ours.isEmpty else { continue }
            var placed = timed { placer.place(placer.base.merging(ours) { $1 }) }
            let slow = Set(placed.keys.filter { windowPids[$0].map(slowPids.contains) ?? false })
            // No slow window, no column to hold: nothing to read.
            if !slow.isEmpty {
                let hold = ColumnHold.held(placed, columns: columns(key), slow: slow) { serverFrame($0) }
                placed.merge(hold.frames) { $1 }
                held.formUnion(hold.held)
            }
            for id in ours.keys { frames[id] = placed[id] ?? frames[id] }
            for (id, still) in placer.resting where moving[id] == nil {
                guard let frame = placed[id], frame != still.frame, !applier.isSlow(still.pid) || stepCount % 3 == 2 else { continue }
                placers[key]!.resting[id]!.frame = frame
                restingJobs.append(FrameJob(pid: still.pid, id: id, frame: frame))
            }
        }
        // A window at its target arrives, unless it is held for the slow window of its column, for a while at most.
        for id in done {
            if held.contains(id) {
                let since = waitingSince[id] ?? lastStepAt
                waitingSince[id] = since
                if lastStepAt - since < Self.columnWait { continue }
            }
            waitingSince[id] = nil
            entries[id] = nil
            arrived.append(id)
        }
        stepCount &+= 1
        var jobs = restingJobs
        for (id, frame) in frames where written[id] != frame {
            let pid = moving[id]!.pid
            // A slow app keeps gliding at a third of the rate rather than freezing for the rest of the glide, and is
            // written its target when it gets there, which the quick windows of its column wait for.
            if applier.isSlow(pid), stepCount % 3 != 0, !done.contains(id) { continue }
            written[id] = frame
            jobs.append(FrameJob(pid: pid, id: id, frame: frame, leadEdge: moving[id]!.anchor?.edge))
        }
        for id in arrived { written[id] = nil }
        applier.step(jobs)
        if !arrived.isEmpty { onArrive(arrived) }
        finishArrived()
        if entries.isEmpty { idle() }
    }

    /// Finish every tree none of whose windows is still moving.
    private func finishArrived() {
        let moving = Set(entries.values.map(\.key))
        for (key, finish) in finishes where !moving.contains(key) {
            finishes[key] = nil
            placers[key] = nil
            sinks[key] = nil
            finish()
        }
    }
}
