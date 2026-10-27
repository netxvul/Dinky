import DinkyLayout
import DinkyPrivate
import Foundation
import QuartzCore

// dinky's Dock scripting addition moves other apps' windows through Dock's privileged WindowServer connection,
// which dinky's own connection cannot do. It is available only when the payload has been injected into Dock (see
// scripts/build-sa.sh); every call is a no-op otherwise, so callers fall back to the Accessibility path. Main thread.
enum ScriptingAddition {
    /// Off while top-level `scripting-addition = false`. While off, nothing probes the socket or re-injects, so
    /// the whole path costs nothing and logs nothing — important when SIP is on and injection cannot work anyway.
    /// Set from config by the coordinator.
    static var enabled = false
    /// The installed injector. Run as root (passwordless sudo, see scripts/dinky-sudoers) it re-injects the payload.
    private static let loaderPath = "/Library/ScriptingAdditions/dinky.osax/Contents/MacOS/loader"
    private static var cachedAt: CFTimeInterval = -1
    private static var cached = false
    private static var cachedMoves = false
    private static var cachedOrders = false
    // The payload dies whenever Dock restarts, so dinky re-injects it on its own. These bound that: never more than
    // one attempt in flight, never before `nextAttemptAt`, and the interval doubles (to 5 min) whenever a freshly
    // injected payload dies again within 15 s, so a payload that somehow destabilised Dock cannot drive a restart loop.
    private static var lastReinjectAt: CFTimeInterval = -1
    private static var lastAliveAt: CFTimeInterval = -1
    private static var nextAttemptAt: CFTimeInterval = 0
    private static var backoff: Double = 30
    private static var reinjecting = false

    /// Whether the payload answers right now. Re-probed at most once a second; a dead socket kicks an async,
    /// rate-limited re-injection so the addition heals itself after a Dock restart.
    static var available: Bool {
        guard enabled else { return false }
        let now = CACurrentMediaTime()
        if now - cachedAt > 1 {
            cached = dinky_sa_available()
            // Asked each time too, as the payload Dock has can be replaced by a newer one without dinky restarting.
            cachedMoves = cached && dinky_sa_moves_windows()
            cachedOrders = cached && dinky_sa_orders_windows()
            cachedAt = now
            if cached { lastAliveAt = now }
        }
        if !cached { ensureLoaded() }
        return cached
    }

    /// Re-inject the payload if it is not answering. Async, rate-limited, safe to call often (and at startup).
    static func ensureLoaded() {
        guard enabled else { return }
        let now = CACurrentMediaTime()
        guard !reinjecting, now >= nextAttemptAt else { return }
        if dinky_sa_available() { lastAliveAt = now; return }
        let aliveSpan = lastAliveAt - lastReinjectAt
        if lastReinjectAt > 0, aliveSpan < 15 { backoff = min(backoff * 2, 300) } else { backoff = 30 }
        lastReinjectAt = now
        nextAttemptAt = now + backoff
        reinjecting = true
        DispatchQueue.global(qos: .utility).async {
            let ok = runLoader()
            DispatchQueue.main.async {
                reinjecting = false
                cachedAt = -1
                NSLog("dinky: scripting-addition reinject %@", ok ? "ok" : "failed")
            }
        }
    }

    private static func runLoader() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", loaderPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    /// Show each window's top-left at its frame's origin, in global top-left-origin coordinates, via a Dock
    /// transform. Purely visual: the real Accessibility frames are untouched, and a point may lie off-screen.
    static func transform(_ frames: [WindowID: CGRect]) {
        guard !frames.isEmpty else { return }
        var wids: [UInt32] = [], points: [CGPoint] = []
        wids.reserveCapacity(frames.count)
        points.reserveCapacity(frames.count)
        for (id, frame) in frames {
            wids.append(id)
            points.append(frame.origin)
        }
        dinky_sa_transform_batch(wids, points, Int32(wids.count))
    }

    /// Whether the payload Dock has can move windows (see `move`), as of `available`; one installed before it could
    /// only shows them through transforms.
    static var moves: Bool { cached && cachedMoves }

    /// Move each window's real frame so its top-left is at its frame's origin, in global top-left-origin coordinates,
    /// all in one message. Dock's connection is not clamped as Accessibility is, and no app falls behind the others;
    /// nor are the apps told, so their frames are written through Accessibility once a glide ends, which then finds
    /// the windows where they put them. A no-op with a payload that cannot.
    /// Each window's origin as last sent, so a frame of a glide or hold sends only those that moved (`forget`).
    private static var sent: [WindowID: CGPoint] = [:]

    /// Moves the windows to the origins of `frames`, those that moved half a point or more since last sent, or all with
    /// `fresh`; nothing when none did.
    static func move(_ frames: [WindowID: CGRect], fresh: Bool = false) {
        guard cachedMoves, !frames.isEmpty else { return }
        let wids = frames.keys.filter { id in
            fresh || sent[id].map { hypot($0.x - frames[id]!.minX, $0.y - frames[id]!.minY) >= 0.5 } ?? true
        }
        guard !wids.isEmpty else { return }
        let points = wids.map { frames[$0]!.origin }
        for (id, point) in zip(wids, points) { sent[id] = point }
        dinky_sa_move_batch(wids, points, Int32(wids.count))
    }

    /// Forgets the origins last sent for `ids`, or for every window, so the next move sends them whatever they are:
    /// a glide or hold setting off or ending, the windows maybe moved by other means meanwhile.
    static func forget(_ ids: [WindowID]? = nil) {
        guard let ids else { return sent = [:] }
        for id in ids { sent[id] = nil }
    }

    /// Window `id` shows at `origin`, as its move or resize events have it: one moved by other means than the last
    /// sent, half a point or more, is sent again by the next move, even mid-glide or held.
    static func noteShown(_ id: WindowID, at origin: CGPoint) {
        guard let last = sent[id], hypot(last.x - origin.x, last.y - origin.y) >= 0.5 else { return }
        sent[id] = nil
    }

    /// Whether the payload Dock has can order windows (see `order`), as of `available`; one installed before 0.4.0
    /// cannot, and windows are raised through Accessibility instead.
    static var orders: Bool { cached && cachedOrders }

    /// Clear the transforms, returning the windows to their real Accessibility positions.
    static func reset(_ ids: [WindowID]) {
        guard !ids.isEmpty else { return }
        forget(ids)
        var wids = ids
        dinky_sa_reset_batch(&wids, Int32(wids.count))
    }
}

// Holds a strip's Dock transforms until both the glide has ended and the real frames have landed, then clears them.
// Main thread.
final class SAGlide {
    private static let landingLimit: TimeInterval = 0.4
    private let onFinish: () -> Void
    private var glided = false
    private var landed = false
    private var done = false

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    /// The glide is over: clear once the real frames have landed, or after `landingLimit`.
    func glideEnded() {
        glided = true
        if landed { return finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.landingLimit) { [weak self] in self?.finish() }
    }

    /// The real frames have been written to their places and read back.
    func framesLanded() {
        landed = true
        if glided { finish() }
    }

    private func finish() {
        guard !done else { return }
        done = true
        onFinish()
    }
}
