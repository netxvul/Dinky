import AppKit
import DinkyLayout

// Glides windows to their tiles. Each window rides a spring, or an easing over a fixed time, from where it is to its
// tile, stepped on every frame of the main display and written through the applier's per-app queues without
// readback. Once a tree's windows have arrived, its pass finishes as an unanimated one would: the full write with
// readback, retry and raises. A new pass mid-flight retargets the windows: on the spring they curve to their new
// tiles, keeping their speed; an easing starts over from where they are. A scrolling strip glides as a whole: its
// windows ride in strip coordinates, unparked, and each frame the tree's `place` puts them all on screen together,
// so a long scroll passes the columns between across the screen in turn.
//
// Frames are stepped and written at the display's rate (120 a second on a ProMotion display). Each app moves its own
// windows; one that takes longer than `FrameScheduler.slowStep` over a step is then moved only every third frame
// rather than dropped for the rest of the glide, so it keeps gliding at a pace it can hold instead of freezing and
// jumping to its tile at the end; frames coalesce per window in the scheduler, so a throttled app never has a backlog
// to leap through.
//
// A tree can glide something other than its windows instead, such as snapshots of them (see GlideStage): its frames go
// to its `sink` and nowhere else, at the display's full rate, since no app has to keep up. Main thread only.
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
    private var lastTick: CFTimeInterval?
    /// When a frame was last stepped, on the wall clock, so a display link that stopped firing is noticed.
    private var lastStepAt = CACurrentMediaTime()
    private var watchdog: Timer?
    private var curve = AnimationCurve.spring(Spring(response: 0.15, damping: 0.9))
    /// How long a window growing to the left stands at its start at most, waiting for its lead-in to be written.
    private static let leadInWait: CFTimeInterval = 0.25
    private var timeout = 1.0
    /// Where windows came to rest the last time they were written unanimated, by the frame they were asked for.
    /// An app that snaps to a grid (Terminal) or keeps a minimum size never reaches its tile exactly, and
    /// must not be sent gliding towards it on every pass.
    private var landed: [WindowID: (asked: CGRect, got: CGRect)] = [:]
    /// Called with the windows that just arrived.
    var onArrive: ([WindowID]) -> Void = { _ in }

    init(applier: FrameApplier) {
        self.applier = applier
        super.init()
        applier.onLeadStep = { [weak self] id in DispatchQueue.main.async { self?.entries[id]?.heldSince = nil } }
        // The link is made for one screen; with that screen gone it never fires again.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.screensChanged() }
    }

    /// How long a window takes to arrive, roughly on the spring and exactly along an easing; nil for the spring.
    func configure(durationMs ms: Int, easing: Easing?) {
        let duration = Double(ms) / 1000
        curve = easing.map { .eased($0, duration: duration) } ?? .spring(Spring(response: duration, damping: 0.9))
        timeout = max(1, 4 * duration)
    }

    /// Whether dinky is moving the window right now, so its frame changes are not the user's.
    func isAnimating(_ id: WindowID) -> Bool { entries[id] != nil }

    /// The windows moving now.
    var animating: [WindowID] { Array(entries.keys) }

    /// Where a gliding window's steps write it now; nil for one not gliding.
    func frame(of id: WindowID) -> CGRect? { entries[id]?.frame }

    /// Move the tree's windows from `starts` to `targets`, then run `finish`. Windows already there, or with
    /// no start, are left to `finish`; with none left to move, it runs at once. With `place`, the starts and targets
    /// are in strip coordinates and `place` puts them on screen on every frame; a window that was moving without it,
    /// or with it, starts over from `starts`. `resting` has where the strip's windows are on screen now, so one that
    /// does not glide is moved as soon as `place` puts it elsewhere. A window in `slower` takes that many times as
    /// long as `stretch` has the others take. A window in `anchors` grows to the left as it glides, its right edge held
    /// past the screen's; one that did so before and no longer does carries on from where it was written.
    func animate(_ key: UInt64, from starts: [WindowID: CGRect], to targets: [WindowID: CGRect],
                 pids: [WindowID: pid_t], place: (([WindowID: CGRect]) -> [WindowID: CGRect])? = nil,
                 resting: [WindowID: CGRect] = [:], stretch: Double = 1, slower: [WindowID: Double] = [:],
                 anchors: [WindowID: ResizeOnce.Anchor] = [:], sink: (([WindowID: CGRect]) -> Void)? = nil,
                 then finish: @escaping () -> Void) {
        // A new glide: every app gets another chance to keep up.
        if entries.isEmpty { applier.clearSlow() }
        let wasPlaced = placers[key] != nil
        let still = Dictionary(uniqueKeysWithValues: resting.compactMap { id, frame in pids[id].map { (id, ($0, frame)) } })
        placers[key] = place.map { (targets, $0, still) }
        sinks[key] = sink
        for (id, entry) in entries where entry.key == key && (targets[id] == nil || wasPlaced != (place != nil)) {
            entries[id] = nil
            written[id] = nil
        }
        for (id, target) in targets {
            if entries[id] != nil {
                if entries[id]!.anchor != nil, anchors[id] == nil { entries[id]!.animation.carryOn(from: entries[id]!.frame) }
                if entries[id]!.anchor == nil, anchors[id] != nil { entries[id]!.heldSince = CACurrentMediaTime() }
                if anchors[id] == nil { entries[id]!.heldSince = nil }
                entries[id]!.animation.retarget(target)
                entries[id]!.key = key
                entries[id]!.stretch = stretch * (slower[id] ?? 1)
                entries[id]!.anchor = anchors[id]
            } else if let start = starts[id], let pid = pids[id], !isResting(id, at: start, for: target) {
                entries[id] = Entry(animation: FrameAnimation(from: start, to: target), pid: pid, key: key,
                                    stretch: stretch * (slower[id] ?? 1), anchor: anchors[id],
                                    heldSince: anchors[id] == nil ? nil : CACurrentMediaTime())
            }
        }
        finishes[key] = finish
        finishArrived()
        if !entries.isEmpty { run() }
    }

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
        }
        finishes[key] = nil
        placers[key] = nil
        sinks[key] = nil
    }

    /// Forgets a window that is gone, so a new window given its id starts fresh.
    func forget(_ id: WindowID) {
        entries[id] = nil
        landed[id] = nil
        written[id] = nil
    }

    /// Stops every animation where it is. Nothing is finished.
    func cancel() {
        entries = [:]
        finishes = [:]
        placers = [:]
        sinks = [:]
        written = [:]
        link?.isPaused = true
        lastTick = nil
        watchdog?.invalidate()
        watchdog = nil
    }

    private func run() {
        if link == nil {
            link = (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        // Aim for the display's full rate, snapshots and real windows alike; an app that cannot keep up is moved
        // every third step instead (see `step`), so it glides at its own pace rather than dragging the rate down.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link?.isPaused = false
        lastStepAt = CACurrentMediaTime()
        if watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkStalled() }
        }
    }

    /// Drops the link, so the next pass makes one for the screen that is main now, and carries on with a pass in flight.
    private func screensChanged() {
        dropLink()
        if !entries.isEmpty { run() }
    }

    /// A link that has not fired for a while (its screen went away without a screen change reaching us) would
    /// leave windows mid-glide for good: put them on their tiles now and start over with a new link next time.
    private func checkStalled() {
        guard !entries.isEmpty, CACurrentMediaTime() - lastStepAt > 2 else { return }
        dropLink()
        step(dt: timeout)
    }

    private func dropLink() {
        link?.invalidate()
        link = nil
        lastTick = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // A stalled clock (sleep, a busy main thread) resumes where it was rather than leaping ahead.
        let dt = min(lastTick.map { link.timestamp - $0 } ?? link.duration, 1.0 / 30)
        lastTick = link.timestamp
        step(dt: dt)
    }

    /// Advances every window by `dt` seconds and writes the frames; `dt` of `timeout` or more lands them all.
    private func step(dt: Double) {
        lastStepAt = CACurrentMediaTime()
        var frames: [WindowID: CGRect] = [:], arrived: [WindowID] = []
        let moving = entries
        for id in moving.keys {
            // Standing at its start until its lead-in is written, or for long enough that the app has not answered.
            if let since = entries[id]!.heldSince, lastStepAt - since < Self.leadInWait {
                frames[id] = entries[id]!.frame
                continue
            }
            entries[id]!.heldSince = nil
            let stretch = entries[id]!.stretch
            let done = entries[id]!.animation.step(curve.stretched(stretch), dt: dt, timeout: timeout * stretch)
            frames[id] = entries[id]!.frame
            if done { entries[id] = nil; arrived.append(id) }
        }
        // A tree gliding something else takes its frames, and its windows are left alone.
        for (key, sink) in sinks {
            let ours = frames.filter { moving[$0.key]?.key == key }
            frames = frames.filter { moving[$0.key]?.key != key }
            if !ours.isEmpty { sink(ours) }
        }
        // A strip's windows go on screen together, each tree's resting ones where they rest.
        var restingJobs: [FrameJob] = []
        for (key, placer) in placers {
            let ours = frames.filter { moving[$0.key]?.key == key }
            guard !ours.isEmpty else { continue }
            let placed = placer.place(placer.base.merging(ours) { $1 })
            for id in ours.keys { frames[id] = placed[id] ?? frames[id] }
            for (id, still) in placer.resting where moving[id] == nil {
                guard let frame = placed[id], frame != still.frame, !applier.isSlow(still.pid) || stepCount % 3 == 2 else { continue }
                placers[key]!.resting[id]!.frame = frame
                restingJobs.append(FrameJob(pid: still.pid, id: id, frame: frame))
            }
        }
        stepCount &+= 1
        var jobs = restingJobs
        for (id, frame) in frames where written[id] != frame {
            let pid = moving[id]!.pid
            // A slow app keeps gliding at a third of the rate rather than freezing for the rest of the glide.
            if applier.isSlow(pid), stepCount % 3 != 0 { continue }
            written[id] = frame
            jobs.append(FrameJob(pid: pid, id: id, frame: frame, leadEdge: moving[id]!.anchor?.edge))
        }
        for id in arrived { written[id] = nil }
        applier.step(jobs)
        if !arrived.isEmpty { onArrive(arrived) }
        finishArrived()
        if entries.isEmpty {
            link?.isPaused = true
            lastTick = nil
            watchdog?.invalidate()
            watchdog = nil
        }
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
