import CoreGraphics
import Foundation
import Testing
@testable import DinkyLayout

/// A pretend window server: windows hold frames, some refuse widths below a minimum, writes can be held,
/// and windows can stop answering or be gone.
private final class FakeWindows: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [WindowID: CGRect] = [:]
    private var minWidths: [WindowID: CGFloat] = [:]
    private(set) var writes: [(WindowID, CGRect)] = []
    private(set) var prepared: [Int32] = []
    /// Every call, as "read 10", "write 10" or "move 10", with when it was made.
    private var calls: [(String, Date)] = []
    /// Calls on windows in here time out, as in an app that has stopped answering.
    private var stalled: Set<WindowID> = []
    /// Windows in here cannot be read and take no writes.
    private var vanished: Set<WindowID> = []
    /// Writes to windows in here block until the semaphore is signalled.
    var holds: [WindowID: DispatchSemaphore] = [:]

    init(_ frames: [WindowID: CGRect] = [:], minWidths: [WindowID: CGFloat] = [:]) {
        self.frames = frames
        self.minWidths = minWidths
    }

    func writes(to id: WindowID) -> [CGRect] { lock.withLock { writes.filter { $0.0 == id }.map(\.1) } }

    func calls(to id: WindowID) -> [String] { lock.withLock { calls.map(\.0).filter { $0.hasSuffix(" \(id)") } } }

    /// When each read of the window was made.
    func reads(of id: WindowID) -> [Date] { lock.withLock { calls.filter { $0.0 == "read \(id)" }.map(\.1) } }

    func stall(_ ids: Set<WindowID>) { lock.withLock { stalled = ids } }

    func vanish(_ ids: Set<WindowID>) { lock.withLock { vanished = ids } }

    /// With `moves`, a move sets only the window's origin and is logged as one; otherwise it is a write.
    func scheduler(backoff: TimeInterval = 1, moves: Bool = false, learns: @escaping (CGRect) -> Bool = { _ in true }) -> FrameScheduler {
        FrameScheduler(
            settle: 0,
            backoff: backoff,
            prepare: { pid in self.lock.withLock { self.prepared.append(pid) } },
            read: { job in
                self.lock.withLock {
                    self.calls.append(("read \(job.id)", Date()))
                    if self.stalled.contains(job.id) { return .busy }
                    if self.vanished.contains(job.id) { return .gone }
                    return self.frames[job.id].map(FrameRead.frame) ?? .gone
                }
            },
            write: { job in
                self.holds[job.id]?.wait()
                return self.lock.withLock {
                    self.calls.append(("write \(job.id)", Date()))
                    if self.stalled.contains(job.id) { return false }
                    if self.vanished.contains(job.id) { return true }
                    self.writes.append((job.id, job.frame))
                    var frame = job.frame
                    frame.size.width = max(frame.width, self.minWidths[job.id] ?? 0)
                    self.frames[job.id] = frame
                    return true
                }
            },
            move: moves ? { job in
                self.lock.withLock {
                    self.calls.append(("move \(job.id)", Date()))
                    if self.stalled.contains(job.id) { return false }
                    self.frames[job.id]?.origin = job.frame.origin
                    return true
                }
            } : nil, learns: learns)
    }
}

/// One window as AppKit sizes it through Accessibility: a size that would take it past the screen's right edge from on
/// screen stops there, unless it is already a point past it, and its app snaps widths down to a multiple of `cell`. A
/// write is size, position, size, as FrameApplier's. `shown` has its frame after every write or move.
private final class AppKitLike: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: CGRect
    private let edge: CGFloat, cell: CGFloat
    private var frames: [CGRect] = []
    var shown: [CGRect] { lock.withLock { frames } }

    init(frame: CGRect, edge: CGFloat, cell: CGFloat) {
        self.frame = frame
        self.edge = edge
        self.cell = cell
    }

    private func size(_ width: CGFloat) {
        var width = width
        if frame.maxX < edge + 1, frame.minX + width > edge { width = edge - frame.minX }
        frame.size.width = (width / cell).rounded(.down) * cell
    }

    func scheduler() -> FrameScheduler {
        FrameScheduler(settle: 0, read: { _ in self.lock.withLock { .frame(self.frame) } }, write: { job in
            self.lock.withLock {
                self.size(job.frame.width)
                self.frame.origin = job.frame.origin
                self.size(job.frame.width)
                self.frames.append(self.frame)
            }
            return true
        }, move: { job in
            self.lock.withLock {
                self.frame.origin = job.frame.origin
                self.frames.append(self.frame)
            }
            return true
        })
    }
}

private func job(_ pid: Int32, _ id: WindowID, _ x: CGFloat) -> FrameJob {
    FrameJob(pid: pid, id: id, frame: CGRect(x: x, y: 0, width: 100, height: 100))
}

private func submitAndWait(_ scheduler: FrameScheduler, _ jobs: [FrameJob],
                           fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) -> [FrameResult] {
    let done = DispatchSemaphore(value: 0)
    var results: [FrameResult] = []
    scheduler.submit(jobs) { results = $0; done.signal() }
    #expect(done.wait(timeout: .now() + 2) == .success,
            sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column))
    return results.sorted { $0.job.id < $1.job.id }
}

struct FrameSchedulerTests {
    @Test func `Writes and reads back`() {
        let fake = FakeWindows()
        let results = submitAndWait(fake.scheduler(), [job(1, 10, 0), job(2, 20, 100)])
        #expect(results.map(\.matched) == [true, true])
        #expect(results.map(\.written) == [true, true])
        #expect(results.map(\.retried) == [false, false])
        #expect(results.map(\.got) == [job(1, 10, 0).frame, job(2, 20, 100).frame])
    }

    @Test func `Skips window already in place within one point`() {
        let fake = FakeWindows([10: CGRect(x: 0.5, y: 0, width: 100, height: 100.5)])
        let results = submitAndWait(fake.scheduler(), [job(1, 10, 0)])
        #expect(results.map(\.written) == [false])
        #expect(results.map(\.matched) == [true])
        #expect(fake.writes(to: 10).isEmpty)
    }

    @Test func `A window already the right size is only moved`() {
        let fake = FakeWindows([10: CGRect(x: 0, y: 0, width: 100.5, height: 100)])
        let results = submitAndWait(fake.scheduler(moves: true), [job(1, 10, 50)])
        #expect(fake.calls(to: 10) == ["read 10", "move 10", "read 10"])
        #expect(results.map(\.written) == [true])
        #expect(results.map(\.matched) == [true])
    }

    @Test func `A move that does not land is retried as a whole write`() {
        let lock = NSLock()
        var frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        var calls: [String] = []
        // Moves stop at x = 30, as a window held back by the screen edge; a whole write gets there.
        let scheduler = FrameScheduler(settle: 0, read: { _ in lock.withLock { calls.append("read"); return .frame(frame) } },
                                       write: { job in lock.withLock { calls.append("write"); frame = job.frame }; return true },
                                       move: { job in lock.withLock { calls.append("move"); frame.origin.x = min(job.frame.minX, 30) }; return true })
        let results = submitAndWait(scheduler, [job(1, 10, 50)])
        #expect(lock.withLock { calls } == ["read", "move", "read", "write", "read"])
        #expect(results.map(\.retried) == [true])
        #expect(results.map(\.matched) == [true])
    }

    @Test func `Prepares each process once`() {
        let fake = FakeWindows()
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0), job(1, 11, 100)])
        _ = submitAndWait(scheduler, [job(1, 10, 200), job(2, 20, 0)])
        #expect(fake.prepared.sorted() == [1, 2])
    }

    @Test func `Newest frame wins while queue is busy`() {
        let fake = FakeWindows()
        let hold = DispatchSemaphore(value: 0)
        fake.holds[10] = hold
        let scheduler = fake.scheduler()
        let done = DispatchSemaphore(value: 0)
        scheduler.submit([job(1, 10, 0)])
        Thread.sleep(forTimeInterval: 0.05)  // the queue is now stuck in window 10's write
        scheduler.submit([job(1, 10, 1), job(1, 11, 1)])
        scheduler.submit([job(1, 11, 2)])
        var last: [FrameResult] = []
        scheduler.submit([job(1, 10, 3), job(1, 11, 3)]) { last = $0; done.signal() }
        hold.signal()
        hold.signal()
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(fake.writes(to: 10).map(\.minX) == [0, 3])
        #expect(fake.writes(to: 11).map(\.minX) == [3])
        #expect(last.map(\.job.frame.minX) == [3, 3])
    }

    @Test func `Busy app does not block others`() {
        let fake = FakeWindows()
        let hold = DispatchSemaphore(value: 0)
        fake.holds[10] = hold
        let scheduler = fake.scheduler()
        scheduler.submit([job(1, 10, 0)])
        let results = submitAndWait(scheduler, [job(2, 20, 0)])
        #expect(results.map(\.matched) == [true])
        #expect(fake.writes(to: 10).isEmpty)
        hold.signal()
    }

    @Test func `Cancel drops queued frames`() {
        let fake = FakeWindows()
        let hold = DispatchSemaphore(value: 0)
        fake.holds[10] = hold
        let scheduler = fake.scheduler()
        let done = DispatchSemaphore(value: 0)
        scheduler.submit([job(1, 10, 0)])
        Thread.sleep(forTimeInterval: 0.05)  // the queue is now stuck in window 10's write
        var results: [FrameResult] = []
        scheduler.submit([job(1, 10, 1), job(1, 11, 1)]) { results = $0; done.signal() }
        scheduler.cancel()
        hold.signal()
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(fake.writes(to: 10).map(\.minX) == [0])
        #expect(fake.writes(to: 11).isEmpty)
        #expect(results.isEmpty)
        #expect(submitAndWait(scheduler, [job(1, 11, 2)]).map(\.matched) == [true])
    }

    @Test func `Cancel stops the second try`() {
        var writes = 0
        let scheduler = FrameScheduler(settle: 0.2, read: { _ in .frame(CGRect(x: 0, y: 0, width: 574, height: 100)) },
                                       write: { _ in writes += 1; return true })
        let done = DispatchSemaphore(value: 0)
        var results: [FrameResult] = []
        scheduler.submit([job(1, 10, 0)]) { results = $0; done.signal() }
        Thread.sleep(forTimeInterval: 0.1)  // the first write is done and settling
        scheduler.cancel()
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(writes == 1)
        #expect(results.map(\.retried) == [false])
    }

    @Test func `Completion waits for every process`() {
        let fake = FakeWindows()
        let results = submitAndWait(fake.scheduler(), [job(1, 10, 0), job(2, 20, 0), job(3, 30, 0)])
        #expect(results.map(\.job.id) == [10, 20, 30])
    }

    @Test func `Refused size is retried once and recorded as minimum on the second pass`() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        let results = submitAndWait(scheduler, [job(1, 10, 0), job(1, 11, 100)])
        #expect(results.map(\.matched) == [false, true])
        #expect(results.map(\.retried) == [true, false])
        #expect(results[0].got?.width == 574)
        #expect(fake.writes(to: 10).count == 2)
        #expect(scheduler.minimumSizes == [:], "one refusal could be an app still catching up")
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(scheduler.minimumSizes == [10: CGSize(width: 574, height: 0)])
    }

    @Test func `A window asked partly off the screen teaches no minimum`() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler(learns: { $0.minX >= 0 })
        let parked = FrameJob(pid: 1, id: 10, frame: CGRect(x: -400, y: 0, width: 100, height: 100))
        _ = submitAndWait(scheduler, [parked])
        _ = submitAndWait(scheduler, [parked])
        #expect(scheduler.minimumSizes == [:])
        #expect(scheduler.unconfirmedMinimums.isEmpty)
    }

    @Test func `An app that catches up shows no minimum`() {
        var lagging = true
        let scheduler = FrameScheduler(settle: 0, read: { job in
            .frame(lagging ? CGRect(x: 0, y: 0, width: 2524, height: 100) : job.frame)
        }, write: { _ in true })
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        lagging = false
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        lagging = true
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(scheduler.minimumSizes == [:], "landing where it was put forgets the earlier refusal")
    }

    @Test func `Two refusals in one pass complete once with both minimums`() {
        let fake = FakeWindows(minWidths: [10: 574, 20: 115])
        let scheduler = fake.scheduler()
        var completions = 0
        var minimums: [WindowID: CGSize] = [:]
        _ = submitAndWait(scheduler, [job(1, 10, 0), job(2, 20, 100), job(2, 21, 200)])
        let done = DispatchSemaphore(value: 0)
        scheduler.submit([job(1, 10, 0), job(2, 20, 100), job(2, 21, 200)]) { _ in
            completions += 1
            minimums = scheduler.minimumSizes
            done.signal()
        }
        #expect(done.wait(timeout: .now() + 2) == .success)
        Thread.sleep(forTimeInterval: 0.05)
        #expect(completions == 1)
        #expect(minimums == [10: CGSize(width: 574, height: 0), 20: CGSize(width: 115, height: 0)])
    }

    @Test func `Recorded minimum is not written again`() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        let again = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(fake.writes(to: 10).count == 4)
        #expect(again.map(\.written) == [false])
    }

    @Test func `Move of a window at its minimum is written once without retry`() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        let moved = submitAndWait(scheduler, [job(1, 10, 50)])
        #expect(fake.writes(to: 10).count == 5)
        #expect(moved.map(\.retried) == [false])
    }

    @Test func `Minimums found in each dimension are kept`() {
        var frame = CGRect.zero
        let scheduler = FrameScheduler(settle: 0, read: { _ in .frame(frame) }, write: { job in
            frame = CGRect(origin: job.frame.origin, size: job.frame.size.grown(to: CGSize(width: 574, height: 300)))
            return true
        })
        for _ in 0..<2 { _ = submitAndWait(scheduler, [FrameJob(pid: 1, id: 10, frame: CGRect(x: 0, y: 0, width: 100, height: 400))]) }
        for _ in 0..<2 { _ = submitAndWait(scheduler, [FrameJob(pid: 1, id: 10, frame: CGRect(x: 0, y: 0, width: 600, height: 100))]) }
        #expect(scheduler.minimumSizes == [10: CGSize(width: 574, height: 300)])
    }

    @Test func `A window that comes out smaller than its minimum has it lowered`() {
        var minimum = CGSize(width: 574, height: 0), largest = CGSize(width: 10_000, height: 10_000)
        var frame = CGRect.zero
        let scheduler = FrameScheduler(settle: 0, read: { _ in .frame(frame) }, write: { job in
            let size = job.frame.size.grown(to: minimum)
            frame = CGRect(origin: job.frame.origin, size: CGSize(width: min(size.width, largest.width), height: min(size.height, largest.height)))
            return true
        })
        for _ in 0..<2 { _ = submitAndWait(scheduler, [job(1, 10, 0)]) }
        #expect(scheduler.minimumSizes == [10: CGSize(width: 574, height: 0)])
        // As an app does that no longer keeps to the size it refused to go below, or never did: asked for the minimum,
        // it comes out narrower.
        (minimum, largest) = (.zero, CGSize(width: 500, height: 10_000))
        let results = submitAndWait(scheduler, [FrameJob(pid: 1, id: 10, frame: CGRect(x: 50, y: 0, width: 574, height: 100))])
        #expect(results.map(\.retried) == [true])
        #expect(scheduler.minimumSizes == [10: CGSize(width: 500, height: 0)])
    }

    @Test func `A minimum is lowered to a size the window was seen at, where that is smaller`() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        for _ in 0..<2 { _ = submitAndWait(scheduler, [job(1, 10, 0)]) }
        #expect(!scheduler.lowerMinimum(of: 10, to: CGSize(width: 600, height: 50)), "no smaller where it has a minimum")
        #expect(scheduler.lowerMinimum(of: 10, to: CGSize(width: 400, height: 50)))
        #expect(scheduler.minimumSizes == [10: CGSize(width: 400, height: 0)])
        #expect(!scheduler.lowerMinimum(of: 20, to: .zero), "none to lower")
        #expect(CGSize(width: 300, height: 200).lowered(to: CGSize(width: 299, height: 100)) == CGSize(width: 300, height: 100),
                "within 2 pt is the same size")
    }

    @Test func `A window at its recorded minimum is matched without a write`() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        let again = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(again.map(\.written) == [false])
        #expect(again.map(\.matched) == [true], "as close as it will come is where it was asked to go")
    }

    @Test func `Forget clears a window's minimum and its unconfirmed refusal`() {
        let fake = FakeWindows(minWidths: [10: 574, 20: 115])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0), job(1, 20, 100)])
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(scheduler.minimumSizes[10] != nil)
        #expect(scheduler.unconfirmedMinimums == [20])
        scheduler.forget(10)
        scheduler.forget(20)
        #expect(scheduler.minimumSizes == [:])
        #expect(scheduler.unconfirmedMinimums.isEmpty)
    }

    @Test func `Unreadable window is written once and reported unmatched`() {
        var writes = 0
        let scheduler = FrameScheduler(settle: 0, read: { _ in .gone }, write: { _ in writes += 1; return true })
        let results = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(results.map(\.matched) == [false])
        #expect(results.map(\.retried) == [false])
        #expect(writes == 1)
        #expect(scheduler.minimumSizes == [:])
    }

    @Test func `Empty submit completes immediately`() {
        let results = submitAndWait(FakeWindows().scheduler(), [])
        #expect(results.isEmpty)
    }

    @Test func `Plain tiles need no raises`() {
        let layout = workspace(3, gaps: Gaps(all: 8)).layout()
        #expect(layout.raises(current: [3, 1, 2]) == [])
        #expect(workspace(3).layout().raises(current: [2, 3, 1]) == [])
    }

    @Test func `Accordion raises only when order differs`() {
        let layout = workspace(3, algorithm: .dwindle(.accordion)).layout()
        #expect(layout.order == [3, 2, 1])
        #expect(layout.raises(current: [3, 99, 2, 1]) == [])
        #expect(layout.raises(current: [1, 2, 3]) == [2, 3], "1 is already below 2, so only 2 and 3 go up")
        #expect(layout.raises(current: [3, 1, 2]) == [], "the front window is on top; which one peeks is not worth a flash")
    }

    @Test func `Accordion neighbours only need the front window on top`() {
        var ws = workspace(3, algorithm: .dwindle(.accordion))
        ws.focus(2)
        let layout = ws.layout()
        #expect(layout.order == [2, 1, 3])
        #expect(layout.raises(current: [2, 3, 1]) == [], "1 and 3 peek out at opposite edges, so their order never shows")
        #expect(layout.raises(current: [3, 2, 1]) == [2], "only the front window goes up, nothing flashes above it")
    }

    @Test func `Fullscreen raises when not in front`() {
        var ws = workspace(2)
        ws.toggleFullscreen()
        let layout = ws.layout()
        #expect(layout.raises(current: [2, 1]) == [])
        #expect(layout.raises(current: [1, 2]) == [2])
    }
}

struct FrameSchedulerStepTests {
    @Test func `Steps move when the size is unchanged and are not read back`() {
        let lock = NSLock()
        var calls: [String] = []
        let scheduler = FrameScheduler(settle: 0, read: { _ in Issue.record("steps are not read back"); return .gone },
                                       write: { job in lock.withLock { calls.append("write \(Int(job.frame.minX))") }; return true },
                                       move: { job in lock.withLock { calls.append("move \(Int(job.frame.minX))") }; return true })
        scheduler.step([job(1, 10, 0)])
        scheduler.step([job(1, 10, 10)])
        var wider = job(1, 10, 20)
        wider.frame.size.width = 200
        scheduler.step([wider])
        scheduler.step([])
        Thread.sleep(forTimeInterval: 0.2)
        // The first two may coalesce; either way the first write sizes the window and a resize writes again.
        let result = lock.withLock { calls }
        #expect(result.first?.hasPrefix("write") == true)
        #expect(result.last == "write 20")
        #expect(!result.dropFirst().dropLast().contains { $0.hasPrefix("write") })
    }

    @Test func `A window growing to the left is led past the edge once, from where it is, however the steps coalesce`() {
        let lock = NSLock()
        var calls: [String] = [], frame = CGRect(x: 760, y: 0, width: 723, height: 100)
        let entered = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0)
        var held = false
        let scheduler = FrameScheduler(settle: 0, read: { _ in lock.withLock { .frame(frame) } }, write: { job in
            // The first write waits, so the steps behind it pile up.
            if lock.withLock({ defer { held = true }; return !held }) { entered.signal(); gate.wait() }
            lock.withLock { calls.append("write \(Int(job.frame.minX)) \(Int(job.frame.width))"); frame = job.frame }
            return true
        })
        func step(_ x: CGFloat, leadEdge: CGFloat? = 1512) -> FrameJob {
            FrameJob(pid: 1, id: 10, frame: CGRect(x: x, y: 0, width: 1514 - x, height: 100), leadEdge: leadEdge)
        }
        scheduler.step([step(700)])
        #expect(entered.wait(timeout: .now() + 2) == .success)
        scheduler.step([step(600)])
        scheduler.step([step(500)])
        gate.signal()
        Thread.sleep(forTimeInterval: 0.1)
        // Sized to the edge where it is and moved past it by the nudge, then stepped.
        #expect(lock.withLock { calls } == ["write 762 752", "write 700 814", "write 500 1014"])

        // A step without an edge ends the run. Already past the edge, the window needs no lead-in; back on screen after
        // a full pass, it is led in again from there.
        lock.withLock { calls = [] }
        scheduler.step([step(400, leadEdge: nil)])
        Thread.sleep(forTimeInterval: 0.05)
        scheduler.step([step(300)])
        Thread.sleep(forTimeInterval: 0.05)
        _ = submitAndWait(scheduler, [FrameJob(pid: 1, id: 10, frame: CGRect(x: 200, y: 0, width: 1000, height: 100))])
        scheduler.step([step(100)])
        Thread.sleep(forTimeInterval: 0.05)
        #expect(lock.withLock { calls } == ["write 400 1114", "write 300 1214", "write 200 1000", "write 202 1312",
                                             "write 100 1414"])
    }

    @Test func `A window its app leaves short of the edge is moved past it, and its steps there written wider`() {
        let lock = NSLock()
        var calls: [String] = [], frame = CGRect(x: 760, y: 0, width: 723, height: 100)
        // Snaps its width down to a multiple of ten, as a terminal snaps to its character grid.
        let scheduler = FrameScheduler(settle: 0, read: { _ in lock.withLock { .frame(frame) } }, write: { job in
            lock.withLock {
                frame = CGRect(x: job.frame.minX, y: 0, width: (job.frame.width / 10).rounded(.down) * 10, height: 100)
                calls.append("write \(Int(frame.minX)) \(Int(frame.width))")
            }
            return true
        }, move: { job in
            lock.withLock { frame.origin.x = job.frame.minX; calls.append("move \(Int(frame.minX))") }
            return true
        })
        scheduler.step([FrameJob(pid: 1, id: 10, frame: CGRect(x: 700, y: 0, width: 814, height: 100), leadEdge: 1512)])
        Thread.sleep(forTimeInterval: 0.05)
        // Led in to 750 wide, its right edge on the screen edge, then moved past it; its step 16 wider: 830 from 816.
        #expect(lock.withLock { calls } == ["write 762 750", "move 764", "write 700 830"])
        #expect(lock.withLock { frame.maxX } > 1513)
    }

    @Test func `A window led past the edge stays past it on every step, its app snapping its size or not`() {
        for cell in [1, 8, 10] as [CGFloat] {
            for x in [760, 761, 763] as [CGFloat] {
                let windows = AppKitLike(frame: CGRect(x: x, y: 0, width: 723, height: 100), edge: 1512, cell: cell)
                let scheduler = windows.scheduler()
                for left in stride(from: x - 20, through: 40, by: -60) {
                    scheduler.step([FrameJob(pid: 1, id: 10, frame: CGRect(x: left, y: 0, width: 1514 - left, height: 100),
                                             leadEdge: 1512)])
                    Thread.sleep(forTimeInterval: 0.01)
                }
                Thread.sleep(forTimeInterval: 0.05)
                // Every frame shown once the lead-in has taken it past the edge stays past it, but for one a snapping
                // app can leave up to a cell short before the step's read finds that out and moves it on.
                let shown = windows.shown.drop { $0.maxX < 1513 }
                let back = shown.filter { $0.maxX < 1513 }
                #expect(!shown.isEmpty)
                #expect(back.count <= 1 && back.allSatisfy { $0.maxX > 1512 - cell }, "cell \(cell), from \(x): \(shown.map(\.maxX))")
                #expect(shown.suffix(3).allSatisfy { $0.maxX >= 1513 })
            }
        }
    }

    @Test func `A lead-in the app has not taken yet, or does not answer after, is left alone`() {
        // Read back at its old width, as an app still taking the size: neither widened nor moved.
        let lock = NSLock()
        var calls: [String] = [], reads = 0
        let lagging = FrameScheduler(settle: 0, read: { _ in
            lock.withLock { reads += 1; return .frame(CGRect(x: 760, y: 0, width: 723, height: 100)) }
        }, write: { job in
            lock.withLock { calls.append("write \(Int(job.frame.minX)) \(Int(job.frame.width))") }
            return true
        }, move: { job in lock.withLock { calls.append("move \(Int(job.frame.minX))") }; return true })
        lagging.step([FrameJob(pid: 1, id: 10, frame: CGRect(x: 700, y: 0, width: 814, height: 100), leadEdge: 1512)])
        Thread.sleep(forTimeInterval: 0.05)
        #expect(lock.withLock { calls } == ["write 762 752", "write 700 814"])

        // Not answering the read after the lead-in: no step is sent, and the app counts as busy.
        let windows = FakeWindows([10: CGRect(x: 760, y: 0, width: 723, height: 100)])
        let scheduler = windows.scheduler()
        var answered = 0
        let stalling = FrameScheduler(settle: 0, backoff: 10, read: { job in
            lock.withLock { answered += 1; return answered == 1 ? .frame(CGRect(x: 760, y: 0, width: 723, height: 100)) : .busy }
        }, write: { job in lock.withLock { calls.append("write \(Int(job.frame.minX))") }; return true })
        lock.withLock { calls = [] }
        stalling.step([FrameJob(pid: 1, id: 10, frame: CGRect(x: 700, y: 0, width: 814, height: 100), leadEdge: 1512)])
        Thread.sleep(forTimeInterval: 0.05)
        #expect(lock.withLock { calls } == ["write 762"])
        #expect(stalling.isBusy(1))
        _ = scheduler
    }

    @Test func `A size an animation step asked for is not a minimum`() {
        // The window is stuck at 300 wide, a size a step asked for: it is catching up, not refusing.
        let lagging = FakeWindows([10: CGRect(x: 0, y: 0, width: 300, height: 100)], minWidths: [10: 300])
        let scheduler = lagging.scheduler()
        var step = job(1, 10, 0)
        step.frame.size.width = 300
        scheduler.step([step])
        let results = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(results[0].retried)
        #expect(scheduler.minimumSizes[10] == nil)

        // Stuck at a size nothing asked for is a minimum.
        let refusing = FakeWindows([20: CGRect(x: 0, y: 0, width: 250, height: 100)], minWidths: [20: 250])
        let other = refusing.scheduler()
        var small = job(1, 20, 0)
        small.frame.size.width = 300
        other.step([small])
        _ = submitAndWait(other, [job(1, 20, 0)])
        _ = submitAndWait(other, [job(1, 20, 0)])
        #expect(other.minimumSizes[20]?.width == 250)
    }

    @Test func `A pass that finds the window in place forgets the sizes steps asked for`() {
        // Stepped to 300 wide and already there when the pass arrives, so nothing is written.
        let fake = FakeWindows(minWidths: [10: 300])
        let scheduler = fake.scheduler()
        var step = job(1, 10, 0)
        step.frame.size.width = 300
        scheduler.step([step])
        #expect(submitAndWait(scheduler, [step]).map(\.written) == [false])

        // Then it refuses 100 at 300: two passes make that a minimum, as for a window never stepped.
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(scheduler.minimumSizes[10] == nil, "one refusal could be an app still catching up")
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        #expect(scheduler.minimumSizes[10]?.width == 300)
    }

    @Test func `A window that left shows no minimum`() {
        // Gone to native full screen while it was written: whole-display size, somewhere else.
        let scheduler = FrameScheduler(settle: 0, read: { _ in .frame(CGRect(x: 0, y: 0, width: 1024, height: 768)) }, write: { _ in true })
        let results = submitAndWait(scheduler, [job(1, 10, 50)])
        #expect(results[0].retried)
        #expect(scheduler.minimumSizes[10] == nil)
    }
}

struct SlowStepTests {
    @Test func `An app slower than a step's allowance counts as slow until cleared`() {
        let windows = FakeWindows([10: .zero, 20: .zero])
        windows.holds[10] = DispatchSemaphore(value: 0)
        let scheduler = windows.scheduler()
        // Window 10's app is stuck past the allowance; window 20's moves at once.
        scheduler.step([job(1, 10, 50), job(2, 20, 50)])
        Thread.sleep(forTimeInterval: FrameScheduler.slowStep + 0.03)
        windows.holds[10]!.signal()
        Thread.sleep(forTimeInterval: 0.05)
        #expect(scheduler.isSlow(1))
        #expect(!scheduler.isSlow(2))
        scheduler.clearSlow()
        #expect(!scheduler.isSlow(1))
    }
}

struct BusyProcessTests {
    @Test func `A process that does not answer is left alone and read again after a growing backoff`() {
        let fake = FakeWindows([10: CGRect(x: 0, y: 0, width: 100, height: 100)])
        fake.stall([10])
        let scheduler = fake.scheduler(backoff: 0.1)
        let results = submitAndWait(scheduler, [job(1, 10, 50)])
        #expect(results.map(\.busy) == [true])
        #expect(results.map(\.gone) == [false])
        #expect(results.map(\.written) == [false])
        #expect(results.map(\.got) == [nil])
        #expect(scheduler.isBusy(1))
        #expect(submitAndWait(scheduler, [job(1, 10, 60)]).map(\.busy) == [true])
        #expect(fake.calls(to: 10) == ["read 10"], "nothing is sent to it while it is busy")
        Thread.sleep(forTimeInterval: 0.6)
        // The first read, one 0.1 s later and one 0.2 s after that; the next is not due until 0.7 s.
        let reads = fake.reads(of: 10)
        let gaps = zip(reads.dropFirst(), reads).map { $0.timeIntervalSince($1) }
        #expect(reads.count == 3)
        #expect(gaps.count == 2 && gaps[0] >= 0.1 && gaps[1] >= 0.2)
        #expect(scheduler.isBusy(1))
        #expect(fake.writes(to: 10).isEmpty)
    }

    @Test func `The backoff stops growing at eight times the first`() {
        let fake = FakeWindows([10: .zero])
        fake.stall([10])
        let scheduler = fake.scheduler(backoff: 0.01)
        _ = submitAndWait(scheduler, [job(1, 10, 50)])
        Thread.sleep(forTimeInterval: 0.5)
        // Reads 0.01, 0.02, 0.04 and then 0.08 s apart: 0.16 and 0.32 would leave room for only six.
        let reads = fake.reads(of: 10)
        let gaps = zip(reads.dropFirst(), reads).map { $0.timeIntervalSince($1) }
        #expect(reads.count >= 7)
        #expect(gaps.dropFirst(3).allSatisfy { $0 < 0.12 })
    }

    @Test func `Windows after one that times out are left alone in that pass`() {
        let fake = FakeWindows([10: .zero, 11: .zero, 20: .zero])
        fake.stall([10])
        let scheduler = fake.scheduler()
        let results = submitAndWait(scheduler, [job(1, 10, 0), job(1, 11, 100), job(2, 20, 0)])
        #expect(results.map(\.busy) == [true, true, false])
        #expect(results.map(\.matched) == [false, false, true])
        #expect(fake.calls(to: 11).isEmpty)
        #expect(scheduler.isBusy(1))
        #expect(!scheduler.isBusy(2))
    }

    @Test func `Steps for a busy process are dropped`() {
        let fake = FakeWindows([10: .zero, 20: .zero])
        fake.stall([10])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        scheduler.step([job(1, 10, 10), job(2, 20, 10)])
        Thread.sleep(forTimeInterval: 0.05)
        #expect(fake.calls(to: 10) == ["read 10"])
        #expect(fake.calls(to: 20) == ["write 20"])
    }

    @Test func `A step the process does not answer makes it busy`() {
        let fake = FakeWindows([10: .zero, 11: .zero])
        fake.stall([10])
        let scheduler = fake.scheduler()
        scheduler.step([job(1, 10, 10)])
        Thread.sleep(forTimeInterval: 0.05)
        #expect(scheduler.isBusy(1))
        scheduler.step([job(1, 10, 20)])
        #expect(submitAndWait(scheduler, [job(1, 11, 0)]).map(\.busy) == [true])
        #expect(fake.calls(to: 10) == ["write 10"])
        #expect(fake.calls(to: 11).isEmpty)
    }

    @Test func `Once it answers, the newest frame of each window is written once`() {
        let fake = FakeWindows([10: CGRect(x: 0, y: 0, width: 100, height: 100), 11: .zero])
        fake.stall([10])
        let scheduler = fake.scheduler(backoff: 0.05)
        _ = submitAndWait(scheduler, [job(1, 10, 10)])
        _ = submitAndWait(scheduler, [job(1, 10, 20), job(1, 11, 20)])
        _ = submitAndWait(scheduler, [job(1, 10, 30)])
        #expect(fake.writes(to: 11).isEmpty, "held while the process is busy")
        fake.stall([])
        Thread.sleep(forTimeInterval: 0.3)
        #expect(!scheduler.isBusy(1))
        #expect(fake.writes(to: 10).map(\.minX) == [30])
        #expect(fake.writes(to: 11).map(\.minX) == [20])
        #expect(submitAndWait(scheduler, [job(1, 10, 40)]).map(\.matched) == [true])
    }

    @Test func `Cancel drops the frames held for a busy process`() {
        let fake = FakeWindows([10: .zero])
        fake.stall([10])
        let scheduler = fake.scheduler(backoff: 0.05)
        _ = submitAndWait(scheduler, [job(1, 10, 10)])
        scheduler.cancel()
        fake.stall([])
        Thread.sleep(forTimeInterval: 0.2)
        #expect(!scheduler.isBusy(1))
        #expect(fake.writes(to: 10).isEmpty)
    }

    @Test func `A busy process's refusals wait for it to answer before they count as unconfirmed`() {
        let fake = FakeWindows(minWidths: [20: 115, 21: 115])
        let scheduler = fake.scheduler(backoff: 0.05)
        _ = submitAndWait(scheduler, [job(1, 20, 0), job(2, 21, 200)])
        #expect(scheduler.unconfirmedMinimums == [20, 21])
        fake.stall([20])
        #expect(submitAndWait(scheduler, [job(1, 20, 0)]).map(\.busy) == [true])
        #expect(scheduler.unconfirmedMinimums == [21], "a pass now would only hold its frame")
        fake.stall([])
        Thread.sleep(forTimeInterval: 0.3)
        #expect(!scheduler.isBusy(1))
        #expect(scheduler.minimumSizes[20]?.width == 115, "the pass once it answers sees the refusal again")
        #expect(scheduler.unconfirmedMinimums == [21])
    }

    @Test func `A window that is gone is told from one whose app is busy`() {
        let fake = FakeWindows([20: .zero])
        fake.vanish([10])
        fake.stall([20])
        let scheduler = fake.scheduler()
        let results = submitAndWait(scheduler, [job(1, 10, 0), job(2, 20, 0)])
        #expect(results.map(\.gone) == [true, false])
        #expect(results.map(\.busy) == [false, true])
        #expect(results.map(\.got) == [nil, nil])
        #expect(results.map(\.written) == [true, false], "a window that is gone is written all the same, in case it is back")
        #expect(results.map(\.retried) == [false, false])
        #expect(!scheduler.isBusy(1))
        #expect(scheduler.isBusy(2))
    }
}
