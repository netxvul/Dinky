import AppKit
import DinkyLayout

// TEMPORARY: timing of a glide, to find where a strip scroll stutters. Printed when the glide ends.
final class GlideStats {
    static let shared = GlideStats()

    private let lock = NSLock()
    private var started: CFTimeInterval?
    private var ticks = 0
    private var gaps: [Double] = []
    private var stepTimes: [Double] = []
    private var jobs = 0
    private var events = 0
    private var eventTime = 0.0
    private var maxEvent = 0.0
    private var drains: [Int32: (count: Int, total: Double, max: Double, windows: Int)] = [:]

    var active: Bool { started != nil }

    func begin() {
        guard started == nil else { return }
        lock.withLock { drains = [:] }
        started = CACurrentMediaTime()
        (ticks, gaps, stepTimes, jobs, events, eventTime, maxEvent) = (0, [], [], 0, 0, 0, 0)
    }

    func tick(gap: Double?, step: Double, jobs count: Int) {
        guard active else { return }
        ticks += 1
        if let gap { gaps.append(gap) }
        stepTimes.append(step)
        jobs += count
    }

    func event(_ seconds: Double) {
        guard active else { return }
        events += 1
        eventTime += seconds
        maxEvent = max(maxEvent, seconds)
    }

    func drain(pid: Int32, seconds: Double, windows: Int) {
        lock.withLock {
            var d = drains[pid] ?? (0, 0, 0, 0)
            d.count += 1; d.total += seconds; d.max = max(d.max, seconds); d.windows = max(d.windows, windows)
            drains[pid] = d
        }
    }

    func end() {
        guard let started else { return }
        self.started = nil
        let total = (CACurrentMediaTime() - started) * 1000
        func ms(_ s: Double) -> String { String(format: "%.1f", s * 1000) }
        let sorted = gaps.sorted()
        let p90 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.9)]
        var line = String(format: "glide: %.0f ms, %d ticks, gap avg %@ p90 %@ max %@ ms, step max %@ ms, %d jobs; ",
                          total, ticks, ms(gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)), ms(p90),
                          ms(sorted.last ?? 0), ms(stepTimes.max() ?? 0), jobs)
        line += "window events \(events), \(ms(eventTime)) ms on main, max \(ms(maxEvent)) ms; apps:"
        let snapshot = lock.withLock { drains }
        for (pid, d) in snapshot.sorted(by: { $0.value.total > $1.value.total }) {
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "\(pid)"
            line += " \(name) \(d.count) drains of up to \(d.windows) windows, avg \(ms(d.total / Double(max(d.count, 1)))) max \(ms(d.max)) ms;"
        }
        print("\(stamp()) \(line)")
        fflush(stdout)
    }
}
