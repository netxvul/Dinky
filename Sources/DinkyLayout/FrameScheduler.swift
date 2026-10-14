import CoreGraphics
import Foundation

/// A frame to write: a window, the process that owns it and where it should go (top-left origin).
public struct FrameJob: Equatable, Sendable {
    public var pid: Int32
    public var id: WindowID
    public var frame: CGRect

    public init(pid: Int32, id: WindowID, frame: CGRect) {
        self.pid = pid
        self.id = id
        self.frame = frame
    }
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

    /// Landed within 2 pt of the target on every edge.
    public var matched: Bool { got.map { $0.isClose(to: target, within: 2) } ?? false }
}

/// Schedules frame writes: one serial queue per process so a slow app only stalls itself,
/// the newest frame per window wins, and a window that refuses its frame is written at most twice.
/// Animation steps take a lighter path on the same queues: written once, not read back, and only moved
/// when their size is the one last written. The actual reads and writes are injected, so this is testable
/// without Accessibility.
public final class FrameScheduler: @unchecked Sendable {
    public typealias Completion = ([FrameResult]) -> Void

    private let settle: TimeInterval
    private let prepare: (Int32) -> Void
    private let read: (FrameJob) -> CGRect?
    private let write: (FrameJob) -> Void
    private let move: (FrameJob) -> Void

    /// TEMPORARY: how long each process's animation steps took to write, with how many windows.
    public var onStepsWritten: ((Int32, Double, Int) -> Void)?

    private let lock = NSLock()
    private var apps: [Int32: App] = [:]
    private var minimums: [WindowID: CGSize] = [:]
    /// Refusals seen once, by window: a minimum only when a later pass sees the same one.
    private var candidates: [WindowID: CGSize] = [:]
    /// Bumped by `cancel`; writes queued under an older generation are dropped.
    private var generation = 0

    /// `prepare` runs once per process before its first write; `read`, `write` and `move` (position only)
    /// run on that process's queue.
    public init(settle: TimeInterval = 0.1, prepare: @escaping (Int32) -> Void = { _ in },
                read: @escaping (FrameJob) -> CGRect?, write: @escaping (FrameJob) -> Void,
                move: ((FrameJob) -> Void)? = nil) {
        self.settle = settle
        self.prepare = prepare
        self.read = read
        self.write = write
        self.move = move ?? write
    }

    /// Sizes windows refused to go below, seen the same on two passes. Only dimensions that were refused are set.
    public var minimumSizes: [WindowID: CGSize] { lock.withLock { minimums } }

    /// Windows that refused a size once and wait for a second pass to tell a minimum from an app catching up.
    public var unconfirmedMinimums: Set<WindowID> { lock.withLock { Set(candidates.keys) } }

    /// Queue frames. `completion` gets the results of every process queue these jobs went to,
    /// once each has written them (or newer frames for the same windows).
    public func submit(_ jobs: [FrameJob], completion: Completion? = nil) {
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
                schedule(app)
            }
        }
    }

    /// Queue animation steps: each replaces any step of the same window not written yet, and is written once
    /// without reading back. A step whose size is the one last written for its window only moves it.
    public func step(_ jobs: [FrameJob]) {
        lock.withLock {
            for job in jobs {
                let app = app(job.pid)
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
            // What steps wrote is the queue's alone, so it is cleared there, after anything already queued.
            for app in apps.values { app.queue.async { app.written[id] = nil; app.stepSizes[id] = nil } }
        }
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
            for app in apps.values { app.pending = []; app.steps = [] }
        }
    }

    /// Take everything pending for one process and write it, steps first. Runs on the process's queue.
    private func drain(_ app: App) {
        let (steps, jobs, batches, needsPrepare, generation) = lock.withLock {
            defer { app.steps = []; app.pending = []; app.batches = []; app.scheduled = false; app.prepared = true }
            return (app.steps, app.pending, app.batches, !app.prepared, self.generation)
        }
        if needsPrepare { prepare(app.pid) }
        let began = Date()
        defer { if !steps.isEmpty { onStepsWritten?(app.pid, Date().timeIntervalSince(began), steps.count) } }
        for job in steps {
            app.written[job.id] == job.frame.size ? move(job) : write(job)
            app.written[job.id] = job.frame.size
            app.stepSizes[job.id, default: []].insert(job.frame.size)
        }
        let results = run(jobs, stepSizes: app.stepSizes) { self.lock.withLock { self.generation } == generation }
        for result in results {
            if result.written { app.written[result.job.id] = nil }
            app.stepSizes[result.job.id] = nil
        }
        // In place, or already where its minimum lets it be: whatever it refused before, it has caught up.
        lock.withLock { for result in results where result.matched || !result.written { candidates[result.job.id] = nil } }
        for batch in batches { batch.report(results) }
    }

    /// Write, settle, read back; write the misses once more, settle, read back again. Writes only while `live`.
    /// A window already where its recorded minimum size lets it be is neither written nor retried. A window
    /// still at a size an animation step asked for is catching up, not refusing, so it shows no minimum.
    private func run(_ jobs: [FrameJob], stepSizes: [WindowID: Set<CGSize>], live: () -> Bool) -> [FrameResult] {
        var results = jobs.map { job in
            let current = read(job), target = reachable(job)
            let write = live() && !(current?.isClose(to: target, within: 1) ?? false)
            if write { self.write(job) }
            return FrameResult(job: job, target: target, got: current, written: write)
        }
        let written = results.indices.filter { results[$0].written }
        guard !written.isEmpty else { return results }
        wait()
        for i in written { results[i].got = read(results[i].job) }

        // Only windows that answered and landed elsewhere; an unreadable (possibly hung) one is not worth a second try.
        let misses = written.filter { i in results[i].got.map { !$0.isClose(to: results[i].target, within: 2) } ?? false }
        guard !misses.isEmpty, live() else { return results }
        for i in misses {
            write(results[i].job)
            results[i].retried = true
        }
        wait()
        for i in misses {
            results[i].got = read(results[i].job)
            recordMinimum(results[i], stepSizes: stepSizes[results[i].job.id] ?? [])
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
    /// left (native full screen, another Space) and says nothing about how small it can be.
    private func recordMinimum(_ result: FrameResult, stepSizes: Set<CGSize>) {
        let id = result.job.id
        guard let got = result.got else { return }
        guard abs(got.minX - result.job.frame.minX) <= 2, abs(got.minY - result.job.frame.minY) <= 2,
              !stepSizes.contains(got.size) else { return lock.withLock { candidates[id] = nil } }
        let wanted = result.job.frame.size
        let refused = CGSize(width: got.width > wanted.width + 2 ? got.width : 0,
                             height: got.height > wanted.height + 2 ? got.height : 0)
        lock.withLock {
            let seen = candidates[id] ?? .zero
            candidates[id] = refused == .zero ? nil : refused
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
        /// The size each window's last step wrote, so the next step can be a plain move. Queue only.
        var written: [WindowID: CGSize] = [:]
        /// Every size steps asked of each window since the last full pass that included it. Apps that resize
        /// lazily can still be at one of them when the full write reads back. Queue only.
        var stepSizes: [WindowID: Set<CGSize>] = [:]
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
}

extension CGRect {
    /// Every edge within `tolerance` points of the other rect's.
    public func isClose(to other: CGRect, within tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance &&
            abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
