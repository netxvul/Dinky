import CoreGraphics

// A scrolling strip glides every window through its own app, and apps move their windows at their own pace: one too
// slow to follow a glide frame by frame falls behind (see `FrameScheduler.isSlow`). A column of a slow app's window
// over a quick app's would come apart on the way, the quick one sliding in on its own while its column is still off
// the screen. So on every frame the quick windows of such a column keep with the slow one as the window server shows
// it: the slow window furthest behind goes on where the glide has it, and the others stay the same distance short of
// where the glide has them. A column all of slow or all of quick windows glides as it is.
public enum ColumnHold {
    /// How far, in points, the slow window may show from where the glide has it before its column waits for it.
    public static let slack: CGFloat = 1

    /// `frames`, where the glide has the strip's windows on screen this frame, with the quick windows of each column
    /// of `columns` that also has a window in `slow` held to the slow one furthest behind, as `shown` has it; and the
    /// windows held. A window missing from `frames`, or a slow one `shown` has nothing for, is left out of its column.
    public static func held(_ frames: [WindowID: CGRect], columns: [[WindowID]], slow: Set<WindowID>,
                            shown: (WindowID) -> CGRect?) -> (frames: [WindowID: CGRect], held: Set<WindowID>) {
        var result = frames, held: Set<WindowID> = []
        for column in columns {
            let ids = column.filter { frames[$0] != nil }
            let quick = ids.filter { !slow.contains($0) }
            guard ids.count > 1, !quick.isEmpty,
                  let dx = lag(of: ids.filter(slow.contains), frames: frames, shown: shown) else { continue }
            for id in quick {
                result[id] = frames[id]!.offsetBy(dx: -dx, dy: 0)
                held.insert(id)
            }
        }
        return (result, held)
    }

    /// How far short of its frame in `frames`, along x, the window of `ids` furthest from its frame shows; nil when
    /// every one shows within `slack` of its frame.
    static func lag(of ids: [WindowID], frames: [WindowID: CGRect], shown: (WindowID) -> CGRect?) -> CGFloat? {
        let lags = ids.compactMap { id in shown(id).map { frames[id]!.minX - $0.minX } }
        guard let worst = lags.max(by: { abs($0) < abs($1) }), abs(worst) > slack else { return nil }
        return worst
    }
}
