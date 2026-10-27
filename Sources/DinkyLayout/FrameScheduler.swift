import CoreGraphics
import Foundation

/// A frame to write: a window, the process that owns it and where it should go (top-left origin).
public struct FrameJob: Equatable, Sendable {
    public var pid: Int32
    public var id: WindowID
    public var frame: CGRect
    /// For an animation step of a window growing to the left, the screen's right edge, which the window is taken just
    /// past from where it is before the first of a run of steps carrying it, once, so no step's size stops there. See
    /// `ResizeOnce.leadIn(from:edge:)`.
    public var leadEdge: CGFloat?

    public init(pid: Int32, id: WindowID, frame: CGRect, leadEdge: CGFloat? = nil) {
        self.pid = pid
        self.id = id
        self.frame = frame
        self.leadEdge = leadEdge
    }
}

/// What reading a window's frame came to.
public enum FrameRead: Equatable, Sendable {
    case frame(CGRect)
    /// The app did not answer in time: it is busy, and nothing is known about the window.
    case busy
    /// The window cannot be read: it is no longer among its app's windows, its element is no longer valid,
    /// or the app will not give its frame.
    case gone
}

/// What a window ended up at after a write.
public struct FrameResult: Equatable, Sendable {
    public var job: FrameJob
    /// Where the window was asked to go: the job's frame grown to the window's recorded minimum size.
    public var target: CGRect
    /// The frame read back, nil when the window could not be read.
    public var got: CGRect?
    /// False when the window was already in place and nothing was written.
    public var written = false
    /// True when the first write landed elsewhere and it was written once more.
    public var retried = false
    /// The app did not answer in time, or was still busy from an earlier pass and was left alone: nothing is known
    /// about the window. Its frame is written once the app answers again.
    public var busy = false
    /// The window could not be read: its element is gone. See `FrameRead.gone`.
    public var gone = false

    /// Landed within 2 pt of the target on every edge.
    public var matched: Bool { got.map { $0.isClose(to: target, within: 2) } ?? false }
}

/// Schedules frame writes: one serial queue per process so a slow app only stalls itself,
/// the newest frame per window wins, and a window that refuses its frame is written at most twice.
/// Animation steps take a lighter path on the same queues: written once, not read back, and only moved
/// when their size is the one last written. An app that does not answer in time is left alone for a while (see
/// `isBusy`), so messages do not pile up in a hung app for it to work through once it wakes. The actual reads and
/// writes are injected, so this is testable without Accessibility.
public final class FrameScheduler: @unchecked Sendable {
    public typealias Completion = ([FrameResult]) -> Void

    private let settle: TimeInterval
    private let backoff: TimeInterval
    private let prepare: (Int32) -> Void
    private let read: (FrameJob) -> FrameRead
    private let write: (FrameJob) -> Bool
    private let move: (FrameJob) -> Bool
    private let learns: (CGRect) -> Bool

    /// Seconds an app may take to move its windows for one animation step before it counts as slow.
    public static let slowStep: TimeInterval = 0.05

    private let lock = NSLock()
    /// Processes that took longer than `slowStep` over an animation step since `clearSlow`.
    private var slow: Set<Int32> = []
    /// Processes found slow that have since moved their windows in time for `recoveredAfter` steps running, till
    /// `takeRecovered` hands them on.
    private var quickAgain: Set<Int32> = []
    /// How many animation steps in a row a slow process must keep up with to count as slow no longer.
    public static let recoveredAfter = 6
    /// Windows whose glide or held drag just set off (`startRun`): their next size is the app laying them out again.
    private var runStarts: Set<WindowID> = []
    private var apps: [Int32: App] = [:]
    private var minimums: [WindowID: CGSize] = [:]
    /// Refusals seen once, by window, with the window's process: a minimum only when a later pass sees the same one.
    private var candidates: [WindowID: (size: CGSize, pid: Int32)] = [:]
    /// Bumped by `cancel`; writes queued under an older generation are dropped.
    private var generation = 0

    /// `prepare` runs once per process before its first write; `read`, `write` and `move` (position only)
    /// run on that process's queue. `write` and `move` return false when the app did not answer in time.
    /// A process that does not answer is first left alone for `backoff` seconds, doubling up to eight times that.
    /// Only a window asked for a frame `learns` accepts teaches a minimum size (see `recordMinimum`).
    public init(settle: TimeInterval = 0.1, backoff: TimeInterval = 1, prepare: @escaping (Int32) -> Void = { _ in },
                read: @escaping (FrameJob) -> FrameRead, write: @escaping (FrameJob) -> Bool,
                move: ((FrameJob) -> Bool)? = nil, learns: @escaping (CGRect) -> Bool = { _ in true }) {
        self.settle = settle
        self.backoff = backoff
        self.prepare = prepare
        self.read = read
        self.write = write
        self.move = move ?? write
        self.learns = learns
    }

    /// Sizes windows refused to go below, seen the same on two passes. Only dimensions that were refused are set.
    public var minimumSizes: [WindowID: CGSize] { lock.withLock { minimums } }

    /// Windows that refused a size once and wait for a second pass to tell a minimum from an app catching up.
    /// Windows of a busy process are left out: a pass now would only hold their frames, not confirm anything,
    /// and the pass that writes them once it answers settles the refusal.
    public var unconfirmedMinimums: Set<WindowID> {
        lock.withLock { Set(candidates.filter { (apps[$0.value.pid]?.backoff ?? 0) == 0 }.keys) }
    }

    /// Queue frames. `completion` gets the results of every process queue these jobs went to,
    /// once each has written them (or newer frames for the same windows). `ignoringBusy` writes them even to a
    /// process that is not answering, as putting windows back on quit must: there is no later to hold them for.
    public func submit(_ jobs: [FrameJob], ignoringBusy: Bool = false, completion: Completion? = nil) {
        let byPid = Dictionary(grouping: jobs, by: \.pid)
        guard !byPid.isEmpty else { completion?([]); return }
        let batch = Batch(waiting: byPid.count, completion)
        lock.withLock {
            for (pid, jobs) in byPid {
                let app = app(pid)
                for job in jobs {
                    if let i = app.pending.firstIndex(where: { $0.id == job.id }) { app.pending[i] = job } else { app.pending.append(job) }
                }
                app.batches.append(batch)
                if ignoringBusy { app.forced = true }
                schedule(app)
            }
        }
    }

    /// Called on a process's queue when it answers again after a busy spell, once the frames held through it are
    /// queued: they are written as a pass of their own, which reports to no completion, so whoever lays windows out
    /// can lay that process's windows out again.
    public var onRecovered: ((Int32) -> Void)? {
        get { lock.withLock { recovered } }
        set { lock.withLock { recovered = newValue } }
    }
    private var recovered: ((Int32) -> Void)?

    /// Called on a process's queue once an animation step of a window growing to the left is written, with its lead-in
    /// if it needed one: whoever glides the window can set it off then, rather than have it stand while the lead-in is
    /// written and then jump.
    public var onLeadStep: ((WindowID) -> Void)? {
        get { lock.withLock { leadStep } }
        set { lock.withLock { leadStep = newValue } }
    }
    private var leadStep: ((WindowID) -> Void)?

    /// Queue animation steps: each replaces any step of the same window not written yet, and is written once
    /// without reading back. A step whose size is the one last written for its window only moves it. Steps for a
    /// busy process are dropped: by the time it answers they are long out of date.
    public func step(_ jobs: [FrameJob]) {
        lock.withLock {
            for job in jobs {
                let app = app(job.pid)
                guard app.backoff == 0 else { continue }
                if let i = app.steps.firstIndex(where: { $0.id == job.id }) { app.steps[i] = job } else { app.steps.append(job) }
                schedule(app)
            }
        }
    }

    /// The process's queue, made on first use. Under the lock.
    private func app(_ pid: Int32) -> App {
        if let app = apps[pid] { return app }
        let app = App(pid)
        apps[pid] = app
        return app
    }

    /// Whether the process took longer than `slowStep` to move its windows for an animation step since `clearSlow`:
    /// following it frame by frame would only show it stalling and jumping.
    public func isSlow(_ pid: Int32) -> Bool { lock.withLock { slow.contains(pid) } }

    /// The processes no longer slow since this was last asked (see `recoveredAfter`), forgetting them.
    public func takeRecovered() -> Set<Int32> {
        lock.withLock {
            defer { quickAgain = [] }
            return quickAgain
        }
    }

    /// Forgets which processes were slow, as a new glide starts.
    public func clearSlow() { lock.withLock { slow = [] } }

    /// The glides or held drags of `ids` set off: the first size each is stepped to is left out of the slow measure,
    /// whatever sizes earlier steps left behind.
    public func startRun(_ ids: [WindowID]) { lock.withLock { runStarts.formUnion(ids) } }

    /// Whether the process stopped answering and is being left alone: steps for it are dropped, and its frames wait,
    /// newest per window, until a read gets an answer. That read comes after one backoff, then two, four, and eight
    /// from then on.
    public func isBusy(_ pid: Int32) -> Bool { lock.withLock { (apps[pid]?.backoff ?? 0) > 0 } }

    /// Takes `size` as the size last written for a window about to be stepped, its size now, so a first step that
    /// keeps it is a plain move: writing the size as well would make the app lay the window out again as it sets off.
    public func assume(_ size: CGSize, of id: WindowID, pid: Int32) {
        lock.withLock {
            let app = app(pid)
            app.queue.async { app.written[id] = size }
        }
    }

    /// Drain the process's queue unless a drain is already on its way. Under the lock.
    private func schedule(_ app: App) {
        guard !app.scheduled else { return }
        app.scheduled = true
        app.queue.async { self.drain(app) }
    }

    /// Forgets a window that is gone: its minimum size, any refusal waiting to be confirmed, and what steps wrote.
    /// Window ids are reused, so a new window must not inherit them.
    public func forget(_ id: WindowID) {
        lock.withLock {
            minimums[id] = nil
            candidates[id] = nil
            for app in apps.values { app.held.removeAll { $0.id == id } }
            // What steps wrote is the queue's alone, so it is cleared there, after anything already queued.
            for app in apps.values {
                app.queue.async {
                    app.written[id] = nil; app.stepSizes[id] = nil; app.ledIn[id] = nil; app.slack[id] = nil; app.probes[id] = nil
                }
            }
        }
    }

    /// Lowers a window's minimum size to `size` in each dimension it is more than 2 pt bigger in: the window has been
    /// seen at that size, which it would not go to were its minimum right. False when it has none bigger.
    @discardableResult
    public func lowerMinimum(of id: WindowID, to size: CGSize) -> Bool {
        lock.withLock { lower(id, to: size) }
    }

    /// `lowerMinimum`, under the lock.
    private func lower(_ id: WindowID, to size: CGSize) -> Bool {
        guard let minimum = minimums[id] else { return false }
        let lowered = minimum.lowered(to: size)
        guard lowered != minimum else { return false }
        minimums[id] = lowered == .zero ? nil : lowered
        return true
    }

    /// Forgets every minimum size and refusal, so windows are asked for their tiles again.
    public func forgetMinimums() {
        lock.withLock { minimums = [:]; candidates = [:] }
    }

    /// Drops every frame not written yet, including a second try already under way. Completions still run,
    /// with the results of what was written.
    public func cancel() {
        lock.withLock {
            generation += 1
            for app in apps.values { app.pending = []; app.steps = []; app.held = [] }
        }
    }

    /// Take everything pending for one process and write it, steps first. Runs on the process's queue.
    /// While the process is busy nothing is sent to it: its frames are held and reported busy.
    private func drain(_ app: App) {
        let (steps, jobs, batches, needsPrepare, generation, busy) = lock.withLock {
            defer {
                app.steps = []; app.pending = []; app.batches = []; app.scheduled = false; app.prepared = true; app.forced = false
            }
            return (app.steps, app.pending, app.batches, !app.prepared, self.generation, app.backoff > 0 && !app.forced)
        }
        if busy { return hold(jobs, of: app, reporting: batches) }
        if needsPrepare { prepare(app.pid) }
        var began = Date()
        var stalled: FrameJob?
        for var job in steps {
            var answered = true
            // A run of steps growing a window to the left is led in before any step that carries it, so newer steps
            // replacing older ones cannot skip it, from where the window is then, and its first frames past the edge are
            // read back (see `probe`). Their time is not the steps': a resize once does not make an app too slow to follow.
            if let edge = job.leadEdge, app.ledIn[job.id] != edge {
                app.slack[job.id] = nil
                app.probes[job.id] = Self.snapProbes
                let leading = Date()
                answered = leadIn(job, past: edge, in: app)
                began += Date().timeIntervalSince(leading)
                if answered { app.ledIn[job.id] = edge }
            }
            if job.leadEdge == nil { app.ledIn[job.id] = nil; app.slack[job.id] = nil; app.probes[job.id] = nil }
            if let edge = job.leadEdge, job.frame.maxX > edge { job.frame.size.width += app.slack[job.id] ?? 0 }
            let runStart = lock.withLock { runStarts.remove(job.id) != nil }
            if answered {
                if app.written[job.id] == job.frame.size {
                    answered = move(job)
                } else {
                    // The first size of a run is the app laying the window out again, not keeping up with the steps:
                    // its time is left out of theirs. Sizes changing step after step are the steps, an app slow to
                    // follow them slow.
                    let first = runStart || (app.stepSizes[job.id]?.isEmpty ?? true)
                    let resizing = Date()
                    answered = write(job)
                    if first { began += Date().timeIntervalSince(resizing) }
                }
            }
            app.written[job.id] = job.frame.size
            app.stepSizes[job.id, default: []].insert(job.frame.size)
            if answered, let edge = job.leadEdge, job.frame.maxX > edge, app.probes[job.id, default: 0] > 0 {
                let probing = Date()
                answered = probe(job, asked: job.frame, past: edge, in: app)
                began += Date().timeIntervalSince(probing)
            }
            if job.leadEdge != nil { lock.withLock { leadStep }?(job.id) }
            if !answered { stalled = job; break }
        }
        if !steps.isEmpty {
            if Date().timeIntervalSince(began) > Self.slowStep {
                app.fastDrains = 0
                lock.withLock { _ = slow.insert(app.pid) }
            } else {
                app.fastDrains += 1
                // Quick again for a run of steps: no longer slow, whatever it was once, and once a run, a glide since
                // `clearSlow` having maybe found it slow before.
                if app.fastDrains == Self.recoveredAfter {
                    lock.withLock { slow.remove(app.pid); quickAgain.insert(app.pid) }
                }
            }
        }
        if let stalled {
            noteBusy(app, probe: stalled)
            return hold(jobs, of: app, reporting: batches)
        }
        let results = run(jobs, stepSizes: app.stepSizes) { self.lock.withLock { self.generation } == generation }
        for result in results {
            if result.written { app.written[result.job.id] = nil }
            if !result.busy { app.stepSizes[result.job.id] = nil }
            app.ledIn[result.job.id] = nil
            app.slack[result.job.id] = nil
            app.probes[result.job.id] = nil
        }
        // In place, or already where its minimum lets it be: whatever it refused before, it has caught up.
        lock.withLock {
            for result in results where !result.busy && (result.matched || !result.written) { candidates[result.job.id] = nil }
        }
        let unanswered = results.filter(\.busy).map(\.job)
        if let first = unanswered.first {
            noteBusy(app, probe: first)
            lock.withLock { keep(unanswered, in: app) }
        }
        for batch in batches { batch.report(results) }
    }

    /// How many frames of a run growing a window to the left are read back for a size its app snapped (see `probe`):
    /// any one width can happen to fit the app's grid.
    static let snapProbes = 3

    /// Takes the window of a step just past the screen edge `edge` from where it is (see `ResizeOnce.leadIn`), and reads
    /// it back. False when the app did not answer. Runs on the process's queue.
    private func leadIn(_ job: FrameJob, past edge: CGFloat, in app: App) -> Bool {
        let now: CGRect
        switch read(job) {
        case .busy: return false
        case .gone: return true
        case .frame(let frame): now = frame
        }
        guard let leadIn = ResizeOnce.leadIn(from: now, edge: edge) else { return true }
        guard write(FrameJob(pid: job.pid, id: job.id, frame: leadIn)) else { return false }
        app.written[job.id] = leadIn.size
        app.stepSizes[job.id, default: []].insert(leadIn.size)
        return probe(job, asked: leadIn, past: edge, in: app)
    }

    /// Reads back a window just written `asked`, past the screen edge `edge`, as one of the first frames of a run growing
    /// it to the left. An app that snaps its size to a grid leaves it narrower where asked, by up to a cell: its frames
    /// past the edge are written `ResizeOnce.snapSlack` wider from then on, so their sizes still leave it there, and one
    /// left on the screen, where AppKit would stop those sizes, is moved on past the edge. Not one further short or
    /// elsewhere, which is an app still taking the frame. False when the app did not answer. Runs on the process's queue.
    private func probe(_ job: FrameJob, asked: CGRect, past edge: CGFloat, in app: App) -> Bool {
        app.probes[job.id, default: 0] -= 1
        let got: CGRect
        switch read(job) {
        case .busy: return false
        case .gone: return true
        case .frame(let frame): got = frame
        }
        let short = asked.width - got.width
        guard short > 0.5, short <= ResizeOnce.snapSlack, abs(got.minX - asked.minX) <= 0.5 else { return true }
        app.slack[job.id] = ResizeOnce.snapSlack
        app.probes[job.id] = 0
        guard got.maxX < edge + 1 else { return true }
        return move(FrameJob(pid: job.pid, id: job.id, frame: got.offsetBy(dx: edge + ResizeOnce.nudge - got.maxX, dy: 0)))
    }

    /// Holds frames for a busy process, newest per window, and reports them busy and not written.
    private func hold(_ jobs: [FrameJob], of app: App, reporting batches: [Batch]) {
        let results = jobs.map { FrameResult(job: $0, target: reachable($0), busy: true) }
        lock.withLock { keep(jobs, in: app) }
        for batch in batches { batch.report(results) }
    }

    /// Adds frames to those held for a busy process, each replacing an older one for its window. Under the lock.
    private func keep(_ jobs: [FrameJob], in app: App) {
        for job in jobs {
            if let i = app.held.firstIndex(where: { $0.id == job.id }) { app.held[i] = job } else { app.held.append(job) }
        }
    }

    /// The process did not answer `job`: leave it alone for a backoff, then read `job`'s window to see if it answers.
    private func noteBusy(_ app: App, probe job: FrameJob) {
        let wait = lock.withLock {
            app.backoff = app.backoff == 0 ? backoff : min(app.backoff * 2, backoff * 8)
            app.probe = job
            return app.backoff
        }
        app.queue.asyncAfter(deadline: .now() + wait) { self.probe(app) }
    }

    /// One read after a backoff: an answer of any kind ends the busy spell and writes the frames held through it,
    /// once, as a pass of their own; no answer doubles the backoff. Runs on the process's queue.
    private func probe(_ app: App) {
        guard let job = lock.withLock({ app.probe }) else { return }
        if read(job) == .busy { return noteBusy(app, probe: job) }
        let recovered = lock.withLock {
            app.backoff = 0
            app.probe = nil
            // Anything queued since is newer than what was held.
            for job in app.held where !app.pending.contains(where: { $0.id == job.id }) { app.pending.append(job) }
            app.held = []
            if !app.pending.isEmpty { schedule(app) }
            return self.recovered
        }
        recovered?(app.pid)
    }

    /// Write, settle, read back; write the misses once more, settle, read back again. Writes only while `live`.
    /// A window already where its recorded minimum size lets it be is neither written nor retried. A window
    /// still at a size an animation step asked for is catching up, not refusing, so it shows no minimum.
    /// A window whose size is already right is only moved, one message instead of three; if the move does not
    /// land, the retry writes the whole frame. Once the app fails to answer, nothing more is sent to it: the
    /// remaining windows are reported busy.
    private func run(_ jobs: [FrameJob], stepSizes: [WindowID: Set<CGSize>], live: () -> Bool) -> [FrameResult] {
        var busy = false
        /// Reads a result's window into it, unless the app has stopped answering.
        func readBack(_ result: inout FrameResult) {
            result.got = nil
            result.gone = false
            guard !busy else { result.busy = true; return }
            switch read(result.job) {
            case .frame(let frame): result.got = frame
            case .busy: busy = true; result.busy = true
            case .gone: result.gone = true
            }
        }

        var results = jobs.map { job in
            var result = FrameResult(job: job, target: reachable(job))
            readBack(&result)
            guard !result.busy, live(), !(result.got?.isClose(to: result.target, within: 1) ?? false) else { return result }
            // An unreadable window is written all the same: the write looks its element up afresh.
            let sized = result.got.map { abs($0.width - result.target.width) <= 1 && abs($0.height - result.target.height) <= 1 }
            result.written = true
            if !(sized == true ? move(job) : write(job)) { busy = true; result.busy = true; result.got = nil }
            return result
        }
        let written = results.indices.filter { results[$0].written }
        guard !written.isEmpty else { return results }
        wait()
        for i in written where !results[i].busy { readBack(&results[i]) }

        // Only windows that answered and landed elsewhere; an unreadable (possibly hung) one is not worth a second try.
        let misses = written.filter { i in results[i].got.map { !$0.isClose(to: results[i].target, within: 2) } ?? false }
        guard !misses.isEmpty, live(), !busy else { return results }
        var retried: [Int] = []
        for i in misses where !busy {
            results[i].retried = true
            if write(results[i].job) { retried.append(i) } else { busy = true; results[i].busy = true; results[i].got = nil }
        }
        wait()
        for i in retried {
            readBack(&results[i])
            if !results[i].busy { recordMinimum(results[i], stepSizes: stepSizes[results[i].job.id] ?? []) }
        }
        return results
    }

    /// The job's frame grown to the window's recorded minimum size: as close as the window will come.
    private func reachable(_ job: FrameJob) -> CGRect {
        guard let minimum = minimumSizes[job.id] else { return job.frame }
        return CGRect(origin: job.frame.origin, size: job.frame.size.grown(to: minimum))
    }

    private func wait() {
        if settle > 0 { Thread.sleep(forTimeInterval: settle) }
    }

    /// A window that came back larger than asked, where it was put, may have a minimum size in that dimension. It
    /// counts once a later pass sees the same refusal: an app still resizing to an earlier size (Ghostty reflowing,
    /// an Electron app, or a size an animation step asked for) has caught up by then. A window somewhere else has
    /// left (native full screen, another Space) and says nothing about how small it can be; nor does one asked for a
    /// frame partly off the screen, which AppKit sizes as it keeps a window on screen and clear of an edge. One that
    /// came back smaller than its minimum, where it was put, shows the minimum was too big, as one learned from an app
    /// that had not caught up after all: it is lowered to what the window came out at.
    private func recordMinimum(_ result: FrameResult, stepSizes: Set<CGSize>) {
        let id = result.job.id
        guard let got = result.got else { return }
        guard abs(got.minX - result.job.frame.minX) <= 2, abs(got.minY - result.job.frame.minY) <= 2,
              !stepSizes.contains(got.size), learns(result.job.frame) else { return lock.withLock { candidates[id] = nil } }
        let wanted = result.job.frame.size
        let refused = CGSize(width: got.width > wanted.width + 2 ? got.width : 0,
                             height: got.height > wanted.height + 2 ? got.height : 0)
        lock.withLock {
            _ = lower(id, to: got.size)
            let seen = candidates[id]?.size ?? .zero
            candidates[id] = refused == .zero ? nil : (refused, result.job.pid)
            let confirmed = CGSize(width: refused.width > 0 && abs(refused.width - seen.width) <= 2 ? refused.width : 0,
                                   height: refused.height > 0 && abs(refused.height - seen.height) <= 2 ? refused.height : 0)
            if confirmed != .zero {
                minimums[id] = minimums[id]?.grown(to: confirmed) ?? confirmed
                candidates[id] = nil
            }
        }
    }

    /// One process's queue and what is waiting on it. Guarded by the scheduler's lock.
    private final class App {
        let pid: Int32
        let queue: DispatchQueue
        var pending: [FrameJob] = []
        var batches: [Batch] = []
        var steps: [FrameJob] = []
        /// While busy, how long until the next read to see if the process answers; 0 while it answers.
        var backoff: TimeInterval = 0
        /// Drains of animation steps in a row done within `slowStep`. Queue only.
        var fastDrains = 0
        /// The window read to see if a busy process answers again.
        var probe: FrameJob?
        /// The newest frame per window that a busy process has not been sent.
        var held: [FrameJob] = []
        /// Its pending frames are to be written even while it is busy. See `submit(_:ignoringBusy:completion:)`.
        var forced = false
        /// The size each window's last step wrote, so the next step can be a plain move. Queue only.
        var written: [WindowID: CGSize] = [:]
        /// Every size steps asked of each window since the last full pass that included it. Apps that resize
        /// lazily can still be at one of them when the full write reads back. Queue only.
        var stepSizes: [WindowID: Set<CGSize>] = [:]
        /// The screen edge each window's steps have been led past, while steps carry one. Queue only.
        var ledIn: [WindowID: CGFloat] = [:]
        /// How much wider than asked each window's steps past the screen edge are written. See `ResizeOnce.snapSlack`.
        var slack: [WindowID: CGFloat] = [:]
        /// How many more of each window's frames past the screen edge are read back. See `probe`.
        var probes: [WindowID: Int] = [:]
        var scheduled = false
        var prepared = false

        init(_ pid: Int32) {
            self.pid = pid
            self.queue = DispatchQueue(label: "dinky.frames.\(pid)")
        }
    }

    /// Collects results from each process queue a submit went to, then calls its completion.
    private final class Batch {
        private let lock = NSLock()
        private var waiting: Int
        private var results: [FrameResult] = []
        private let completion: Completion?

        init(waiting: Int, _ completion: Completion?) {
            self.waiting = waiting
            self.completion = completion
        }

        func report(_ new: [FrameResult]) {
            let done: [FrameResult]? = lock.withLock {
                results += new
                waiting -= 1
                return waiting == 0 ? results : nil
            }
            if let done { completion?(done) }
        }
    }
}

extension CGSize {
    /// The larger of the two sizes in each dimension.
    public func grown(to other: CGSize) -> CGSize {
        CGSize(width: max(width, other.width), height: max(height, other.height))
    }

    /// A minimum size taken down to `other` in each dimension where that is more than 2 pt smaller: to a size a window
    /// was seen at.
    public func lowered(to other: CGSize) -> CGSize {
        CGSize(width: other.width < width - 2 ? other.width : width, height: other.height < height - 2 ? other.height : height)
    }
}

extension CGRect {
    /// Every edge within `tolerance` points of the other rect's.
    public func isClose(to other: CGRect, within tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance &&
            abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
